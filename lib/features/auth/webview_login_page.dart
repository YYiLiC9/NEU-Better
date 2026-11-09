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

const String _identityProbeScript = r'''
(() => {
  try {
    let info = null;
    const host = window.location.hostname;
    // The portal is a same-origin Vue SPA. Its own API is authoritative and
    // avoids guessing an account number from arbitrary page text.
    if (host === 'personal.neu.edu.cn' || host.endsWith('.personal.neu.edu.cn')) {
      try {
        const xhr = new XMLHttpRequest();
        xhr.open('GET', '/site/user_info?t=' + Date.now(), false);
        xhr.withCredentials = true;
        xhr.setRequestHeader('Content-Type', 'application/x-www-form-urlencoded');
        xhr.setRequestHeader('Source-Version', '0');
        xhr.setRequestHeader('X-Requested-With', 'XMLHttpRequest');
        xhr.send(null);
        if (xhr.status === 200) {
          const payload = JSON.parse(xhr.responseText);
          if (Number(payload.e) === 0 && payload.d) info = payload.d;
        }
      } catch (_) {}
    }

    let cached = null;
    try {
      const raw = window.localStorage.getItem('userInfo') ||
        window.localStorage.getItem('hitstudent_userInfo');
      if (raw) cached = JSON.parse(raw);
    } catch (_) {}

    let cookieId = '';
    try {
      const match = document.cookie.match(/(?:^|;\s*)neu_better_un=([^;]+)/);
      if (match) cookieId = decodeURIComponent(match[1]);
    } catch (_) {}

    const infoId = info && info.user_number ? String(info.user_number) : '';
    const cachedId = cached && cached.user_number ? String(cached.user_number) : '';
    // Never trust a cached id unless it matches the id the user just typed in
    // the CAS form; this prevents an old WebView cache from showing another
    // account's number.
    const id = infoId || (cachedId && cookieId && cachedId === cookieId ? cachedId : '');
    const name = info && info.user_name
      ? String(info.user_name)
      : (cached && cached.user_name ? String(cached.user_name) : '');

    const text = document.body ? document.body.innerText : '';
    const labeledId = text.match(/(?:学号|账号|用户名|工号)\s*[:：]?\s*(\d{8,12})/);
    const labeledName = text.match(/(?:姓名|用户姓名|真实姓名)\s*[:：]?\s*([\u4e00-\u9fa5]{2,8})/);

    return JSON.stringify({
      studentId: id || (labeledId ? labeledId[1] : ''),
      displayName: name || (labeledName ? labeledName[1] : ''),
    });
  } catch (error) {
    return JSON.stringify({ studentId: '', displayName: '' });
  }
})();
''';

Future<StudentIdentity> _probeAndroidIdentity(
  mobile.WebViewController controller,
) async {
  try {
    final raw = await controller
        .runJavaScriptReturningResult(_identityProbeScript)
        .timeout(const Duration(milliseconds: 1500));
    return _decodeIdentity(raw);
  } catch (_) {
    return const StudentIdentity();
  }
}

Future<StudentIdentity> _probeWindowsIdentity(
  desktop.WebviewController controller,
) async {
  try {
    final raw = await controller
        .executeScript(_identityProbeScript)
        .timeout(const Duration(milliseconds: 1500));
    return _decodeIdentity(raw);
  } catch (_) {
    return const StudentIdentity();
  }
}

Future<void> _captureAndroidUsername(
  mobile.WebViewController controller,
) async {
  try {
    await controller.runJavaScript(_captureUsernameScript);
  } catch (_) {
    // The page can be in transition while onPageFinished fires.
  }
}

StudentIdentity _decodeIdentity(Object? raw) {
  if (raw is Map) {
    return _identityFromMap(raw);
  }
  if (raw is String) {
    var value = raw;
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        final decoded = jsonDecode(value);
        if (decoded is Map) return _identityFromMap(decoded);
        if (decoded is String) {
          value = decoded;
          continue;
        }
        break;
      } catch (_) {
        break;
      }
    }
  }
  return const StudentIdentity();
}

StudentIdentity _identityFromMap(Map<dynamic, dynamic> map) {
  final id = '${map['studentId'] ?? ''}'.trim();
  final name = '${map['displayName'] ?? ''}'.trim();
  return StudentIdentity(
    studentId: id.isEmpty ? null : id,
    displayName: name.isEmpty ? null : name,
  );
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

  Future<void> _finish() async {
    if (_reading) return;
    setState(() => _reading = true);
    try {
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

      final pageIdentity = await _probeAndroidIdentity(_controller);
      final identity = pageIdentity.merge(
        fallbackStudentId: _cookieStudentId(allCookies),
      );
      if (!mounted) return;
      Navigator.of(context).pop(
        WebViewLoginResult(
          cookies: result,
          studentId: identity.studentId,
          displayName: identity.displayName,
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
            const ColoredBox(
              color: Color(0x66FFFFFF),
              child: Center(child: CircularProgressIndicator()),
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

  Future<void> _finish() async {
    final controller = _controller;
    if (controller == null || _reading) return;
    setState(() => _reading = true);
    try {
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

      final pageIdentity = await _probeWindowsIdentity(controller);
      final identity = pageIdentity.merge(
        fallbackStudentId: _cookieStudentId(cookies),
      );
      if (!mounted) return;
      Navigator.of(context).pop(
        WebViewLoginResult(
          cookies: result,
          studentId: identity.studentId,
          displayName: identity.displayName,
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
                        style: const TextStyle(
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
        backgroundColor: Colors.white,
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
                color: Colors.white.withValues(alpha: 0.94),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.line),
              ),
              child: const Text(
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
