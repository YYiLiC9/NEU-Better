import 'dart:async';
import 'dart:convert';
import 'dart:io' show Directory, FileSystemException, Platform;

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart' as mobile;
import 'package:webview_flutter_windows/webview_flutter_windows.dart'
    as desktop;

import '../../app/theme/app_theme.dart';
import '../../core/auth/student_identity.dart';
import '../../core/auth/webview_login_result.dart';
import '../../core/network/neu_cas_client.dart';

part 'widgets/webview_login_android.dart';
part 'widgets/webview_login_windows.dart';
part 'widgets/webview_widgets.dart';

/// Browser fallback for QR/device verification or if the CAS page changes.
///
/// Windows uses the maintained `webview_flutter_windows` implementation,
/// which renders WebView2 through a regular Flutter texture. Android uses
/// the official `webview_flutter` platform implementation.
class WebViewLoginPage extends StatelessWidget {
  const WebViewLoginPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Platform.isWindows
        ? const _WindowsWebViewLoginPage()
        : const _AndroidWebViewLoginPage();
  }
}

const String _captureUsernameScript = r'''
(() => {
  function attach() {
    const input = document.getElementById('un');
    if (!input || input.dataset.neuBetterCapture === '1') return;
    input.dataset.neuBetterCapture = '1';
    function remember() {
      const value = (input.value || '').trim();
      if (!value) return;
      document.cookie = 'neu_better_un=' + encodeURIComponent(value) +
        '; path=/; max-age=3600; SameSite=Lax';
    }
    input.addEventListener('input', remember);
    input.addEventListener('change', remember);
    remember();
  }
  attach();
  const root = document.documentElement;
  if (root) {
    const observer = new MutationObserver(attach);
    observer.observe(root, { childList: true, subtree: true });
  }
})();
''';

Future<void> _captureAndroidUsername(
  mobile.WebViewController controller,
) async {
  try {
    await controller.runJavaScript(_captureUsernameScript);
  } catch (_) {
    // The page can be in transition while onPageFinished fires.
  }
}

const String _localIdentityScript = r'''
(function () {
  try {
    const raw = localStorage.getItem('userInfo') ||
      sessionStorage.getItem('userInfo');
    return raw || '';
  } catch (e) {
    return '';
  }
})();
''';

StudentIdentity? _parseIdentityPayload(Object? raw) {
  if (raw == null) return null;
  var value = raw;
  for (var i = 0; i < 2; i++) {
    if (value is Map) {
      return StudentIdentity.fromUserInfo(value);
    }
    if (value is! String || value.trim().isEmpty) return null;
    try {
      value = jsonDecode(value);
    } catch (_) {
      return null;
    }
  }
  return null;
}

String? _cookieStudentId(Iterable<dynamic> cookies) {
  for (final cookie in cookies) {
    final name = '${cookie.name}';
    if (name == 'neu_cas_un' || name == 'neu_better_un') {
      final value = '${cookie.value}'.trim();
      if (value.isEmpty) continue;
      String decoded;
      try {
        decoded = Uri.decodeComponent(value).trim();
      } catch (_) {
        decoded = value;
      }
      if (StudentIdentity.isValidStudentId(decoded)) return decoded;
    }
  }
  return null;
}
