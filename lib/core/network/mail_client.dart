import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../auth/auth_session.dart';
import 'neu_cas_client.dart';
import 'neu_service_session.dart';

/// 邮件服务（Coremail）会话无法继续使用：sid 失效 / 需要重新 SSO。
class MailSessionExpired implements Exception {
  const MailSessionExpired([this.message = '邮箱登录状态已过期']);

  final String message;

  @override
  String toString() => message;
}

/// 邮件接口返回了非 `S_OK` 的业务错误。
class MailException implements Exception {
  const MailException(this.code, [this.message = '邮件服务返回错误']);

  final String code;
  final String message;

  @override
  String toString() => '$message（$code）';
}

/// Coremail 侧登录态：`sid` 与发往 `mails.neu.edu.cn` 的 Cookie 头。
@immutable
class CoremailSession {
  const CoremailSession({required this.sid, required this.cookieHeader});

  final String sid;
  final String cookieHeader;
}

/// 收件箱列表项（只读）。
@immutable
class MailSummary {
  const MailSummary({
    required this.id,
    required this.subject,
    required this.from,
    required this.to,
    required this.receivedDate,
    required this.read,
    required this.hasAttachment,
  });

  final String id;
  final String subject;
  final String from;
  final String to;
  final DateTime? receivedDate;
  final bool read;
  final bool hasAttachment;
}

/// 附件元数据（仅名称/大小，不下载）。
@immutable
class MailAttachment {
  const MailAttachment({required this.name, this.size});

  final String name;
  final int? size;
}

/// 读信元数据（不含正文，正文由 WebView 打开）。
@immutable
class MailDetail {
  const MailDetail({
    required this.subject,
    required this.from,
    required this.to,
    required this.date,
    required this.attachments,
  });

  final String subject;
  final String from;
  final String to;
  final DateTime? date;
  final List<MailAttachment> attachments;
}

/// 原生 Coremail 只读邮件客户端。
///
/// 只读能力限定为：收件箱列表 + 读信元数据。正文接口未公开，正文在详情页
/// 用 WebView 打开官方页面。
class MailClient {
  MailClient(this.session, {Dio? dio}) : _dio = dio ?? _buildDio();

  final CoremailSession session;
  final Dio _dio;

  static const ssoService =
      'https://mails.neu.edu.cn/coremail/cmcu_addon/dbdxsso.jsp';
  static const _host = 'mails.neu.edu.cn';
  static const _indexUrl = 'https://mails.neu.edu.cn/coremail/XT/index.jsp';
  static const _jsonBase = 'https://mails.neu.edu.cn/coremail/s/json';
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

  /// 用已保存的 CAS 会话换 Coremail sid + Cookie（推荐，无需密码）。
  static Future<MailClient> fromSession(AuthSession authSession) async {
    final result = await NeuServiceSession().establish(
      sessionCookies: authSession.cookies,
      service: ssoService,
      targetHost: _host,
    );
    return MailClient(_sessionFrom(result.cookies, result.finalUri));
  }

  /// 回退：用保存的账号密码重新走 CAS 登录拿到 Coremail 会话。
  static Future<MailClient> fromCredentials({
    required String username,
    required String password,
  }) async {
    final result = await NeuCasClient().login(
      username: username,
      password: password,
      service: ssoService,
    );
    return MailClient(_sessionFrom(result.cookies, result.finalUri));
  }

  static CoremailSession _sessionFrom(
    Map<String, String> cookies,
    Uri finalUri,
  ) {
    final jar = NeuServiceSession.parseCookieJar(cookies);
    final header = NeuServiceSession.cookieHeaderFor(jar, _host) ?? '';
    var sid = _sidFromUri(finalUri) ?? '';
    if (sid.isEmpty) {
      sid = _sidFromCookieHeader(header) ?? '';
    }
    if (sid.isEmpty) {
      throw const MailSessionExpired('未能获取邮箱会话（缺少 sid）');
    }
    return CoremailSession(sid: sid, cookieHeader: header);
  }

  static String? _sidFromUri(Uri uri) {
    final value = uri.queryParameters['sid'];
    return (value == null || value.isEmpty) ? null : value;
  }

  static String? _sidFromCookieHeader(String header) {
    for (final part in header.split(';')) {
      final trimmed = part.trim();
      if (!trimmed.startsWith('Coremail.sid=')) continue;
      final value = trimmed.substring('Coremail.sid='.length);
      if (value.isNotEmpty) return value;
    }
    return null;
  }

  Map<String, String> get _headers => {
        if (session.cookieHeader.isNotEmpty) 'Cookie': session.cookieHeader,
        'X-Requested-With': 'XMLHttpRequest',
        'Referer': '$_indexUrl?sid=${session.sid}',
      };

  /// 收件箱（fid=1）全部邮件，按日期倒序。接口一次返回全部，不分页。
  Future<List<MailSummary>> list() async {
    final uri = Uri.parse(_jsonBase).replace(
      queryParameters: {
        'func': 'mbox:listMessages',
        'sid': session.sid,
        'fid': '1',
        'order': 'date',
        'desc': '1',
      },
    );
    final body = await _get(uri);
    return parseListResponse(body);
  }

  /// 读信元数据（不含正文）。
  Future<MailDetail> read(String mid) async {
    final uri = Uri.parse(_jsonBase).replace(
      queryParameters: {
        'func': 'mbox:readMessage',
        'sid': session.sid,
        'mid': mid,
        'mode': 'html',
        'header': '1',
      },
    );
    final body = await _get(uri);
    return parseDetailResponse(body);
  }

  /// 详情页 WebView 打开的信件地址（hash 路由）。
  String webUrlFor(String mid) =>
      '$_indexUrl?sid=${session.sid}#mail.read?mid=$mid';

  /// 兜底时打开的官方邮箱首页。
  String get inboxWebUrl => '$_indexUrl?sid=${session.sid}';

  Future<String> _get(Uri uri) async {
    final Response<String> response;
    try {
      response = await _dio.getUri<String>(
        uri,
        options: Options(headers: _headers),
      );
    } on DioException catch (error) {
      throw MailException(
        'NETWORK',
        '无法连接邮箱服务：${error.message ?? error.type.name}',
      );
    }
    final body = response.data ?? '';
    if ((response.statusCode ?? 0) >= 400) {
      throw MailException('HTTP${response.statusCode}', '邮箱服务返回错误');
    }
    return body;
  }

  // ───────────────────────── 解析（可单测） ─────────────────────────

  @visibleForTesting
  static List<MailSummary> parseListResponse(String body) {
    final root = _decodeRoot(body);
    final raw = root['var'];
    final items = <MailSummary>[];
    if (raw is List) {
      for (final entry in raw) {
        if (entry is! Map) continue;
        final map = entry.cast<String, dynamic>();
        items.add(
          MailSummary(
            id: '${map['id'] ?? ''}',
            subject: _subjectOf(map['subject']),
            from: _addressOf(map['from']),
            to: _addressOf(map['to']),
            receivedDate: _dateOf(map['receivedDate'] ?? map['sentDate']),
            read: _readFlag(map['flags']),
            hasAttachment: _attachmentFlag(map),
          ),
        );
      }
    }
    return items;
  }

  @visibleForTesting
  static MailDetail parseDetailResponse(String body) {
    final root = _decodeRoot(body);
    final raw = root['var'];
    final map = raw is Map ? raw.cast<String, dynamic>() : <String, dynamic>{};
    final attachments = <MailAttachment>[];
    final rawAttachments = map['attachments'];
    if (rawAttachments is List) {
      for (final entry in rawAttachments) {
        if (entry is! Map) continue;
        final a = entry.cast<String, dynamic>();
        final name = '${a['name'] ?? a['filename'] ?? a['fileName'] ?? ''}'
            .trim();
        if (name.isEmpty) continue;
        final size = a['size'];
        attachments.add(
          MailAttachment(
            name: name,
            size: size is int ? size : int.tryParse('${size ?? ''}'),
          ),
        );
      }
    }
    return MailDetail(
      subject: _subjectOf(map['subject']),
      from: _addressOf(map['from']),
      to: _addressOf(map['to']),
      date: _dateOf(map['sentDate'] ?? map['receivedDate']),
      attachments: attachments,
    );
  }

  static Map<String, dynamic> _decodeRoot(String body) {
    Object? decoded;
    try {
      decoded = jsonDecode(body);
    } catch (_) {
      throw const MailException('PARSE', '邮箱返回内容无法解析');
    }
    if (decoded is! Map) {
      throw const MailException('PARSE', '邮箱返回格式异常');
    }
    final root = decoded.cast<String, dynamic>();
    final code = '${root['code'] ?? ''}';
    if (code.isNotEmpty && code != 'S_OK') {
      if (code.contains('SECURITY') ||
          code.contains('SESSION') ||
          code == 'FA_SECURITY' ||
          code == 'FR_INVALID_SESSION') {
        throw const MailSessionExpired();
      }
      throw MailException(code);
    }
    return root;
  }

  static String _subjectOf(Object? value) {
    if (value is String) return value.trim();
    if (value is Map) {
      return '${value['subject'] ?? value['name'] ?? ''}'.trim();
    }
    return '${value ?? ''}'.trim();
  }

  /// from/to 在不同接口里可能是字符串，也可能是 `[{name,email}]`。
  static String _addressOf(Object? value) {
    if (value == null) return '';
    if (value is String) return value.trim();
    if (value is List) {
      final names = <String>[];
      for (final entry in value) {
        final one = _addressOf(entry);
        if (one.isNotEmpty) names.add(one);
      }
      return names.join('、');
    }
    if (value is Map) {
      final name = '${value['name'] ?? value['personal'] ?? ''}'.trim();
      final email =
          '${value['email'] ?? value['address'] ?? value['mail'] ?? ''}'.trim();
      if (name.isEmpty) return email;
      if (email.isEmpty || name == email) return name;
      return '$name <$email>';
    }
    return '$value'.trim();
  }

  static bool _readFlag(Object? flags) {
    if (flags is Map) {
      final read = flags['read'];
      if (read is bool) return read;
      if (read is num) return read != 0;
      return '${read ?? ''}'.toLowerCase() == 'true';
    }
    return false;
  }

  static bool _attachmentFlag(Map<String, dynamic> map) {
    for (final key in const ['attachments', 'attachment', 'attachList']) {
      final value = map[key];
      if (value is List && value.isNotEmpty) return true;
      if (value is Map && value.isNotEmpty) return true;
    }
    final has = map['hasAttachment'];
    return has == true || '${has ?? ''}'.toLowerCase() == 'true';
  }

  static DateTime? _dateOf(Object? value) {
    if (value == null) return null;
    if (value is num) {
      return _fromEpoch(value.toInt());
    }
    final text = '$value'.trim();
    if (text.isEmpty) return null;
    final asNumber = int.tryParse(text);
    if (asNumber != null) return _fromEpoch(asNumber);
    return DateTime.tryParse(text);
  }

  static DateTime? _fromEpoch(int value) {
    if (value <= 0) return null;
    // Coremail 通常返回毫秒时间戳；兼容秒级。
    final millis = value < 100000000000 ? value * 1000 : value;
    return DateTime.fromMillisecondsSinceEpoch(millis);
  }
}
