import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../app/theme/app_theme.dart';
import '../../core/auth/auth_session.dart';

/// 官方 e码通（校园动态凭证）H5 页面。
/// 官方 App 本身就是用远端 H5 承载 e码通（见 NEUReverse 报告），这里沿用
/// 同一套做法：内嵌 webview 打开官方页面，并把 CAS 登录态（CASTGC）注入
/// pass/webvpn 域，使页面自动完成 SSO，从而显示可刷新的校园二维码。
const String _ecodeUrl = 'https://ecode.neu.edu.cn/ecode/#/';

class EcodePage extends StatefulWidget {
  const EcodePage({super.key, required this.session});

  final AuthSession session;

  @override
  State<EcodePage> createState() => _EcodePageState();
}

class _EcodePageState extends State<EcodePage> {
  WebViewController? _controller;
  bool _interactive = false;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (Platform.isAndroid) {
      _bootstrap();
    }
  }

  Future<void> _bootstrap() async {
    final controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(AppColors.surface)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (_) {
            if (mounted) setState(() => _loading = true);
          },
          onPageFinished: (_) {
            if (mounted) setState(() => _loading = false);
          },
          onWebResourceError: (error) {
            if (mounted && error.isForMainFrame == true) {
              setState(() => _error = error.description);
            }
          },
        ),
      );
    await _injectCookies();
    await controller.loadRequest(Uri.parse(_ecodeUrl));
    if (mounted) setState(() => _controller = controller);
  }

  /// 把已有的 CAS 票据注入 pass/webvpn 域，让官方 e码通页面自动 SSO 登录。
  Future<void> _injectCookies() async {
    final cookies = widget.session.cookies;
    if (cookies.isEmpty) return;
    final manager = WebViewCookieManager();
    for (final host in const ['pass.neu.edu.cn', 'webvpn.neu.edu.cn']) {
      final header = cookies[host];
      if (header == null || header.isEmpty) continue;
      for (final part in header.split(';')) {
        final index = part.indexOf('=');
        if (index <= 0) continue;
        final name = part.substring(0, index).trim();
        final value = part.substring(index + 1).trim();
        if (name.isEmpty || value.isEmpty) continue;
        try {
          await manager.setCookie(
            WebViewCookie(name: name, value: value, domain: host, path: '/'),
          );
        } catch (_) {
          // 某些平台不支持设置 Cookie，忽略即可（SSO 会退回交互登录）。
        }
      }
    }
  }

  Future<void> _reload() async {
    setState(() {
      _error = null;
      _loading = true;
    });
    await _controller?.reload();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _buildHeader(context),
        Expanded(child: _buildBody(context)),
      ],
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 14, 12, 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border(bottom: BorderSide(color: AppColors.line)),
      ),
      child: Row(
        children: [
          Icon(Icons.qr_code_2_rounded, size: 20, color: AppColors.campusBlue),
          const SizedBox(width: 8),
          Text(
            'e码通',
            style: TextStyle(
              color: AppColors.ink,
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '校园电子凭证 · 轻点二维码刷新',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: AppColors.muted, fontSize: 11),
            ),
          ),
          IconButton(
            tooltip: '刷新二维码',
            onPressed: _controller == null ? null : _reload,
            icon: Icon(Icons.refresh_rounded, size: 20, color: AppColors.campusBlue),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (!Platform.isAndroid) {
      return _placeholder('e码通目前仅在 Android 端提供，请在手机上查看。');
    }
    final controller = _controller;
    if (controller == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return Stack(
      children: [
        // 默认「轻点刷新」模式：忽略 webview 交互，任何点击都触发刷新，
        // 这样点中间的二维码即可刷新；点右上角切换按钮可进入交互模式（登录）。
        IgnorePointer(
          ignoring: !_interactive,
          child: WebViewWidget(controller: controller),
        ),
        if (!_interactive)
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _reload,
              child: const SizedBox.expand(),
            ),
          ),
        if (_loading)
          Positioned.fill(
            child: Container(
              color: AppColors.surface.withValues(alpha: 0.82),
              child: const Center(child: CircularProgressIndicator()),
            ),
          ),
        if (_error != null)
          Positioned.fill(
            child: Container(
              color: AppColors.surface,
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.wifi_off_rounded, size: 40, color: AppColors.muted),
                  const SizedBox(height: 12),
                  Text(
                    '暂时无法加载 e码通，请确认已连接校园网后重试。',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppColors.muted, fontSize: 12),
                  ),
                  const SizedBox(height: 16),
                  FilledButton(onPressed: _reload, child: const Text('重新加载')),
                ],
              ),
            ),
          ),
        Positioned(
          right: 10,
          bottom: 10,
          child: Material(
            color: AppColors.surface.withValues(alpha: 0.9),
            shape: const CircleBorder(
              side: BorderSide(color: Color(0x33000000)),
            ),
            child: IconButton(
              tooltip: _interactive ? '切换到轻点刷新' : '切换到可交互（登录/滚动）',
              onPressed: () => setState(() => _interactive = !_interactive),
              icon: Icon(
                _interactive ? Icons.touch_app_rounded : Icons.lock_open_rounded,
                size: 18,
                color: AppColors.muted,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _placeholder(String message) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: TextStyle(color: AppColors.muted, fontSize: 12),
        ),
      ),
    );
  }
}
