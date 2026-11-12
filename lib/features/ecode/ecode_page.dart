import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../app/theme/app_theme.dart';
import '../../core/auth/auth_session.dart';

/// 官方 e码通（校园动态凭证）H5。
/// 官方 App 本身即用远端 H5 承载 e码通（见 NEUReverse 报告），这里沿用同一
/// 做法：内嵌 webview 打开官方页面并注入 CAS 登录态自动 SSO，同时用注入的
/// JS 把官方页面「除了二维码以外的所有内容」隐藏，只保留一个干净的二维码，
/// 由本 App 自己的界面承载标题与刷新。
const String _ecodeUrl = 'https://ecode.neu.edu.cn/ecode/#/';

/// 只保留页面中的二维码：隐藏其余内容并把二维码居中放大。
/// 脚本会自我轮询（页面/JS 渲染后二维码才出现）并监听 DOM 变化，重复应用。
const String _cleanScript = r"""
(function(){
  function square(r){
    if(r.width<120||r.height<120) return false;
    var d=Math.abs(r.width-r.height);
    return d < Math.max(r.width,r.height)*0.28;
  }
  function pick(){
    var els=[].slice.call(document.querySelectorAll('img,canvas'));
    var best=null,area=0;
    els.forEach(function(el){
      if(el.tagName==='IMG' && (el.naturalWidth&&el.naturalWidth<60)) return;
      var r=el.getBoundingClientRect();
      if(square(r)){var a=r.width*r.height; if(a>area){area=a;best=el;}}
    });
    if(!best){
      var c=[].slice.call(document.querySelectorAll('canvas,img')).filter(function(e){var r=e.getBoundingClientRect();return r.width>80&&r.height>80;});
      if(c.length){c.sort(function(a,b){return b.getBoundingClientRect().width-a.getBoundingClientRect().width;});best=c[0];}
    }
    return best;
  }
  function apply(){
    try{
      var t=pick();
      if(!t) return false;
      var chain=[],n=t;
      while(n&&n!==document.body){chain.push(n);n=n.parentElement;}
      chain.reverse();
      chain.forEach(function(el){
        if(el.parentElement){
          [].slice.call(el.parentElement.children).forEach(function(s){ if(s!==el) s.style.display='none'; });
        }
        el.style.background='transparent'; el.style.boxShadow='none'; el.style.border='0';
      });
      document.documentElement.style.background='#F6F8FB';
      document.body.style.margin='0';
      document.body.style.background='#F6F8FB';
      var m=Math.min(window.innerWidth,window.innerHeight)*0.62;
      t.style.position='fixed'; t.style.left='50%'; t.style.top='50%';
      t.style.transform='translate(-50%,-50%)';
      t.style.width=m+'px'; t.style.height=m+'px';
      t.style.maxWidth='92vw'; t.style.maxHeight='92vw';
      t.style.zIndex='2147483647'; t.style.display='block';
      if(window.EcodeBridge){ window.EcodeBridge.postMessage('ready'); }
      return true;
    }catch(e){ return false; }
  }
  if(apply()){ return 'first'; }
  var n=0, iv=setInterval(function(){ n++; if(apply()||n>50){ clearInterval(iv); } }, 150);
  try{ var mo=new MutationObserver(function(){ apply(); }); mo.observe(document.body,{childList:true,subtree:true,attributes:true}); setTimeout(function(){ mo.disconnect(); },12000); }catch(e){}
  return 'poll';
})();
""";

class EcodePage extends StatefulWidget {
  const EcodePage({super.key, required this.session});

  final AuthSession session;

  @override
  State<EcodePage> createState() => _EcodePageState();
}

class _EcodePageState extends State<EcodePage> {
  WebViewController? _controller;
  bool _interactive = false;
  bool _ready = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (Platform.isAndroid) {
      _bootstrap();
    }
  }

  Future<void> _bootstrap() async {
    final controller = WebViewController();
    controller
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFFF6F8FB))
      ..addJavaScriptChannel(
        'EcodeBridge',
        onMessageReceived: (message) {
          if (!mounted) return;
          if (message.message == 'ready' && !_ready) {
            setState(() => _ready = true);
          }
        },
      );
    controller.setNavigationDelegate(
      NavigationDelegate(
        onPageFinished: (_) => controller.runJavaScript(_cleanScript),
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
          // 某些平台不支持设置 Cookie，忽略（SSO 会退回交互登录）。
        }
      }
    }
  }

  Future<void> _reload() async {
    setState(() {
      _error = null;
      _ready = false;
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
            icon: Icon(
              Icons.refresh_rounded,
              size: 20,
              color: AppColors.campusBlue,
            ),
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
        // 默认「轻点刷新」：忽略 webview 交互，点任意处（含二维码）即刷新。
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
        // 加载/清洗完成前用底色盖住，避免官方页面内容一闪而过。
        if (!_ready && _error == null)
          Positioned.fill(
            child: Container(
              color: const Color(0xFFF6F8FB),
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
              side: BorderSide(color: Color(0x22000000)),
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
