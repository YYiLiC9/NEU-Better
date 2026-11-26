import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../auth/auth_session.dart';
import '../crypto/rsa_encryptor.dart';

/// e码通二维码数据（原生接口 `/ecode/api/qr-code`）。
class EcodeQr {
  const EcodeQr({
    required this.code,
    required this.createTime,
    required this.invalidTime,
    this.refreshedCookie,
  });

  /// 二维码内容（`NEU...` 字符串）。
  final String code;
  final DateTime createTime;
  final DateTime invalidTime;

  /// 服务端在响应中续期后的 Cookie；没有变化时为 null。
  final String? refreshedCookie;

  Duration get lifetime => invalidTime.difference(createTime);
}

class EcodeException implements Exception {
  const EcodeException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// 明确的登录/会话失效（只在这种情况下才提示用户重新登录）。
class EcodeAuthException extends EcodeException {
  const EcodeAuthException(super.message);
}

/// 网络、超时、服务端 5xx/429 等临时故障，不应被当成登录失效。
class EcodeTransientException extends EcodeException {
  const EcodeTransientException(super.message);
}

/// 原生 e码通接口客户端：CAS 登录 → ecode SESSION Cookie → 拉取二维码。
class EcodeClient {
  EcodeClient({Dio? dio})
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              followRedirects: false,
              responseType: ResponseType.plain,
              validateStatus: (s) => s != null && s < 500,
              connectTimeout: const Duration(seconds: 10),
              receiveTimeout: const Duration(seconds: 10),
            ),
          );

  final Dio _dio;

  static const service = 'https://ecode.neu.edu.cn/ecode/api/sso/login';
  static const _apiBase = 'https://ecode.neu.edu.cn/ecode/api';

  /// 用统一身份账号密码登录并返回 ecode Cookie 串。
  Future<String> login({
    required String username,
    required String password,
  }) async {
    final jar = <String, String>{};
    String cookieHeader() =>
        jar.entries.map((e) => '${e.key}=${e.value}').join('; ');
    void absorb(Response<dynamic> r) {
      final raw = r.headers.map['set-cookie'];
      if (raw == null) return;
      for (final line in raw) {
        final first = line.split(';').first.trim();
        final i = first.indexOf('=');
        if (i > 0) jar[first.substring(0, i)] = first.substring(i + 1);
      }
    }

    final loginUrl =
        'https://pass.neu.edu.cn/tpass/login?service=${Uri.encodeQueryComponent(service)}';
    var r = await _dio.get<String>(loginUrl);
    absorb(r);
    final body = r.data ?? '';
    String pick(String name) {
      final m =
          RegExp('name="$name"[^>]*value="([^"]*)"').firstMatch(body) ??
          RegExp('value="([^"]*)"[^>]*name="$name"').firstMatch(body);
      return m?.group(1) ?? '';
    }

    final rsa = NeuRsaEncryptor.encrypt('$username$password');
    r = await _dio.post<String>(
      loginUrl,
      data: {
        'un': username,
        'pd': '',
        'rsa': rsa,
        'ul': username.length.toString(),
        'pl': password.length.toString(),
        'lt': pick('lt'),
        'execution': pick('execution'),
        '_eventId': 'submit',
      },
      options: Options(
        contentType: Headers.formUrlEncodedContentType,
        headers: {'Cookie': cookieHeader()},
      ),
    );
    absorb(r);
    await _follow(r, jar, absorb);
    if (!jar.containsKey('SESSION')) {
      throw const EcodeException('e码通登录失败，请稍后重试');
    }
    return cookieHeader();
  }

  /// 用已保存的 CAS 会话 Cookie（pass 域，含 CASTGC）走 SSO，无需密码。
  Future<String> loginWithPassCookie(String passCookies) async {
    final jar = <String, String>{};
    for (final part in passCookies.split(';')) {
      final t = part.trim();
      final i = t.indexOf('=');
      if (i > 0) jar[t.substring(0, i)] = t.substring(i + 1);
    }
    String cookieHeader() =>
        jar.entries.map((e) => '${e.key}=${e.value}').join('; ');
    void absorb(Response<dynamic> r) {
      final raw = r.headers.map['set-cookie'];
      if (raw == null) return;
      for (final line in raw) {
        final first = line.split(';').first.trim();
        final i = first.indexOf('=');
        if (i > 0) jar[first.substring(0, i)] = first.substring(i + 1);
      }
    }

    final r = await _dio.get<String>(
      service,
      options: Options(headers: {'Cookie': cookieHeader()}),
    );
    absorb(r);
    await _follow(r, jar, absorb);
    if (!jar.containsKey('SESSION')) {
      throw const EcodeException('e码通会话已失效');
    }
    return cookieHeader();
  }

  Future<void> _follow(
    Response<dynamic> start,
    Map<String, String> jar,
    void Function(Response<dynamic>) absorb,
  ) async {
    var r = start;
    var uri = r.realUri;
    var hop = 0;
    while (r.statusCode != null &&
        r.statusCode! >= 300 &&
        r.statusCode! < 400 &&
        hop < 12) {
      hop++;
      final loc = r.headers.value('location');
      if (loc == null || loc.isEmpty) break;
      uri = Uri.parse(loc).isAbsolute ? Uri.parse(loc) : uri.resolve(loc);
      r = await _dio.get<String>(
        uri.toString(),
        options: Options(
          headers: {
            'Cookie': jar.entries.map((e) => '${e.key}=${e.value}').join('; '),
          },
        ),
      );
      absorb(r);
      if (uri.path == '/ecode/api') break;
    }
  }

  /// 拉取当前有效二维码；认证失败与临时故障分别抛不同类型。
  Future<EcodeQr> fetchQr(String cookie) async {
    Response<String> r;
    try {
      r = await _dio.get<String>(
        '$_apiBase/qr-code',
        options: Options(
          headers: {
            'Cookie': cookie,
            'Accept': 'application/json',
            'X-Requested-With': 'XMLHttpRequest',
          },
        ),
      );
    } on DioException catch (error) {
      final status = error.response?.statusCode;
      if (status == 401 || status == 403) {
        throw const EcodeAuthException('e码通登录状态已失效');
      }
      throw EcodeTransientException(_networkMessage(error));
    }
    if (r.statusCode == 401 || r.statusCode == 403) {
      throw const EcodeAuthException('e码通登录状态已失效');
    }
    if (r.statusCode == 429 ||
        (r.statusCode != null && r.statusCode! >= 500)) {
      throw EcodeTransientException('e码通服务暂时不可用（HTTP ${r.statusCode}）');
    }
    if (r.statusCode != 200) {
      throw EcodeTransientException('获取二维码失败（HTTP ${r.statusCode}）');
    }
    final Map<String, dynamic> decoded;
    try {
      final raw = jsonDecode(r.data ?? '{}');
      decoded = raw is Map<String, dynamic> ? raw : <String, dynamic>{};
    } on FormatException {
      throw const EcodeTransientException('二维码数据格式异常');
    }
    final data = decoded['data'];
    if (data is! List || data.isEmpty) {
      throw const EcodeTransientException('二维码数据为空');
    }
    final attrs = (data.first is Map)
        ? (data.first as Map)['attributes']
        : null;
    if (attrs is! Map) {
      throw const EcodeTransientException('二维码数据格式异常');
    }
    final code = attrs['qrCode'];
    if (code is! String || code.isEmpty) {
      throw const EcodeTransientException('未获取到有效二维码');
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    final create = int.tryParse('${attrs['createTime'] ?? ''}') ?? now;
    final invalid =
        int.tryParse('${attrs['qrInvalidTime'] ?? ''}') ?? (now + 10000);
    final jar = <String, String>{};
    for (final part in cookie.split(';')) {
      final t = part.trim();
      final i = t.indexOf('=');
      if (i > 0) jar[t.substring(0, i)] = t.substring(i + 1);
    }
    final setCookies = r.headers.map['set-cookie'];
    if (setCookies != null && setCookies.isNotEmpty) {
      for (final line in setCookies) {
        final first = line.split(';').first.trim();
        final i = first.indexOf('=');
        if (i > 0) {
          jar[first.substring(0, i)] = first.substring(i + 1);
        }
      }
    }
    final merged = jar.entries.map((e) => '${e.key}=${e.value}').join('; ');
    return EcodeQr(
      code: code,
      createTime: DateTime.fromMillisecondsSinceEpoch(create),
      invalidTime: DateTime.fromMillisecondsSinceEpoch(invalid),
      refreshedCookie: merged == cookie ? null : merged,
    );
  }

  String _networkMessage(DioException error) {
    final text = error.toString();
    if (text.contains('Timeout') || error.type == DioExceptionType.connectionTimeout) {
      return '连接 e码通服务超时';
    }
    return '网络连接失败，请检查网络后重试';
  }
}

/// ecode Cookie 持久化（仅 ecode 会话）。
class EcodeCookieStore {
  const EcodeCookieStore({this.studentId});

  final String? studentId;

  static const _storage = FlutterSecureStorage();
  String get _key =>
      'neu_better.ecode.cookie.v1${studentId == null ? '' : '.${studentId!}'}';

  Future<String?> read() async {
    try {
      final value = await _storage
          .read(key: _key)
          .timeout(const Duration(seconds: 3));
      return (value == null || value.isEmpty) ? null : value;
    } catch (_) {
      return null;
    }
  }

  Future<void> save(String cookie) async {
    try {
      await _storage
          .write(key: _key, value: cookie)
          .timeout(const Duration(seconds: 3));
    } catch (_) {}
  }

  Future<void> clear() async {
    try {
      await _storage.delete(key: _key).timeout(const Duration(seconds: 3));
    } catch (_) {}
  }
}

/// 由 [AuthSession] 取 pass 域 CAS Cookie（可能为空）。
String passCookieOf(AuthSession session) {
  return session.cookies['pass.neu.edu.cn'] ?? '';
}
