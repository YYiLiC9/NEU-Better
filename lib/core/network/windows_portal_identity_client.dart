import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:webview_flutter_windows/webview_flutter_windows.dart';

import '../auth/student_identity.dart';
import 'portal_identity_client.dart';

/// Reads the authenticated portal's `userInfo` from a real, headless WebView2
/// session. This is the only reliable way to obtain the portal-generated
/// `cookie_vjuid_login` session and the real `user_name` / `user_number`
/// fields: a plain HTTP CAS login does not run the portal SPA's JavaScript.
class WindowsPortalIdentityClient
    implements PortalIdentityClient, PortalLoginIdentityClient {
  /// WebView2 has one shared environment per process and refuses to
  /// initialize it while another controller is alive. The identity refresh
  /// and the timetable sync can overlap, so all headless probes are serialized
  /// and reuse one long-lived controller. Reinitializing the environment for
  /// each probe is unreliable in release builds.
  static Future<void> _webViewQueue = Future<void>.value();
  static WebviewController? _headlessController;
  static Directory? _headlessDataDir;

  void _debugLog(String message) {
    try {
      final file = File(
        '${File(Platform.resolvedExecutable).parent.path}'
        '${Platform.pathSeparator}data'
        '${Platform.pathSeparator}yjs-debug.log',
      );
      file.writeAsStringSync(
        '${DateTime.now().toIso8601String()} $message\n',
        mode: FileMode.append,
        flush: true,
      );
    } catch (_) {}
  }

  @override
  Future<StudentIdentity?> fetch(Map<String, String> cookies) async {
    return _withController((controller) async {
      await _seedCookies(controller, cookies);
      await controller.loadUrl(
        'https://personal.neu.edu.cn/page/site/homeIndex',
      );
      return _pollIdentity(controller, attempts: 14);
    });
  }

  /// A full headless CAS login is used when the native HTTP session cannot
  /// open the portal SPA (the normal case after `NeuCasClient.login`). The
  /// CAS page's own `login()` JavaScript performs the RSA encryption.
  @override
  Future<StudentIdentity?> fetchWithCredentials({
    required String username,
    required String password,
  }) async {
    return _withController((controller) async {
      final logged = await _loginWithCredentials(
        controller,
        username: username,
        password: password,
      );
      if (!logged) {
        debugPrint('[identity] CAS form not available; trying portal session');
        await controller.loadUrl('https://personal.neu.edu.cn/portal');
        await Future<void>.delayed(const Duration(seconds: 2));
      }
      await controller.loadUrl(
        'https://personal.neu.edu.cn/page/site/homeIndex',
      );
      return _pollIdentity(controller, attempts: 16);
    });
  }

  /// Runs a real browser login and reads the graduate timetable API from the
  /// authenticated `yjs.neu.edu.cn` page.
  Future<String?> fetchYjsTimetable({
    required String username,
    required String password,
    String term = '20261',
    String? roleId,
  }) async {
    _debugLog('fetchYjsTimetable start user=$username term=$term');
    return _withController((controller) async {
      final logged = await _loginWithCredentials(
        controller,
        username: username,
        password: password,
        service:
            'https://yjs.neu.edu.cn/gsapp/sys/yjsemaphome/portal/index.do',
      );
      _debugLog('CAS login result=$logged');
      if (!logged) {
        return jsonEncode({
          'error': '无法打开学校登录页，请稍后重试',
        });
      }
      await controller.loadUrl(
        'https://yjs.neu.edu.cn/gsapp/sys/yjsemaphome/portal/index.do',
      );
      await Future<void>.delayed(const Duration(seconds: 3));
      final portalTitle = await controller.executeScript('document.title');
      final portalBody = await controller.executeScript(
        'document.body.innerText.slice(0,2000)',
      );
      final portalHtml = await controller.executeScript(
        'document.body.innerHTML.slice(0,6000)',
      );
      debugPrint('[yjs] portal title=$portalTitle body=$portalBody');
      debugPrint('[yjs] portal html=$portalHtml');
      final userInfo = await controller.executeScript('''
        (() => {
          try {
            const xhr = new XMLHttpRequest();
            xhr.open('POST', '/gsapp/sys/yjsemaphome/modules/pubWork/getUserInfo.do', false);
            xhr.withCredentials = true;
            xhr.setRequestHeader('Content-Type', 'application/x-www-form-urlencoded; charset=UTF-8');
            xhr.setRequestHeader('X-Requested-With', 'XMLHttpRequest');
            xhr.send('');
            return xhr.responseText;
          } catch (error) { return String(error); }
        })()
      ''');
      debugPrint('[yjs] userInfo=$userInfo');
      final selectedRole = roleId?.trim().isNotEmpty == true
          ? roleId!.trim()
          : _firstRoleId(userInfo);
      _debugLog('role=$selectedRole userInfoLength=${userInfo?.toString().length}');
      if (selectedRole == null || selectedRole.isEmpty) {
        return jsonEncode({
          'error': '该账号没有研究生系统身份（grouplist 为空）',
          'userInfo': userInfo,
        });
      }
      final changedRole = await controller.executeScript('''
        (() => {
          try {
            const xhr = new XMLHttpRequest();
            xhr.open('POST', '/gsapp/sys/yjsemaphome/modules/pubWork/changeAppRole_yjs.do', false);
            xhr.withCredentials = true;
            xhr.setRequestHeader('Content-Type', 'application/x-www-form-urlencoded; charset=UTF-8');
            xhr.setRequestHeader('X-Requested-With', 'XMLHttpRequest');
            xhr.send('_yhz=' + encodeURIComponent(${jsonEncode(selectedRole)}));
            return JSON.stringify({status: xhr.status, body: xhr.responseText});
          } catch (error) { return String(error); }
        })()
      ''');
      debugPrint('[yjs] changeRole=$changedRole');
      await controller.loadUrl(
        'https://yjs.neu.edu.cn/gsapp/sys/yjsemaphome/portal/index.do',
      );
      await Future<void>.delayed(const Duration(seconds: 3));
      final appList = await controller.executeScript('''
        (() => {
          try {
            const xhr = new XMLHttpRequest();
            xhr.open('POST', '/gsapp/sys/yjsemaphome/modules/pubWork/getCanVisitAppList.do', false);
            xhr.withCredentials = true;
            xhr.setRequestHeader('Content-Type', 'application/x-www-form-urlencoded; charset=UTF-8');
            xhr.setRequestHeader('X-Requested-With', 'XMLHttpRequest');
            xhr.send('KEYWORD=');
            return xhr.responseText;
          } catch (error) { return String(error); }
        })()
      ''');
      debugPrint('[yjs] apps=$appList');
      final role = selectedRole;
      final appUrl =
          'https://yjs.neu.edu.cn/gsapp/sys/wdkbapp/*default/index.do'
          '?THEME=blue&min=1&_yhz=${Uri.encodeQueryComponent(role)}#/';
      await controller.loadUrl(appUrl);
      await Future<void>.delayed(const Duration(seconds: 4));
      final pageUrl = await controller.executeScript('location.href');
      final pageTitle = await controller.executeScript('document.title');
      _debugLog('page url=$pageUrl title=$pageTitle');
      debugPrint('[yjs] page url=$pageUrl title=$pageTitle');
      final escapedTerm = jsonEncode(term);
      final raw = await controller.executeScript('''
        (() => {
          try {
            const xhr = new XMLHttpRequest();
            xhr.open('POST', '/gsapp/sys/wdkbapp/modules/xskcb/xspkjgcx.do', false);
            xhr.withCredentials = true;
            xhr.setRequestHeader('Content-Type', 'application/x-www-form-urlencoded; charset=UTF-8');
            xhr.setRequestHeader('X-Requested-With', 'XMLHttpRequest');
            xhr.send('XNXQDM=' + encodeURIComponent($escapedTerm) + '&*order=-ZCBH');
            return JSON.stringify({status: xhr.status, body: xhr.responseText});
          } catch (error) {
            return JSON.stringify({error: String(error)});
          }
        })()
      ''');
      if (raw is String) {
        try {
          final decoded = jsonDecode(raw);
          if (decoded is Map) {
            decoded['currentWeek'] = _currentWeekFromUserInfo(userInfo);
            return jsonEncode(decoded);
          }
        } catch (_) {}
        return raw;
      }
      return jsonEncode(raw);
    });
  }

  int? _currentWeekFromUserInfo(Object? rawUserInfo) {
    if (rawUserInfo is! String || rawUserInfo.trim().isEmpty) return null;
    try {
      final payload = jsonDecode(rawUserInfo);
      if (payload is! Map) return null;
      final data = payload['data'];
      if (data is! Map) return null;
      final words = data['welcomeWords'];
      final match = RegExp(r'第\s*(\d+)\s*周').firstMatch('${words ?? ''}');
      return int.tryParse(match?.group(1) ?? '');
    } catch (_) {
      return null;
    }
  }

  String? _firstRoleId(Object? rawUserInfo) {
    if (rawUserInfo is! String || rawUserInfo.trim().isEmpty) return null;
    try {
      final payload = jsonDecode(rawUserInfo);
      if (payload is! Map) return null;
      final data = payload['data'];
      if (data is! Map) return null;
      final rawGroups = data['grouplist'];
      final groups = rawGroups is String
          ? (rawGroups.trim().isEmpty ? null : jsonDecode(rawGroups))
          : rawGroups;
      if (groups is! List || groups.isEmpty) return null;
      final first = groups.first;
      if (first is! Map) return null;
      for (final key in const ['id', 'roleId', 'ROLEID', 'yhzid']) {
        final value = first[key];
        if (value is String && value.trim().isNotEmpty) return value.trim();
      }
      return null;
    } catch (error) {
      debugPrint('[yjs] failed to parse role list: $error');
      return null;
    }
  }

  Future<bool> _loginWithCredentials(
    WebviewController controller, {
    required String username,
    required String password,
    String? service,
  }) async {
    final loginUri = service == null
        ? _casLoginUri
        : Uri.https('pass.neu.edu.cn', '/tpass/login', {'service': service});
    await controller.loadUrl(loginUri.toString());
    final formReady = await _waitForCasForm(controller, attempts: 8);
    if (!formReady) return false;
    var loginReady = false;
    for (var i = 0; i < 24; i++) {
      final state = await controller.executeScript('typeof login');
      if (state == 'function') {
        loginReady = true;
        break;
      }
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
    if (!loginReady) {
      debugPrint('[identity] CAS login() did not become ready');
    }
    final escapedUser = jsonEncode(username);
    final escapedPassword = jsonEncode(password);
    await controller.executeScript('''
      (() => {
        const u = document.querySelector('#un');
        const p = document.querySelector('#pd');
        if (!u || !p) return 'missing';
        u.value = $escapedUser;
        p.value = $escapedPassword;
        if (typeof login === 'function') { login(); return 'submitted'; }
        const button = document.querySelector('#index_login_btn');
        if (button) { button.click(); return 'clicked'; }
        return 'no-login';
      })()
    ''');
    await Future<void>.delayed(const Duration(seconds: 5));
    return true;
  }

  Uri get _casLoginUri => Uri.https('pass.neu.edu.cn', '/tpass/login', {
    'service':
        'https://personal.neu.edu.cn/portal/manage/common/cas_login/1'
        '?redirect=https%3A%2F%2Fpersonal.neu.edu.cn%2Fportal',
  });

  Future<T?> _withController<T>(
    Future<T?> Function(WebviewController) body,
  ) async {
    final done = Completer<void>();
    final previous = _webViewQueue;
    _webViewQueue = previous.then((_) => done.future);
    await previous;

    try {
      final controller = await _ensureHeadlessController();
      // The controller is intentionally long-lived: its WebView2 environment
      // is process-wide. Clear cookies between probes so a previous account
      // cannot leak into the next identity or timetable request.
      try {
        await controller.clearCookies();
      } catch (error) {
        debugPrint('[identity] clear cookies failed: $error');
      }
      return await body(controller);
    } catch (error, stack) {
      _debugLog('probe failed: $error\n$stack');
      debugPrint('[identity] windows webview probe failed: $error');
      try {
        final log = File(
          '${Directory.systemTemp.path}${Platform.pathSeparator}'
          'neu_better_webview_error.log',
        );
        await log.writeAsString(
          '${DateTime.now().toIso8601String()}\n$error\n$stack\n',
          mode: FileMode.append,
          flush: true,
        );
      } catch (_) {}
      return null;
    } finally {
      if (!done.isCompleted) done.complete();
    }
  }

  Future<WebviewController> _ensureHeadlessController() async {
    final existing = _headlessController;
    if (existing != null) return existing;

    try {
      _headlessDataDir ??=
          await Directory.systemTemp.createTemp('neu_better_headless_');
      await WebviewController.initializeEnvironment(
        userDataPath: _headlessDataDir!.path,
        additionalArguments: '--disable-gpu',
      );
    } catch (error) {
      // If the Flutter UI already created the process-wide environment, or a
      // previous controller is still releasing it, controller.initialize()
      // below can still use it. Do not abort the probe for this reason.
      debugPrint('[identity] initializeEnvironment skipped: $error');
    }

    final controller = WebviewController();
    await controller.initialize();
    await controller.setSize(const Size(1280, 720));
    _headlessController = controller;
    return controller;
  }

  Future<bool> _waitForCasForm(
    WebviewController controller, {
    int attempts = 30,
  }) async {
    for (var attempt = 0; attempt < attempts; attempt++) {
      await Future<void>.delayed(
        Duration(milliseconds: attempt == 0 ? 800 : 500),
      );
      final ready = await controller.executeScript(
        '!!document.querySelector("#un") && '
        '!!document.querySelector("#pd") && typeof login === "function"',
      );
      if (ready == true) return true;
    }
    return false;
  }

  Future<StudentIdentity?> _pollIdentity(
    WebviewController controller, {
    required int attempts,
  }) async {
    for (var attempt = 0; attempt < attempts; attempt++) {
      await Future<void>.delayed(
        Duration(milliseconds: attempt == 0 ? 1200 : 500),
      );
      final raw = await controller.executeScript(_storageProbeScript);
      final identity = _parseStorageProbe(raw);
      if (identity != null && identity.hasDisplayName) return identity;
      if (attempt == attempts - 1) {
        debugPrint('[identity] storage probe ended without userInfo: $raw');
      }
    }
    return null;
  }

  Future<void> _seedCookies(
    WebviewController controller,
    Map<String, String> cookies,
  ) async {
    for (final entry in cookies.entries) {
      final domain = entry.key.trim();
      if (domain.isEmpty) continue;
      for (final part in entry.value.split(';')) {
        final trimmed = part.trim();
        if (trimmed.isEmpty) continue;
        final equals = trimmed.indexOf('=');
        if (equals <= 0) continue;
        final name = trimmed.substring(0, equals).trim();
        final value = trimmed.substring(equals + 1).trim();
        if (name.isEmpty || value.isEmpty) continue;
        try {
          await controller.setCookie(
            WebviewCookie(
              name: name,
              value: value,
              domain: domain,
              path: '/',
              isSecure: true,
              isHttpOnly: true,
            ),
          );
        } catch (error) {
          debugPrint('[identity] seed cookie $name failed: $error');
        }
      }
    }
  }

  static const _storageProbeScript = r'''
(() => {
  const output = [];
  const collect = (storage, prefix) => {
    try {
      for (let i = 0; i < storage.length; i++) {
        const key = storage.key(i);
        const value = storage.getItem(key);
        if (key && value) output.push([prefix + key, value]);
      }
    } catch (_) {}
  };
  collect(localStorage, 'local:');
  collect(sessionStorage, 'session:');
  let cookie = '';
  try { cookie = document.cookie || ''; } catch (_) {}
  return JSON.stringify({ entries: output, cookie: cookie });
})()
''';

  StudentIdentity? _parseStorageProbe(Object? raw) {
    if (raw == null) return null;
    dynamic decoded = raw;
    if (decoded is String) {
      try {
        decoded = jsonDecode(decoded);
      } catch (_) {
        return null;
      }
    }
    if (decoded is! Map) return null;
    final entries = decoded['entries'];
    if (entries is List) {
      for (final entry in entries) {
        if (entry is! List || entry.length < 2) continue;
        final identity = _identityFromJsonValue(entry[1]);
        if (identity != null && identity.hasDisplayName) return identity;
      }
    }
    return null;
  }

  StudentIdentity? _identityFromJsonValue(Object? value) {
    if (value is! String || value.trim().isEmpty) return null;
    try {
      final decoded = jsonDecode(value);
      if (decoded is Map) {
        final identity = StudentIdentity.fromUserInfo(decoded);
        if (identity.hasStudentId || identity.hasDisplayName) return identity;
        final nested = decoded['d'];
        if (nested is Map) {
          final inner = StudentIdentity.fromUserInfo(nested);
          if (inner.hasStudentId || inner.hasDisplayName) return inner;
        }
      }
    } catch (_) {}
    return null;
  }
}
