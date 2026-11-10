import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

/// Raised when a stored CAS session can no longer be exchanged for a service
/// ticket (the TGT was revoked or expired). Callers should fall back to a fresh
/// password login or ask the user to sign in again.
class SessionExpiredException implements Exception {
  const SessionExpiredException([this.message = '登录状态已过期，请重新登录']);

  final String message;

  @override
  String toString() => message;
}

class ServiceLoginResult {
  const ServiceLoginResult({required this.cookies, required this.finalUri});

  /// Merged cookie jar keyed by host. Values are the same `name=value; ...`
  /// header strings used by [AuthSession.cookies].
  final Map<String, String> cookies;
  final Uri finalUri;
}

/// Exchanges the CAS single-sign-on ticket stored in a saved auth session for
/// the cookies of another service (缴费大厅, 研究生系统...).
///
/// Verified flow (2026-11-10):
///   `GET https://pass.neu.edu.cn/tpass/login?service=<target>`
///   with the saved `pass.neu.edu.cn` cookies (`CASTGC=TGT-...`)
///   -> `302 target?ticket=ST-...`
///   -> target establishes its own session and sets cookies.
///
/// This is what makes saved sessions useful even when the user signed in via
/// the webview and no password was ever typed: electricity queries and
/// timetable sync no longer require the plain-text password.
class NeuServiceSession {
  NeuServiceSession({Dio? dio}) : _dio = dio ?? _buildDio();

  final Dio _dio;

  static Dio _buildDio() {
    return Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 25),
        sendTimeout: const Duration(seconds: 15),
        responseType: ResponseType.plain,
        followRedirects: false,
        validateStatus: (status) => status != null && status < 400,
        headers: {
          'User-Agent':
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
              'AppleWebKit/537.36 (KHTML, like Gecko) '
              'Chrome/157.0.0.0 Safari/537.36 Edg/157.0.0.0',
          'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.6',
        },
      ),
    );
  }

  /// Returns a merged jar (including every original host plus the target
  /// service's fresh cookies). Throws [SessionExpiredException] when CAS shows
  /// its login form again instead of issuing a ticket.
  Future<ServiceLoginResult> establish({
    required Map<String, String> sessionCookies,
    required String service,
    required String targetHost,
  }) async {
    final jar = parseCookieJar(sessionCookies);
    var uri = Uri.https('pass.neu.edu.cn', '/tpass/login', {
      'service': service,
    });

    for (var hop = 0; hop < 12; hop++) {
      final Response<String> response;
      try {
        response = await _dio.getUri<String>(
          uri,
          options: Options(headers: _headerFor(jar, uri.host)),
        );
      } on DioException catch (error) {
        throw SessionExpiredException(
          '无法连接学校统一身份认证：${error.message ?? error.type.name}',
        );
      }

      _captureCookies(jar, uri, response.headers);
      final status = response.statusCode ?? 0;
      final location = response.headers.value('location');
      debugPrint('[sso] $status ${uri.host}${uri.path} -> ${location ?? ""}');

      if (location != null && location.isNotEmpty) {
        uri = uri.resolve(location);
        continue;
      }

      if (uri.host == targetHost) {
        return ServiceLoginResult(cookies: exportCookieJar(jar), finalUri: uri);
      }

      // Landing back on the CAS form means the stored TGT was rejected.
      final body = response.data ?? '';
      if (uri.host == 'pass.neu.edu.cn' &&
          (body.contains('name="lt"') ||
              body.contains("name='lt'") ||
              body.contains('name="execution"'))) {
        throw const SessionExpiredException();
      }

      throw SessionExpiredException('登录跳转未到达目标服务（停在 ${uri.host}）。');
    }

    throw const SessionExpiredException('登录跳转次数过多，请重新登录。');
  }

  static Map<String, Map<String, String>> parseCookieJar(
    Map<String, String> cookies,
  ) {
    final jar = <String, Map<String, String>>{};
    for (final entry in cookies.entries) {
      final host = entry.key.trim().replaceFirst(RegExp(r'^\.'), '');
      if (host.isEmpty) continue;
      final map = jar.putIfAbsent(host, () => <String, String>{});
      for (final part in entry.value.split(';')) {
        final pair = part.trim();
        if (pair.isEmpty) continue;
        final equals = pair.indexOf('=');
        if (equals <= 0) continue;
        final name = pair.substring(0, equals).trim();
        final value = pair.substring(equals + 1).trim();
        if (name.isEmpty || value.isEmpty) continue;
        map[name] = value;
      }
    }
    return jar;
  }

  static Map<String, String> exportCookieJar(
    Map<String, Map<String, String>> jar,
  ) {
    final result = <String, String>{};
    for (final entry in jar.entries) {
      if (entry.value.isEmpty) continue;
      result[entry.key] = entry.value.entries
          .map((pair) => '${pair.key}=${pair.value}')
          .join('; ');
    }
    return result;
  }

  /// Cookies valid for [host] as a plain `name=value; ...` header value.
  static String? cookieHeaderFor(
    Map<String, Map<String, String>> jar,
    String host,
  ) {
    final values = <String>[];
    final seen = <String>{};
    for (final entry in jar.entries) {
      final domain = entry.key;
      final matches =
          host == domain ||
          host.endsWith('.$domain') ||
          domain.endsWith('.$host');
      if (!matches) continue;
      for (final pair in entry.value.entries) {
        if (seen.add(pair.key)) values.add('${pair.key}=${pair.value}');
      }
    }
    if (values.isEmpty) return null;
    return values.join('; ');
  }

  /// Cookie name/value pairs valid for [host], convenient for legacy clients
  /// that keep a single-host jar.
  static Map<String, String> cookieMapFor(
    Map<String, Map<String, String>> jar,
    String host,
  ) {
    final result = <String, String>{};
    for (final entry in jar.entries) {
      final domain = entry.key;
      final matches =
          host == domain ||
          host.endsWith('.$domain') ||
          domain.endsWith('.$host');
      if (!matches) continue;
      result.addAll(entry.value);
    }
    return result;
  }

  static Map<String, String>? _headerFor(
    Map<String, Map<String, String>> jar,
    String host,
  ) {
    final header = cookieHeaderFor(jar, host);
    return header == null ? null : {'cookie': header};
  }

  static void _captureCookies(
    Map<String, Map<String, String>> jar,
    Uri uri,
    Headers headers,
  ) {
    final rawHeaders = headers['set-cookie'];
    if (rawHeaders == null || rawHeaders.isEmpty) return;
    for (final raw in rawHeaders) {
      final parts = raw.split(RegExp(r',(?=[^;]+=)'));
      for (final part in parts) {
        final first = part.split(';').first.trim();
        final equals = first.indexOf('=');
        if (equals <= 0) continue;
        final name = first.substring(0, equals).trim();
        final value = first.substring(equals + 1).trim();
        if (name.isEmpty || value.isEmpty) continue;
        jar.putIfAbsent(uri.host, () => {})[name] = value;
      }
    }
  }
}
