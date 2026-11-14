import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../app/theme/app_theme.dart';
import '../../core/auth/auth_session.dart';

/// 从「一号通门户」首页读取单独的「校园卡余额」组件。
///
/// 门户是 SPA：余额数字由前端组件异步渲染，服务端 HTML 里没有。这里用
/// 一个离屏 WebView 打开门户（把当前登录会话的 Cookie 注入，走统一身份
/// 免密登录），轮询页面可见文本，命中「校园卡余额」后取最近的数字。
class CampusCardPage extends StatefulWidget {
  const CampusCardPage({super.key, required this.session});

  final AuthSession session;

  @override
  State<CampusCardPage> createState() => _CampusCardPageState();
}

class _CampusCardPageState extends State<CampusCardPage> {
  static const _portalUrl = 'https://personal.neu.edu.cn/portal';

  WebViewController? _controller;
  String? _value;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    setState(() {
      _loading = true;
      _error = null;
      _value = null;
    });
    try {
      final cookieManager = WebViewCookieManager();
      // 把会话里 neu.edu.cn 各域名的 Cookie 注入 WebView，实现免密登录。
      for (final entry in widget.session.cookies.entries) {
        final host = entry.key;
        if (!host.contains('neu.edu.cn')) continue;
        for (final part in entry.value.split(';')) {
          final trimmed = part.trim();
          final eq = trimmed.indexOf('=');
          if (eq <= 0 || eq == trimmed.length - 1) continue;
          final name = trimmed.substring(0, eq);
          final value = trimmed.substring(eq + 1);
          try {
            await cookieManager.setCookie(
              WebViewCookie(name: name, value: value, domain: host, path: '/'),
            );
          } catch (_) {}
        }
      }

      final controller = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..addJavaScriptChannel(
          'EcardBridge',
          onMessageReceived: (message) => _onBridge(message.message),
        )
        ..setNavigationDelegate(
          NavigationDelegate(
            onPageFinished: (_) => _pollBalance(),
            onWebResourceError: (_) {},
          ),
        );
      _controller = controller;
      await controller.loadRequest(Uri.parse(_portalUrl));
      // 兜底超时：门户组件若一直没出数字，给出可重试的错误。
      Future.delayed(const Duration(seconds: 30), () {
        if (!mounted || _value != null) return;
        if (_loading) {
          setState(() {
            _loading = false;
            _error = '门户「校园卡余额」暂时没加载出来，请重试';
          });
        }
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '打开门户失败：$error';
      });
    }
  }

  Future<void> _pollBalance() async {
    final controller = _controller;
    if (controller == null) return;
    try {
      await controller.runJavaScript(r'''
(function(){
  var tries = 0;
  function post(o){ try { EcardBridge.postMessage(JSON.stringify(o)); } catch(e){} }
  function tick(){
    tries++;
    var t = document.body ? (document.body.innerText || '') : '';
    if (t) {
      var m = t.match(/(?:校园卡余额|一卡通余额|卡余额)[^0-9]{0,30}([0-9]+(?:\.[0-9]{1,2})?)/);
      if (m) { post({value: m[1]}); return; }
    }
    if (location.href.indexOf('cas') >= 0 || t.indexOf('统一身份认证') >= 0 && t.indexOf('校园卡') < 0) {
      if (tries > 3) { post({login: true}); return; }
    }
    if (tries < 40) { setTimeout(tick, 800); return; }
    post({notfound: true});
  }
  tick();
})();
''');
    } catch (_) {}
  }

  void _onBridge(String raw) {
    if (!mounted) return;
    try {
      final data = jsonDecode(raw);
      if (data is Map && data['value'] is String) {
        setState(() {
          _value = (data['value'] as String).trim();
          _loading = false;
          _error = null;
        });
      } else if (data is Map && data['login'] == true) {
        setState(() {
          _loading = false;
          _error = '门户登录态已失效，请重新登录后重试';
        });
      } else if (data is Map && data['notfound'] == true) {
        setState(() {
          _loading = false;
          _error = '没有在门户上找到「校园卡余额」，请重试';
        });
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(
        title: const Text('校园卡余额'),
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.ink,
        elevation: 0,
      ),
      body: Stack(
        children: [
          // 离屏 WebView：只为读取页面数据，不展示。
          Positioned(
            left: -3000,
            top: 0,
            width: 380,
            height: 700,
            child: _controller == null
                ? const SizedBox.shrink()
                : WebViewWidget(controller: _controller!),
          ),
          Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.credit_card_rounded,
                    size: 44,
                    color: AppColors.campusBlue,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    '校园卡余额',
                    style: TextStyle(fontSize: 14, color: AppColors.muted),
                  ),
                  const SizedBox(height: 10),
                  if (_loading)
                    const Padding(
                      padding: EdgeInsets.all(8),
                      child: CircularProgressIndicator(strokeWidth: 2.4),
                    )
                  else if (_value != null)
                    Text(
                      '¥ $_value',
                      style: TextStyle(
                        fontSize: 40,
                        fontWeight: FontWeight.w700,
                        color: AppColors.ink,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    )
                  else
                    Text(
                      _error ?? '读取失败',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 12.5, color: AppColors.danger),
                    ),
                  const SizedBox(height: 22),
                  OutlinedButton.icon(
                    onPressed: _loading ? null : _start,
                    icon: const Icon(Icons.refresh_rounded, size: 18),
                    label: const Text('重新读取'),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    '数据来自一号通门户 · 校园卡余额',
                    style: TextStyle(fontSize: 10, color: AppColors.faint),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
