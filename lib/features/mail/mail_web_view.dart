import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../app/theme/app_theme.dart';
import '../../core/auth/auth_session.dart';

/// 邮件相关页面共用的 WebView：注入学校 Cookie 后打开 Coremail 页面。
///
/// 同时支持：
/// - 传入整个 [session]，把 `*.neu.edu.cn` 的 Cookie 全部注入（A 兜底/dbdxsso）；
/// - 传入 [cookieHeader]（形如 `Coremail=..; Coremail.sid=..`），只注入到
///   [cookieDomain]（通常是 `mails.neu.edu.cn`），用于详情页打开具体信件。
class MailWebView extends StatefulWidget {
  const MailWebView({
    super.key,
    required this.session,
    required this.initialUrl,
    this.cookieHeader,
    this.cookieDomain = 'mails.neu.edu.cn',
  });

  final AuthSession session;
  final String initialUrl;
  final String? cookieHeader;
  final String cookieDomain;

  @override
  State<MailWebView> createState() => _MailWebViewState();
}

class _MailWebViewState extends State<MailWebView> {
  WebViewController? _controller;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  Future<void> _start() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final cookieManager = WebViewCookieManager();
      for (final entry in widget.session.cookies.entries) {
        final host = entry.key;
        if (!host.contains('neu.edu.cn')) continue;
        for (final part in entry.value.split(';')) {
          final trimmed = part.trim();
          final eq = trimmed.indexOf('=');
          if (eq <= 0 || eq == trimmed.length - 1) continue;
          try {
            await cookieManager.setCookie(
              WebViewCookie(
                name: trimmed.substring(0, eq),
                value: trimmed.substring(eq + 1),
                domain: host,
                path: '/',
              ),
            );
          } catch (_) {}
        }
      }
      final header = widget.cookieHeader;
      if (header != null && header.isNotEmpty) {
        for (final part in header.split(';')) {
          final trimmed = part.trim();
          final eq = trimmed.indexOf('=');
          if (eq <= 0 || eq == trimmed.length - 1) continue;
          try {
            await cookieManager.setCookie(
              WebViewCookie(
                name: trimmed.substring(0, eq),
                value: trimmed.substring(eq + 1),
                domain: widget.cookieDomain,
                path: '/',
              ),
            );
          } catch (_) {}
        }
      }

      final controller = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setNavigationDelegate(
          NavigationDelegate(
            onPageStarted: (_) {
              if (mounted) setState(() => _loading = true);
            },
            onPageFinished: (_) {
              if (mounted) setState(() => _loading = false);
            },
            onWebResourceError: (error) {
              if (mounted) {
                setState(() {
                  _loading = false;
                  _error = '网页加载失败：${error.description}';
                });
              }
            },
          ),
        );
      _controller = controller;
      if (mounted) setState(() {});
      await controller.loadRequest(Uri.parse(widget.initialUrl));
    } catch (error) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = '无法打开网页：$error';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    return Stack(
      children: [
        if (controller != null)
          WebViewWidget(controller: controller)
        else
          const Center(child: CircularProgressIndicator()),
        if (_loading && controller != null)
          const Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: LinearProgressIndicator(minHeight: 2),
          ),
        if (_error != null)
          Container(
            color: AppColors.canvas,
            alignment: Alignment.center,
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.wifi_off_rounded,
                    size: 36, color: AppColors.muted),
                const SizedBox(height: 10),
                Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: AppColors.muted),
                ),
                const SizedBox(height: 12),
                OutlinedButton(
                  onPressed: _start,
                  child: const Text('重试'),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
