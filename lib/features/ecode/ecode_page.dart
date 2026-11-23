import 'dart:async';

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../app/theme/app_theme.dart';
import '../../core/auth/auth_session.dart';
import '../../core/auth/credential_store.dart';
import '../../core/network/ecode_client.dart';

/// 安卓 e码通：原生拉取 `ecode/api/qr-code` 并在本地渲染二维码。
///
/// 相比内嵌官方 H5（WebView 首屏约 5~11 秒），原生接口 + 本地 QR 渲染可在
/// 已有 Cookie 时亚秒级出码，并可按二维码有效期自动刷新。
class EcodePage extends StatefulWidget {
  const EcodePage({super.key, required this.session});

  final AuthSession session;

  @override
  State<EcodePage> createState() => _EcodePageState();
}

class _EcodePageState extends State<EcodePage> {
  final EcodeClient _client = EcodeClient();
  final EcodeCookieStore _cookieStore = const EcodeCookieStore();

  EcodeQr? _qr;
  String? _error;
  bool _loading = true;
  bool _busy = false;
  Timer? _timer;
  final Stopwatch _watch = Stopwatch()..start();
  bool _loggedReady = false;
  WebViewController? _webController;
  bool _webFallback = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load(initial: true));
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<String> _ensureCookie() async {
    final cached = await _cookieStore.read();
    if (cached != null) return cached;
    String? cookie;
    final pass = passCookieOf(widget.session);
    if (pass.isNotEmpty) {
      try {
        cookie = await _client.loginWithPassCookie(pass);
      } catch (error) {
        debugPrint('[ecode-native] pass-cookie login failed: $error');
      }
    }
    if (cookie == null) {
      final saved = await const SecureCredentialStore().read();
      debugPrint(
        '[ecode-native] saved credential: user=${saved?.username} '
        'hasPassword=${saved?.password?.isNotEmpty ?? false}',
      );
      final password = saved?.password;
      if (saved != null &&
          password != null &&
          password.isNotEmpty &&
          saved.username.trim().isNotEmpty) {
        cookie = await _client.login(
          username: saved.username.trim(),
          password: password,
        );
      }
    }
    if (cookie == null) {
      throw const EcodeException('无法自动登录 e码通，请先在设置里保存账号密码或重新登录');
    }
    await _cookieStore.save(cookie);
    return cookie;
  }

  Future<EcodeQr> _fetchWithRetry() async {
    try {
      final cookie = await _ensureCookie();
      return await _client.fetchQr(cookie);
    } on EcodeException {
      await _cookieStore.clear();
      final cookie = await _ensureCookie();
      return _client.fetchQr(cookie);
    }
  }

  Future<void> _load({bool initial = false}) async {
    if (initial && mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final qr = await _fetchWithRetry();
      if (!mounted) return;
      if (!_loggedReady) {
        _loggedReady = true;
        debugPrint('[ecode-native] first ready in ${_watch.elapsedMilliseconds}ms');
      }
      setState(() {
        _qr = qr;
        _loading = false;
        _error = null;
        _busy = false;
      });
      _schedule();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _busy = false;
        _error = error is EcodeException ? error.message : '获取二维码失败：$error';
      });
    }
  }

  void _schedule() {
    _timer?.cancel();
    final life = _qr?.lifetime.inMilliseconds ?? 10000;
    final wait = Duration(milliseconds: (life - 1500).clamp(2500, 30000));
    _timer = Timer(wait, () {
      if (!mounted) return;
      unawaited(_load());
    });
  }

  Future<void> _manualRefresh() async {
    if (_busy) return;
    setState(() => _busy = true);
    await _load();
    if (mounted && _busy) {
      setState(() => _busy = false);
    }
  }

  /// 极端兜底：会话过期且未保存密码时，用网页登录一次换取 ecode Cookie，
  /// 之后仍走原生接口（避免每次都加载 H5）。
  Future<void> _startWebFallback() async {
    final controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted);
    final manager = WebViewCookieManager();
    for (final entry in widget.session.cookies.entries) {
      final host = entry.key;
      if (!host.endsWith('neu.edu.cn')) continue;
      for (final part in entry.value.split(';')) {
        final t = part.trim();
        final i = t.indexOf('=');
        if (i <= 0) continue;
        try {
          await manager.setCookie(
            WebViewCookie(
              name: t.substring(0, i),
              value: t.substring(i + 1),
              domain: host,
              path: '/',
            ),
          );
        } catch (_) {}
      }
    }
    controller.setNavigationDelegate(
      NavigationDelegate(
        onPageFinished: (url) async {
          if (!url.contains('ecode.neu.edu.cn')) return;
          if (url.contains('/tpass/') || url.contains('/sso/')) return;
          try {
            final cookies = await manager.getCookies(
              domain: Uri.parse('https://ecode.neu.edu.cn/ecode/api'),
            );
            final header = cookies
                .map((c) => '${c.name}=${c.value}')
                .join('; ');
            if (cookies.any((c) => c.name == 'SESSION')) {
              await _cookieStore.save(header);
              if (!mounted) return;
              setState(() {
                _webFallback = false;
                _webController = null;
              });
              await _load(initial: true);
            }
          } catch (error) {
            debugPrint('[ecode-native] web fallback failed: $error');
          }
        },
      ),
    );
    await controller.loadRequest(
      Uri.parse('https://ecode.neu.edu.cn/ecode/'),
    );
    if (!mounted) return;
    setState(() {
      _webController = controller;
      _webFallback = true;
    });
  }

  String _fmt(DateTime t) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(t.hour)}:${two(t.minute)}:${two(t.second)}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.canvas,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 10, 0),
              child: Row(
                children: [
                  Text(
                    'e码通',
                    style: TextStyle(
                      color: AppColors.ink,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    tooltip: '刷新二维码',
                    onPressed: _busy ? null : _manualRefresh,
                    icon: _busy
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Icon(
                            Icons.refresh_rounded,
                            color: AppColors.campusBlue,
                          ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(left: 20, bottom: 6),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '校园通行二维码 · 自动刷新',
                  style: TextStyle(color: AppColors.muted, fontSize: 11),
                ),
              ),
            ),
            Expanded(
              child: (_webFallback && _webController != null)
                  ? WebViewWidget(controller: _webController!)
                  : Center(child: _buildBody()),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_error != null) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.qr_code_2_rounded, size: 46, color: AppColors.faint),
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: Text(
              _error!,
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.muted, fontSize: 12.5, height: 1.5),
            ),
          ),
          const SizedBox(height: 14),
          FilledButton(
            onPressed: _loading ? null : _manualRefresh,
            child: const Text('重试'),
          ),
          const SizedBox(height: 6),
          TextButton(
            onPressed: _startWebFallback,
            child: const Text('用网页登录一次（首次）'),
          ),
        ],
      );
    }
    if (_qr == null) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(strokeWidth: 2.4),
          const SizedBox(height: 12),
          Text(
            '正在获取二维码…',
            style: TextStyle(color: AppColors.muted, fontSize: 12.5),
          ),
        ],
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final qrSize = (constraints.maxWidth - 96).clamp(180.0, 260.0);
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _manualRefresh,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: AppColors.line),
                  boxShadow: AppColors.isDark
                      ? null
                      : const [
                          BoxShadow(
                            color: Color(0x140B2E5C),
                            blurRadius: 26,
                            offset: Offset(0, 12),
                          ),
                        ],
                ),
                child: QrImageView(
                  data: _qr!.code,
                  version: QrVersions.auto,
                  size: qrSize,
                  backgroundColor: Colors.white,
                ),
              ),
              const SizedBox(height: 14),
              Text(
                '有效至 ${_fmt(_qr!.invalidTime)}',
                style: TextStyle(
                  color: AppColors.ink,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '点按二维码可手动刷新',
                style: TextStyle(color: AppColors.muted, fontSize: 11),
              ),
            ],
          ),
        );
      },
    );
  }
}
