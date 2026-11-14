import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../app/theme/app_theme.dart';
import '../../core/auth/auth_session.dart';
import '../../core/auth/credential_store.dart';
import '../../core/network/neu_cas_client.dart';

/// 官方 e码通（校园动态凭证）H5。
/// 官方 App 本身即用远端 H5 承载 e码通（见 NEUReverse 报告），这里沿用同一
/// 做法：内嵌 webview 打开官方页面并注入 CAS 登录态自动 SSO，同时用注入的
/// JS 把官方页面「除了二维码以外的所有内容」隐藏，只保留一个干净的二维码，
/// 由本 App 自己的界面承载标题与刷新。
const String _ecodeUrl = 'https://ecode.neu.edu.cn/ecode/#/';

/// 只保留页面中的二维码：隐藏其余内容并把二维码居中放大。
/// 脚本自我轮询（页面/JS 渲染后二维码才出现）并监听 DOM 变化；一旦检测不到
/// 二维码（例如刷新/重新渲染的间隙），就先盖一层底色，杜绝官方界面（含宣传
/// 图、姓名卡）一闪而过。
const String _cleanScript = r"""
(function(){
  function isSquare(r){
    return r.width>=100 && r.height>=100 &&
      Math.abs(r.width-r.height) < Math.max(r.width,r.height)*0.35;
  }
  // 二维码可能是 canvas，也可能是任意来源的 <img>（data/blob 或服务端 URL）。
  // 宣传图/横幅是宽矩形，会被“近似正方形”条件排除，所以不再限制 src —— 旧实现
  // 只认 data:/blob: 图片，一旦官方 H5 改用服务端二维码图片就会一直识别不到、
  // 停留在空白盖层（即“长时间白屏”）。
  function pick(){
    var best=null, area=0, i, r, a;
    function consider(el){
      r=el.getBoundingClientRect();
      if(isSquare(r)){ a=r.width*r.height; if(a>area){area=a;best=el;} }
    }
    var cs=document.querySelectorAll('canvas');
    for(i=0;i<cs.length;i++){ consider(cs[i]); }
    if(best) return best;
    var imgs=document.querySelectorAll('img');
    for(i=0;i<imgs.length;i++){ consider(imgs[i]); }
    if(best) return best;
    var hinted=document.querySelectorAll('[class*="qr" i],[id*="qr" i],[class*="qrcode" i]');
    for(i=0;i<hinted.length;i++){
      var h=hinted[i];
      if(!h.getBoundingClientRect) continue;
      // 只认“真正承载图像”的元素：内部 canvas/img，或带 background-image 的元素。
      // 官方“获取失败”占位块是一个带边框的方形容器（里面有“获取失败”文字，但
      // 尚无二维码图像），以前会把这个容器误判成二维码导致失败界面一闪而过。
      var inner=h.querySelector('canvas,img');
      if(inner){ consider(inner); continue; }
      try{
        var bg=window.getComputedStyle(h).backgroundImage||'';
        if(bg && bg!=='none' && bg.indexOf('url(')>=0) consider(h);
      }catch(e){}
    }
    return best;
  }
  function cover(on){
    try{
      var id='__ecode_cover__';
      var c=document.getElementById(id);
      if(on){
        if(!c){
          c=document.createElement('div'); c.id=id;
          c.style.cssText='position:fixed;left:0;top:0;right:0;bottom:0;background:#F6F8FB;z-index:2147483646;';
          (document.body||document.documentElement).appendChild(c);
        }
      } else if(c && c.parentNode){ c.parentNode.removeChild(c); }
    }catch(e){}
  }
  function ensureStyle(){
    try{
      if(document.getElementById('ecode_style')) return;
      var s=document.createElement('style'); s.id='ecode_style';
      s.textContent='canvas:not(.ecode-qr),img:not(.ecode-qr){visibility:hidden !important;}';
      (document.head||document.documentElement).appendChild(s);
    }catch(e){}
  }
  var lastEl=null;
  var applying=false;
  // 首次就绪前要求候选“稳定”若干次，避免把官方“获取失败/加载中”页面里的
  // 方形插图误判成二维码，导致失败界面一闪而过。
  var stableEl=null;
  var stable=0;
  var everReady=false;
  function apply(){
    if(applying) return false;
    applying=true;
    try{
      ensureStyle();
      var t=pick();
      if(!t){ stable=0; stableEl=null; cover(true); return false; } // 二维码渲染中：先用底色盖住，避免露出官方界面
      if(!everReady){
        // 首次确认前，候选需连续约 480ms(8×60ms) 保持同一元素才认作二维码；
        // 官方“获取失败”占位块会很快被真码替换，从而不会被当成二维码。
        if(t===stableEl){ stable++; } else { stableEl=t; stable=0; }
        if(stable<8){ cover(true); return false; }
      }
      t.classList.add('ecode-qr'); // 标记为已识别二维码（未被标记的 canvas/img 一律隐藏，杜绝未定位时的错位闪现）
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
      // 新出现的二维码元素先盖一层底色再显示（避免官方界面/宣传图闪一下），
      // 同一元素在后续 tick 里再撤销底色只留二维码。
      var isNew = (t!==lastEl);
      lastEl=t;
      everReady=true;
      cover(isNew);
      if(window.EcodeBridge){ window.EcodeBridge.postMessage('ready'); }
      return true;
    }catch(e){ return false; }
    finally{ applying=false; }
  }
  apply();
  // 官方 H5 会周期性自动换码（会替换 DOM 中的二维码元素），因此常驻高频轮询，
  // 保证每次换码后依旧只居中显示二维码、且换码间隙始终用底色盖住官方界面。
  setInterval(apply, 60);
  // DOM 变动（换码时可能替换/重建二维码节点）时立刻重新应用，抢在下一帧绘制前
  // 把新节点标记并居中，避免出现一帧空白/错位。
  try{ new MutationObserver(function(){ if(!applying) apply(); }).observe(document.body,{childList:true,subtree:true}); }catch(e){}
  // 点击刷新时直接触发页面自身的换码方法（getUserCode），在同一个页面内原地换码，
  // 不重新加载页面 → 无加载圈、无白屏/官方界面闪烁。
  function findVue(){
    try{
      var el=document.querySelector('#app');
      if(!el) return null;
      var root=el.__vue__ || (el.__vue_app__ && el.__vue_app__._instance) || null;
      var seen=[], stack=[root];
      while(stack.length){
        var v=stack.pop();
        if(!v || seen.indexOf(v)>=0) continue;
        seen.push(v);
        if(typeof v.getUserCode==='function') return v;
        if(v.$children && v.$children.length) stack.push.apply(stack, v.$children);
      }
    }catch(e){}
    return null;
  }
  window.__ecodeRefreshNow = function(){
    try{
      var v=findVue();
      if(v){ v.getUserCode(); return 'ok'; }
      var r=document.querySelector('[class*="refresh" i],[aria-label*="刷新"],[title*="刷新"]');
      if(r && typeof r.click==='function'){ r.click(); return 'ok'; }
      return 'none';
    }catch(e){ return 'err'; }
  };
  return 'loop';
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
  bool _ready = false;
  String? _error;
  Timer? _timeout;
  Timer? _errorTimer;
  bool _recoverTried = false;

  @override
  void initState() {
    super.initState();
    if (Platform.isAndroid) {
      _bootstrap();
    }
  }

  @override
  void dispose() {
    _timeout?.cancel();
    _errorTimer?.cancel();
    super.dispose();
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
          if (message.message == 'ready') {
            _errorTimer?.cancel();
            _timeout?.cancel();
            if (!_ready || _error != null) {
              setState(() {
                _ready = true;
                _error = null;
              });
            }
          }
        },
      );
    controller.setNavigationDelegate(
      NavigationDelegate(
        // 一进入新页面就注入清洗脚本，尽早隐藏官方页面（含其自身的
        // “获取失败/加载中”提示），避免快速切换时露出一瞬非二维码内容。
        onPageStarted: (_) async {
          try {
            await controller.runJavaScript(_cleanScript);
          } catch (_) {}
        },
        onPageFinished: (_) => _onPageFinished(controller),
        onWebResourceError: (error) {
          // 页面跳转/SSO 重定向/冷启动首帧会报瞬时错误；一律不弹错误页，
          // 真正失败交给 18 秒超时兜底，从根本上杜绝“失败界面一闪而过”。
          debugPrint('[ecode] web resource error: ${error.description}');
        },
      ),
    );
    await _injectCookies();
    await controller.loadRequest(Uri.parse(_ecodeUrl));
    if (mounted) setState(() => _controller = controller);
    _armTimeout();
  }

  /// 首次加载最多等 18 秒；超时仍未拿到二维码就转为可重试的错误态，
  /// 避免一直停在空白盖层（会话过期/网络异常时页面可能既不报错也不出码）。
  void _armTimeout() {
    _timeout?.cancel();
    _timeout = Timer(const Duration(seconds: 30), () {
      if (!mounted || _ready) return;
      final controller = _controller;
      if (controller != null) unawaited(_logDiagnostics(controller));
      setState(
        () => _error =
            'e码通加载超时。请确认已连接校园网；若登录状态已失效，请返回重新登录后再试。',
      );
    });
  }

  Future<void> _onPageFinished(WebViewController controller) async {
    _errorTimer?.cancel();
    if (_error != null && mounted) setState(() => _error = null);
    await controller.runJavaScript(_cleanScript);
    // 如果页面被重定向到 CAS 登录页，说明注入的会话票据已失效：
    // 用已保存的账号密码重新登录 CAS（service=ecode 的 SSO 入口），拿到新的
    // pass/ecode cookies 后重新注入并重载，实现自动恢复。
    final url = await controller.currentUrl();
    if (url != null &&
        (url.contains('pass.neu.edu.cn') || url.contains('/tpass/login'))) {
      await _recoverExpiredSession(controller);
      return;
    }
    _armTimeout();
    unawaited(_logDiagnostics(controller));
  }

  /// 会话过期自动恢复：用保存的账号密码对 ecode 的 CAS SSO 入口重新登录，
  /// 把新拿到的 pass/ecode cookies 注入 WebView 后重载。只尝试一次。
  Future<void> _recoverExpiredSession(WebViewController controller) async {
    if (_recoverTried) {
      if (mounted) {
        setState(
          () => _error = 'e码通登录状态已失效，请返回重新登录后再试。',
        );
      }
      return;
    }
    _recoverTried = true;
    try {
      final saved = await const SecureCredentialStore().read();
      final password = saved?.password;
      if (saved == null ||
          saved.username.trim().isEmpty ||
          password == null ||
          password.isEmpty) {
        if (mounted) {
          setState(
            () => _error = 'e码通登录状态已失效，请返回重新登录后再试。',
          );
        }
        return;
      }
      debugPrint('[ecode] session expired, re-login as ${saved.username}');
      // 先用默认门户 service 重新登录 CAS，拿到新的 pass.neu.edu.cn 票据
      // （CASTGC）；随后重载 ecode 页面，由 CAS 用该票据换 ecode 的 service
      // ticket 完成 SSO。直接把 ecode 的 SSO 入口当 service 会 404。
      final cas = await NeuCasClient()
          .login(username: saved.username, password: password)
          .timeout(const Duration(seconds: 35));
      await _applyCookieMap(WebViewCookieManager(), cas.cookies);
      if (!mounted) return;
      setState(() => _error = null);
      await controller.loadRequest(Uri.parse(_ecodeUrl));
      _armTimeout();
    } catch (error) {
      debugPrint('[ecode] recover failed: $error');
      if (mounted) {
        setState(
          () => _error = 'e码通登录状态已失效，请返回重新登录后再试。',
        );
      }
    }
  }

  Future<void> _applyCookieMap(
    WebViewCookieManager manager,
    Map<String, String> cookieMap,
  ) async {
    for (final entry in cookieMap.entries) {
      final host = entry.key;
      if (!host.endsWith('neu.edu.cn')) continue;
      for (final part in entry.value.split(';')) {
        final index = part.indexOf('=');
        if (index <= 0) continue;
        final name = part.substring(0, index).trim();
        final value = part.substring(index + 1).trim();
        if (name.isEmpty || value.isEmpty) continue;
        try {
          await manager.setCookie(
            WebViewCookie(name: name, value: value, domain: host, path: '/'),
          );
        } catch (_) {}
      }
    }
  }

  /// 诊断：页面加载完后打印当前 URL / 二维码候选数量 / 页面可见文字，
  /// 便于区分「登录失效」「H5 未渲染」「识别不到二维码」等原因。
  Future<void> _logDiagnostics(WebViewController controller) async {
    await Future<void>.delayed(const Duration(seconds: 4));
    if (!mounted) return;
    try {
      final url = await controller.currentUrl();
      final result = await controller.runJavaScriptReturningResult(
        r"""(function(){
          try{
            var cvs=document.querySelectorAll('canvas').length;
            var imgs=document.querySelectorAll('img').length;
            var txt=document.body?document.body.innerText.replace(/\s+/g,' ').slice(0,180):'';
            return 'href='+location.href+' canvas='+cvs+' img='+imgs+' text='+txt;
          }catch(e){return 'diagerr '+e;}
        })()""",
      );
      debugPrint('[ecode][diag] page=$url js=$result');
    } catch (error) {
      debugPrint('[ecode][diag] failed: $error');
    }
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
    final controller = _controller;
    if (controller == null) return;
    _errorTimer?.cancel();
    setState(() => _error = null);
    _armTimeout();
    // 优先原地换码：不重载页面、不显示加载圈，新二维码就绪后直接覆盖旧码。
    try {
      final result = await controller.runJavaScriptReturningResult(
        '(window.__ecodeRefreshNow && window.__ecodeRefreshNow()) || "none"',
      );
      debugPrint('[ecode] refresh -> $result');
      if ('$result'.contains('ok')) return;
    } catch (error) {
      debugPrint('[ecode] refresh js failed: $error');
    }
    // 兜底：仅当页面自身换码不可用时才整体重载（不显示加载圈，尽量不闪烁）。
    setState(() => _ready = false);
    await controller.reload();
    _armTimeout();
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
        // 轻点任意处（含二维码）即刷新：webview 不接收交互，用透明层接管点击。
        IgnorePointer(
          ignoring: true,
          child: WebViewWidget(controller: controller),
        ),
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _reload,
            child: const SizedBox.expand(),
          ),
        ),
        // 加载/清洗完成前用底色盖住，避免官方页面内容一闪而过。
        if (!_ready && _error == null)
          const Positioned.fill(
            child: ColoredBox(
              color: Color(0xFFF6F8FB),
              child: Center(child: CircularProgressIndicator()),
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
                    _error ?? '暂时无法加载 e码通，请确认已连接校园网后重试。',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppColors.muted, fontSize: 12),
                  ),
                  const SizedBox(height: 16),
                  FilledButton(onPressed: _reload, child: const Text('重新加载')),
                ],
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
