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

class _AndroidWebViewLoginPage extends StatefulWidget {
  const _AndroidWebViewLoginPage();

  @override
  State<_AndroidWebViewLoginPage> createState() =>
      _AndroidWebViewLoginPageState();
}

class _AndroidWebViewLoginPageState extends State<_AndroidWebViewLoginPage> {
  late final mobile.WebViewController _controller;
  bool _loading = true;
  bool _reading = false;

  @override
  void initState() {
    super.initState();
    _controller = mobile.WebViewController()
      ..setJavaScriptMode(mobile.JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        mobile.NavigationDelegate(
          onPageStarted: (_) {
            if (mounted) setState(() => _loading = true);
          },
          onPageFinished: (_) {
            if (mounted) setState(() => _loading = false);
            unawaited(_captureAndroidUsername(_controller));
          },
          onWebResourceError: (_) {
            if (mounted) setState(() => _loading = false);
          },
        ),
      )
      ..loadRequest(NeuCasClient.loginUri);
  }

  Future<StudentIdentity?> _readIdentity() async {
    try {
      final raw = await _controller.runJavaScriptReturningResult(
        _localIdentityScript,
      );
      return _parseIdentityPayload(raw);
    } catch (_) {
      return null;
    }
  }

  Future<void> _finish() async {
    if (_reading) return;
    setState(() => _reading = true);
    try {
      final identityFuture = _readIdentity();
      final result = <String, String>{};
      final allCookies = <dynamic>[];
      for (final host in const ['pass.neu.edu.cn', 'personal.neu.edu.cn']) {
        final cookies = await mobile.WebViewCookieManager().getCookies(
          domain: Uri.parse('https://$host'),
        );
        if (cookies.isEmpty) continue;
        allCookies.addAll(cookies);
        final pairs = <String, String>{};
        for (final cookie in cookies) {
          pairs[cookie.name] = cookie.value;
        }
        result[host] = pairs.entries
            .map((entry) => '${entry.key}=${entry.value}')
            .join('; ');
      }

      if (!mounted) return;
      if (result.isEmpty) {
        _showEmptyCookieMessage();
        return;
      }

      // A localStorage read is local and fast; it gives the real name without
      // adding a visible pause. If the portal has not stored it yet, the
      // shell refreshes identity from /site/user_info in the background.
      final identity = await identityFuture.timeout(
        const Duration(milliseconds: 500),
        onTimeout: () => null,
      );
      final studentId = identity?.studentId ?? _cookieStudentId(allCookies);
      if (!mounted) return;
      Navigator.of(context).pop(
        WebViewLoginResult(
          cookies: result,
          studentId: studentId,
          displayName: identity?.displayName,
        ),
      );
    } finally {
      if (mounted) setState(() => _reading = false);
    }
  }

  void _showEmptyCookieMessage() {
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('还没有取得登录会话，请先在网页中完成登录。')));
  }

  @override
  Widget build(BuildContext context) {
    return _WebViewScaffold(
      reading: _reading,
      onFinish: _finish,
      body: Stack(
        children: [
          mobile.WebViewWidget(controller: _controller),
          if (_loading)
            ColoredBox(
              color: AppColors.canvas.withValues(alpha: 0.62),
              child: const Center(child: CircularProgressIndicator()),
            ),
        ],
      ),
    );
  }
}

class _WindowsWebViewLoginPage extends StatefulWidget {
  const _WindowsWebViewLoginPage();

  @override
  State<_WindowsWebViewLoginPage> createState() =>
      _WindowsWebViewLoginPageState();
}

class _WindowsWebViewLoginPageState extends State<_WindowsWebViewLoginPage> {
  desktop.WebviewController? _controller;
  String? _error;
  bool _reading = false;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    final controller = desktop.WebviewController();
    try {
      debugPrint('[webview] initializing Windows WebView2');
      Directory dataDir;
      try {
        dataDir = Directory(
          '${Directory.systemTemp.path}\\NEU Better\\WebView2',
        );
        await dataDir.create(recursive: true);
      } on FileSystemException {
        // Some locked-down Windows accounts deny writes under AppData/Temp.
        // Keep the webview usable by falling back next to the executable.
        dataDir = Directory('${Directory.current.path}\\data\\webview2');
        await dataDir.create(recursive: true);
      }
      await desktop.WebviewController.initializeEnvironment(
        userDataPath: dataDir.path,
      );
      await controller.initialize();
      await controller.addScriptToExecuteOnDocumentCreated(
        _captureUsernameScript,
      );
      debugPrint('[webview] controller initialized');
      await controller.loadUrl(NeuCasClient.loginUri.toString());
      debugPrint('[webview] loaded CAS page');
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() => _controller = controller);
    } catch (error) {
      debugPrint('[webview] initialization failed: $error');
      if (!mounted) return;
      setState(() => _error = '无法初始化 Windows WebView2：$error');
      await controller.dispose();
    }
  }

  Future<StudentIdentity?> _readIdentity() async {
    try {
      final raw = await _controller?.executeScript(_localIdentityScript);
      return _parseIdentityPayload(raw);
    } catch (_) {
      return null;
    }
  }

  Future<void> _finish() async {
    final controller = _controller;
    if (controller == null || _reading) return;
    setState(() => _reading = true);
    try {
      final identityFuture = _readIdentity();
      final cookies = await controller.getCookies();
      final byDomain = <String, List<String>>{};
      for (final cookie in cookies) {
        if (!cookie.domain.contains('neu.edu.cn')) continue;
        final domain = cookie.domain.replaceFirst(RegExp(r'^\.'), '');
        byDomain
            .putIfAbsent(domain, () => <String>[])
            .add('${cookie.name}=${cookie.value}');
      }

      final result = <String, String>{
        for (final entry in byDomain.entries)
          if (entry.value.isNotEmpty) entry.key: entry.value.join('; '),
      };
      if (!mounted) return;
      if (result.isEmpty) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('还没有取得登录会话，请先在网页中完成登录。')));
        return;
      }

      // Read the portal's cached userInfo before popping; this is local and
      // bounded, so it does not hold the page open on a network round trip.
      final identity = await identityFuture.timeout(
        const Duration(milliseconds: 500),
        onTimeout: () => null,
      );
      final studentId = identity?.studentId ?? _cookieStudentId(cookies);
      if (!mounted) return;
      Navigator.of(context).pop(
        WebViewLoginResult(
          cookies: result,
          studentId: studentId,
          displayName: identity?.displayName,
        ),
      );
    } finally {
      if (mounted) setState(() => _reading = false);
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    return _WebViewScaffold(
      reading: _reading,
      onFinish: controller == null ? null : _finish,
      body: controller == null
          ? Center(
              child: _error == null
                  ? const CircularProgressIndicator()
                  : Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        _error!,
                        style: TextStyle(
                          color: AppColors.danger,
                          fontSize: 13,
                          height: 1.6,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
            )
          : desktop.Webview(controller),
    );
  }
}

class _WebViewScaffold extends StatelessWidget {
  const _WebViewScaffold({
    required this.reading,
    required this.onFinish,
    required this.body,
  });

  final bool reading;
  final VoidCallback? onFinish;
  final Widget body;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(
        title: const Text('学校网页登录'),
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.ink,
        surfaceTintColor: Colors.transparent,
        actions: [
          TextButton(
            onPressed: reading ? null : onFinish,
            child: reading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('完成'),
          ),
        ],
      ),
      body: Stack(
        children: [
          Positioned.fill(child: body),
          Positioned(
            left: 16,
            right: 16,
            bottom: 16,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.surface.withValues(
                  alpha: AppColors.isDark ? 0.96 : 0.94,
                ),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.line),
              ),
              child: Text(
                '登录完成后点右上角“完成”。如果页面停在二次验证，请按学校提示完成验证。',
                style: TextStyle(
                  color: AppColors.muted,
                  fontSize: 12,
                  height: 1.5,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
