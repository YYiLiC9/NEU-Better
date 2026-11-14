import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../app/theme/app_theme.dart';
import '../../core/auth/auth_session.dart';

/// 余额中心里的「校园卡余额」卡片：进入页面即自动读取一号通门户上的
/// 独立「校园卡余额」组件，显示刷新后的余额。
///
/// 门户是 SPA，余额由前端组件异步渲染，服务端 HTML 里没有数字；因此用
/// 一个离屏 WebView 打开门户（注入当前会话的 neu.edu.cn Cookie 免密），
/// 轮询页面可见文本，命中「校园卡余额」后取最近数字。
class CampusCardBalanceCard extends StatefulWidget {
  const CampusCardBalanceCard({super.key, required this.session});

  final AuthSession session;

  @override
  State<CampusCardBalanceCard> createState() => _CampusCardBalanceCardState();
}

class _CampusCardBalanceCardState extends State<CampusCardBalanceCard> {
  static const _portalUrl = 'https://personal.neu.edu.cn/portal';

  WebViewController? _controller;
  String? _value;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  @override
  void dispose() {
    _controller = null;
    super.dispose();
  }

  Future<void> _start() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
      _value = null;
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

      final controller = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..addJavaScriptChannel(
          'EcardBridge',
          onMessageReceived: (message) => _onBridge(message.message),
        )
        ..setNavigationDelegate(
          NavigationDelegate(onPageFinished: (_) => _pollBalance()),
        );
      _controller = controller;
      if (mounted) setState(() {});
      await controller.loadRequest(Uri.parse(_portalUrl));
      Future.delayed(const Duration(seconds: 30), () {
        if (!mounted || _value != null) return;
        if (_loading) {
          setState(() {
            _loading = false;
            _error = '门户余额暂时没加载出来，点右侧可重试';
          });
        }
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '打开门户失败，点右侧可重试';
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
      } else if (data is Map && data['notfound'] == true) {
        setState(() {
          _loading = false;
          _error = '门户上没找到校园卡余额';
        });
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final right = _loading
        ? const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        : Text(
            _value != null ? '¥ $_value' : (_error != null ? '读取失败' : '—'),
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: _value != null ? AppColors.ink : AppColors.muted,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          );
    return Stack(
      children: [
        // 离屏 WebView：只为读取数据，不展示。
        Positioned(
          left: -2500,
          top: 0,
          width: 380,
          height: 700,
          child: _controller == null
              ? const SizedBox.shrink()
              : WebViewWidget(controller: _controller!),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.line),
          ),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: AppColors.campusBlue.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.credit_card_rounded,
                  size: 20,
                  color: AppColors.campusBlue,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '校园卡余额',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppColors.ink,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _error ?? '来自一号通门户 · 进入自动刷新',
                      style: TextStyle(fontSize: 10.5, color: AppColors.muted),
                    ),
                  ],
                ),
              ),
              right,
              IconButton(
                tooltip: '刷新',
                onPressed: _loading ? null : _start,
                icon: const Icon(Icons.refresh_rounded, size: 18),
                color: AppColors.muted,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
