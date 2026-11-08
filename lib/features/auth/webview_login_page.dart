import 'package:flutter/material.dart';
import 'package:webview_all/webview_all.dart';

import '../../app/theme/app_theme.dart';
import '../../core/network/neu_cas_client.dart';

/// Browser fallback for QR/device verification or if the CAS page changes.
class WebViewLoginPage extends StatefulWidget {
  const WebViewLoginPage({super.key});

  @override
  State<WebViewLoginPage> createState() => _WebViewLoginPageState();
}

class _WebViewLoginPageState extends State<WebViewLoginPage> {
  late final WebViewController _controller;
  bool _loading = true;
  bool _reading = false;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
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
        final cookies = await WebViewCookieManager().getCookies(
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
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(
        title: const Text('学校网页登录'),
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        actions: [
          TextButton(
            onPressed: _reading ? null : _finish,
            child: _reading
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
          WebViewWidget(controller: _controller),
          if (_loading)
            const ColoredBox(
              color: Color(0x66FFFFFF),
              child: Center(child: CircularProgressIndicator()),
            ),
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
