import 'dart:io' show Directory, FileSystemException, Platform;

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart' as mobile;
import 'package:webview_flutter_windows/webview_flutter_windows.dart' as desktop;

import '../../app/theme/app_theme.dart';
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
      for (final host in const ['pass.neu.edu.cn', 'personal.neu.edu.cn']) {
        final cookies = await mobile.WebViewCookieManager().getCookies(
          domain: Uri.parse('https://$host'),
        );
        if (cookies.isEmpty) continue;
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
      Navigator.of(context).pop(result);
    } finally {
      if (mounted) setState(() => _reading = false);
    }
  }

  void _showEmptyCookieMessage() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('还没有取得登录会话，请先在网页中完成登录。')),
    );
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
        dataDir = Directory('${Directory.systemTemp.path}\\NEU Better\\WebView2');
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
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('还没有取得登录会话，请先在网页中完成登录。')),
        );
        return;
      }
      Navigator.of(context).pop(result);
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
