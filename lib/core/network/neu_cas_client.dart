import 'package:dio/dio.dart';

import '../auth/auth_exception.dart';
import '../crypto/rsa_encryptor.dart';

class CasLoginResult {
  const CasLoginResult({required this.cookies, required this.finalUri});

  /// Cookie header values keyed by host.
  final Map<String, String> cookies;
  final Uri finalUri;
}

abstract interface class CasClient {
  Future<CasLoginResult> login({
    required String username,
    required String password,
  });
}

/// Native client for the NEU CAS page at pass.neu.edu.cn.
///
/// The flow is deliberately done one redirect at a time so every `Set-Cookie`
/// header is captured. A browser is only needed when the school asks for an
/// additional device/QR verification.
class NeuCasClient implements CasClient {
  NeuCasClient({Dio? dio}) : _dio = dio ?? _buildDio();

  static const service =
      'https://personal.neu.edu.cn/portal/manage/common/cas_login/1'
      '?redirect=https%3A%2F%2Fpersonal.neu.edu.cn%2Fportal';

  static final Uri loginUri = Uri.https(
    'pass.neu.edu.cn',
    '/tpass/login',
    {'service': service},
  );

  final Dio _dio;
  final Map<String, Map<String, String>> _cookies = {};

  static Dio _buildDio() {
    return Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 20),
        sendTimeout: const Duration(seconds: 15),
        responseType: ResponseType.plain,
        headers: {
          'User-Agent':
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
              'AppleWebKit/537.36 (KHTML, like Gecko) '
              'Chrome/157.0.0.0 Safari/537.36 Edg/157.0.0.0',
          'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.6',
        },
        validateStatus: (status) => status != null && status < 400,
      ),
    );
  }

  @override
  Future<CasLoginResult> login({
    required String username,
    required String password,
  }) async {
    final trimmedUsername = username.trim();
    if (trimmedUsername.isEmpty || password.isEmpty) {
      throw const AuthException('学号和密码不能为空。');
    }

    final loginPage = await _request(loginUri);
    if (loginPage.statusCode != 200) {
      throw AuthException('无法打开学校登录页（HTTP ${loginPage.statusCode}）。');
    }

    final lt = _hiddenValue(loginPage.body, 'lt');
    final execution = _hiddenValue(loginPage.body, 'execution');
    if (lt == null || execution == null) {
      throw const AuthException('学校登录页格式已更新，请使用网页登录。');
    }

    final encrypted = NeuRsaEncryptor.encrypt('$trimmedUsername$password');
    final response = await _request(
      loginUri,
      method: 'POST',
      form: {
        'un': trimmedUsername,
        'pd': password,
        'rsa': encrypted,
        'ul': '${trimmedUsername.length}',
        'pl': '${password.length}',
        'lt': lt,
        'execution': execution,
        '_eventId': 'submit',
      },
    );

    final finalHost = response.uri.host;
    if (finalHost == 'pass.neu.edu.cn') {
      final error = _errorMessage(response.body);
      if (error != null) throw AuthException(error);
      if (_looksLikeSecondFactor(response.body)) {
        throw const SecondaryVerificationRequired();
      }
      throw const AuthException('登录未完成，请重试或使用网页登录。');
    }

    final cookies = _exportCookies();
    if (cookies.isEmpty) {
      throw const AuthException('登录成功但未取得会话，请重试。');
    }
    return CasLoginResult(cookies: cookies, finalUri: response.uri);
  }

  Future<_HttpPage> _request(
    Uri uri, {
    String method = 'GET',
    Map<String, String>? form,
  }) async {
    var current = uri;
    var currentMethod = method;
    var currentForm = form;

    for (var redirectCount = 0; redirectCount < 10; redirectCount++) {
      final response = await _dio.requestUri<String>(
        current,
        data: currentForm,
        options: Options(
          method: currentMethod,
          followRedirects: false,
          contentType:
              currentForm == null ? null : Headers.formUrlEncodedContentType,
          headers: _cookieHeader(current),
        ),
      );

      _captureCookies(current, response.headers);
      final status = response.statusCode ?? 0;
      final location = response.headers.value('location');
      if (status >= 300 && status < 400 && location != null) {
        final next = current.resolve(location);
        if (status == 303 || (status == 302 && currentMethod != 'GET')) {
          currentMethod = 'GET';
          currentForm = null;
        }
        current = next;
        continue;
      }

      return _HttpPage(
        uri: current,
        statusCode: status,
        body: response.data ?? '',
      );
    }

    throw const AuthException('登录跳转次数过多，请稍后再试。');
  }

  Map<String, String>? _cookieHeader(Uri uri) {
    final values = <String>[];
    for (final entry in _cookies.entries) {
      final domain = entry.key;
      final matches = uri.host == domain ||
          uri.host.endsWith('.$domain') ||
          domain.endsWith('.${uri.host}');
      if (!matches) continue;
      for (final pair in entry.value.entries) {
        values.add('${pair.key}=${pair.value}');
      }
    }
    if (values.isEmpty) return null;
    return {'cookie': values.join('; ')};
  }

  void _captureCookies(Uri uri, Headers headers) {
    final rawHeaders = headers['set-cookie'];
    if (rawHeaders == null || rawHeaders.isEmpty) return;

    for (final raw in rawHeaders) {
      // Most servers send one cookie per header. The split also tolerates
      // comma-joined cookies without confusing the comma inside Expires.
      final parts = raw.split(RegExp(r',(?=[^;]+=)'));
      for (final part in parts) {
        final first = part.split(';').first.trim();
        final equals = first.indexOf('=');
        if (equals <= 0) continue;
        final name = first.substring(0, equals).trim();
        final value = first.substring(equals + 1).trim();
        if (name.isEmpty || value.isEmpty) continue;
        _cookies.putIfAbsent(uri.host, () => {})[name] = value;
      }
    }
  }

  Map<String, String> _exportCookies() {
    final result = <String, String>{};
    for (final entry in _cookies.entries) {
      if (entry.value.isEmpty) continue;
      result[entry.key] = entry.value.entries
          .map((pair) => '${pair.key}=${pair.value}')
          .join('; ');
    }
    return result;
  }

  static bool _looksLikeSecondFactor(String html) {
    return html.contains('second_valid_ok') || html.contains('second_valid');
  }

  static String? _hiddenValue(String html, String name) {
    final escaped = RegExp.escape(name);
    final patterns = [
      RegExp(
        'name=["\']$escaped["\'][^>]*value=["\']([^"\']*)["\']',
        caseSensitive: false,
        dotAll: true,
      ),
      RegExp(
        'value=["\']([^"\']*)["\'][^>]*name=["\']$escaped["\']',
        caseSensitive: false,
        dotAll: true,
      ),
    ];
    for (final pattern in patterns) {
      final match = pattern.firstMatch(html);
      if (match != null) return htmlDecode(match.group(1) ?? '');
    }
    return null;
  }

  static String? _errorMessage(String html) {
    final patterns = [
      RegExp(
        "id=[\"']errormsghide[\"'][^>]*>(.*?)</",
        caseSensitive: false,
        dotAll: true,
      ),
      RegExp(
        "id=[\"']errormsg[\"'][^>]*>(.*?)</",
        caseSensitive: false,
        dotAll: true,
      ),
    ];
    for (final pattern in patterns) {
      final match = pattern.firstMatch(html);
      final text = match?.group(1)?.replaceAll(RegExp('<[^>]+>'), '').trim();
      if (text != null && text.isNotEmpty) return htmlDecode(text);
    }
    if (html.contains('账号不存在')) return '账号不存在，请检查学号。';
    if (html.contains('密码错误')) return '密码错误，请重试。';
    return null;
  }

  static String htmlDecode(String value) {
    return value
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'");
  }
}

class _HttpPage {
  const _HttpPage({
    required this.uri,
    required this.statusCode,
    required this.body,
  });

  final Uri uri;
  final int statusCode;
  final String body;
}
