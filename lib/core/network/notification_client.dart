import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../../core/auth/auth_session.dart';
import '../../core/auth/credential_store.dart';
import '../../core/network/neu_cas_client.dart';
import '../../core/network/neu_service_session.dart';
import 'in_flight_request.dart';
import 'notification_models.dart';

/// 通知接口错误（鉴权失效 / 网络 / 业务失败）。
class NotificationQueryException implements Exception {
  const NotificationQueryException(this.code, this.message, [this.cause]);

  final String code;
  final String message;
  final Object? cause;

  @override
  String toString() => 'NotificationQueryException($code): $message';
}

/// 校园消息中心（personal.neu.edu.cn ucs）只读客户端。
///
/// 阶段0 已实测：CAS 默认登录后的 cookies 含 `personal.neu.edu.cn`，之后所有
/// ucs API 只需 GET + cookie + `X-Requested-With: XMLHttpRequest`，无需 CSRF。
class NotificationClient {
  NotificationClient(this._session, {Dio? dio, CredentialStore? credentials})
    : _dio = dio ?? _buildDio(),
      _credentials = credentials ?? const SecureCredentialStore();

  final AuthSession _session;
  final Dio _dio;
  final CredentialStore _credentials;

  static const _host = 'personal.neu.edu.cn';
  static const _base = 'https://personal.neu.edu.cn/portal/ucs/frontend/msg';
  static const _browserUa =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
      'AppleWebKit/537.36 (KHTML, like Gecko) '
      'Chrome/157.0.0.0 Safari/537.36 Edg/157.0.0.0';

  static Dio _buildDio() {
    return Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 20),
        sendTimeout: const Duration(seconds: 15),
        responseType: ResponseType.plain,
        headers: {
          'User-Agent': _browserUa,
          'Accept': 'application/json, text/plain, */*',
          'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.6',
        },
        validateStatus: (status) => status != null && status < 500,
      ),
    );
  }

  factory NotificationClient.fromSession(AuthSession session, {Dio? dio}) {
    return NotificationClient(session, dio: dio);
  }

  String? _cookieHeader;
  final _counts = InFlightRequest<NotificationCounts>();
  final _firstPage = InFlightRequest<List<AppNotification>>();
  final _sessionRefresh = InFlightRequest<void>();

  void close() => _dio.close(force: true);

  String get _cookie {
    return _cookieHeader ??=
        NeuServiceSession.cookieHeaderFor(
          NeuServiceSession.parseCookieJar(_session.cookies),
          _host,
        ) ??
        '';
  }

  Map<String, String> get _headers => {
    if (_cookie.isNotEmpty) 'Cookie': _cookie,
    'X-Requested-With': 'XMLHttpRequest',
    'Referer': 'https://personal.neu.edu.cn/portal/',
  };

  /// 拉取未读统计。
  Future<NotificationCounts> counts() => _counts.run(() async {
    final body = await _getJson('/countData');
    final root = _asMap(body);
    _ensureBusinessOk(root);
    return parseCounts(root);
  });

  /// 拉取一页通知（type=3：APP 消息推送）。实际每页 10 条。
  Future<List<AppNotification>> list({int page = 1}) =>
      page == 1 ? _firstPage.run(() => _list(1)) : _list(page);

  Future<List<AppNotification>> _list(int page) async {
    final body = await _getJson(
      '/index',
      query: {'type': '3', 'pageNum': '$page', 'pageSize': '20'},
    );
    final root = _asMap(body);
    _ensureBusinessOk(root);
    return parseIndex(root);
  }

  /// 标记已读：实测接口为 PUT `/frontend/msg/read?ucs_id=<log_id>`。
  Future<bool> markRead(List<int> logIds) async {
    if (logIds.isEmpty) return true;
    var allOk = true;
    for (final id in logIds) {
      try {
        var response = await _dio.put<String>(
          '$_base/read',
          queryParameters: {'ucs_id': '$id'},
          options: Options(headers: _headers),
        );
        if (_looksExpired(response)) {
          await _refreshSession();
          response = await _dio.put<String>(
            '$_base/read',
            queryParameters: {'ucs_id': '$id'},
            options: Options(headers: _headers),
          );
        }
        final root = _asMap(_decode(response.data));
        if (_asInt(root['e']) != 0) {
          debugPrint('[notify] markRead $id -> ${response.data}');
          allOk = false;
        }
      } catch (error) {
        debugPrint('[notify] markRead failed for $id: $error');
        allOk = false;
      }
    }
    return allOk;
  }

  Future<Object?> _getJson(String path, {Map<String, String>? query}) async {
    final uri = Uri.parse('$_base$path').replace(queryParameters: query);
    var response = await _dio.get<String>(
      uri.toString(),
      options: Options(headers: _headers),
    );
    if (_looksExpired(response)) {
      await _refreshSession();
      response = await _dio.get<String>(
        uri.toString(),
        options: Options(headers: _headers),
      );
      if (_looksExpired(response)) {
        throw const NotificationQueryException('session', '消息中心会话已过期，请重新登录');
      }
    }
    final status = response.statusCode ?? 0;
    if (status >= 400) {
      throw NotificationQueryException('http', '通知接口返回 HTTP $status');
    }
    return _decode(response.data);
  }

  bool _looksExpired(Response<String> response) {
    final status = response.statusCode ?? 0;
    if (status == 401 || status == 403) return true;
    final body = (response.data ?? '').trimLeft();
    if (body.startsWith('<')) return true;
    if (body.contains('pass.neu.edu.cn') || body.contains('/tpass/login')) {
      return true;
    }
    final decoded = _decode(body);
    final root = _asMap(decoded);
    if (root['hasLogin'] == false) return true;
    final message = (root['m'] ?? root['message'] ?? '').toString();
    if (message.contains('未登录') || message.contains('登录超时')) return true;
    final businessCode = _asInt(root['e']);
    if (businessCode != null &&
        businessCode != 0 &&
        (message.contains('登录') || message.contains('失效'))) {
      // 服务端把登录失效放在业务码里返回，例如
      // {"e":xxx,"m":"登录信息已失效，请重新登录"}。
      return true;
    }
    return false;
  }

  Future<void> _refreshSession() => _sessionRefresh.run(_renewSession);

  Future<void> _renewSession() async {
    // 优先用已保存的 CAS 会话换取 personal 门户的 cookies：WebView 登录的用户
    // 往往没有保存密码，只有 TGT，这条路才是可用的。
    try {
      final result = await NeuServiceSession().establish(
        sessionCookies: _session.cookies,
        service: NeuCasClient.service,
        targetHost: _host,
      );
      final header = NeuServiceSession.cookieHeaderFor(
        NeuServiceSession.parseCookieJar(result.cookies),
        _host,
      );
      if (header != null && header.isNotEmpty) {
        _cookieHeader = header;
        return;
      }
    } catch (error) {
      debugPrint('[notify] sso refresh failed: $error');
    }
    final credentials = await _credentials.read();
    final password = credentials?.password;
    if (credentials == null || password == null || password.isEmpty) {
      throw const NotificationQueryException('session', '本地没有保存的密码，无法刷新消息中心会话');
    }
    final result = await NeuCasClient().login(
      username: credentials.username,
      password: password,
    );
    final header = NeuServiceSession.cookieHeaderFor(
      NeuServiceSession.parseCookieJar(result.cookies),
      _host,
    );
    if (header == null || header.isEmpty) {
      throw const NotificationQueryException('session', '刷新消息中心会话失败');
    }
    _cookieHeader = header;
  }

  void _ensureBusinessOk(Map<String, dynamic> root) {
    final error = _asInt(root['e']);
    if (error != null && error != 0) {
      throw NotificationQueryException(
        'business',
        (root['m'] ?? '通知接口返回错误 $error').toString(),
      );
    }
  }
}

Object? _decode(Object? payload) {
  if (payload == null) return null;
  if (payload is! String) return payload;
  final text = payload.trim();
  if (text.isEmpty) return null;
  try {
    return jsonDecode(text);
  } catch (_) {
    return text;
  }
}

Map<String, dynamic> _asMap(Object? value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) return Map<String, dynamic>.from(value);
  return const <String, dynamic>{};
}

int? _asInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value.trim());
  return null;
}
