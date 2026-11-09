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
      await controller.loadUrl(_casLoginUri.toString());
      final formReady = await _waitForCasForm(controller, attempts: 8);
      if (!formReady) {
        // The WebView2 profile may already hold a CAS/portal session from an
        // earlier login. In that case CAS redirects straight to the portal
        // and there is no login form to fill; read the portal identity
        // directly instead of treating this as a failure.
        debugPrint('[identity] CAS form not available; trying portal session');
        await controller.loadUrl('https://personal.neu.edu.cn/portal');
        await Future<void>.delayed(const Duration(seconds: 2));
        await controller.loadUrl(
          'https://personal.neu.edu.cn/page/site/homeIndex',
        );
        return _pollIdentity(controller, attempts: 16);
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
          return 'no-login';
        })()
      ''');
      await Future<void>.delayed(const Duration(seconds: 5));
      // The portal may land on /portal first; the SPA root is the page that
      // persists userInfo, so make that explicit.
      await controller.loadUrl(
        'https://personal.neu.edu.cn/page/site/homeIndex',
      );
      return _pollIdentity(controller, attempts: 16);
    });
  }

  Uri get _casLoginUri => Uri.https('pass.neu.edu.cn', '/tpass/login', {
    'service':
        'https://personal.neu.edu.cn/portal/manage/common/cas_login/1'
        '?redirect=https%3A%2F%2Fpersonal.neu.edu.cn%2Fportal',
  });

  Future<StudentIdentity?> _withController(
    Future<StudentIdentity?> Function(WebviewController) body,
  ) async {
    final controller = WebviewController();
    Directory? dataDir;
    try {
      // Never reuse a WebView2 profile here: the profile keeps CAS/portal
      // cookies, and reusing it would return the previously logged-in
      // student's identity when a second account is tested.
      dataDir = await Directory.systemTemp.createTemp('neu_better_identity_');
      await WebviewController.initializeEnvironment(
        userDataPath: dataDir.path,
      );
      await controller.initialize();
      await controller.setSize(const Size(1280, 720));
      return await body(controller);
    } catch (error) {
      debugPrint('[identity] windows webview probe failed: $error');
      return null;
    } finally {
      try {
        await controller.dispose();
      } catch (_) {}
      if (dataDir != null) {
        try {
          await dataDir.delete(recursive: true);
        } catch (_) {
          // WebView2 may keep a lock briefly; the OS temp directory is fine.
        }
      }
    }
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
