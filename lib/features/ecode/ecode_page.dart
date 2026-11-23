import 'dart:async';

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

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

class _EcodePageState extends State<EcodePage> with WidgetsBindingObserver {
  final EcodeClient _client = EcodeClient();
  final EcodeCookieStore _cookieStore = const EcodeCookieStore();

  EcodeQr? _qr;
  String? _error;
  bool _loading = true;
  bool _busy = false;
  Timer? _timer;
  Timer? _retryTimer;
  int _failureCount = 0;
  bool _reloginPrompted = false;
  final Stopwatch _watch = Stopwatch()..start();
  bool _loggedReady = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_refresh(initial: true));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _retryTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      // 息屏/切后台时停止定时器，避免无效请求；恢复时立即补一次。
      _timer?.cancel();
      _retryTimer?.cancel();
      return;
    }
    if (state == AppLifecycleState.resumed) {
      _failureCount = 0;
      _reloginPrompted = false;
      if (mounted) {
        setState(() {
          _error = null;
          if (_qr == null) _loading = true;
        });
      }
      unawaited(_refresh());
    }
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

  Future<void> _refresh({bool initial = false, bool manual = false}) async {
    _retryTimer?.cancel();
    if (initial && mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final qr = await _fetchWithRetry();
      if (!mounted) return;
      _failureCount = 0;
      _reloginPrompted = false;
      if (!_loggedReady) {
        _loggedReady = true;
        debugPrint('[ecode-native] first ready in ${_watch.elapsedMilliseconds}ms');
      }
      debugPrint(
        '[ecode-native] refresh ok at ${DateTime.now().toIso8601String()}',
      );
      setState(() {
        _qr = qr;
        _loading = false;
        _error = null;
        _busy = false;
      });
      _schedule();
    } catch (error) {
      if (!mounted) return;
      _failureCount++;
      debugPrint('[ecode-native] fetch failed ($_failureCount/3): $error');
      if (_failureCount < 3) {
        // 前两次失败：保留当前二维码，2 秒后自动重试。
        setState(() {
          _loading = false;
          _busy = false;
        });
        _retryTimer = Timer(const Duration(seconds: 2), () {
          if (mounted) unawaited(_refresh(manual: manual));
        });
      } else {
        // 连续失败三次：停止自动刷新并提示重新登录。
        setState(() {
          _loading = false;
          _busy = false;
          _error = _describeError(error);
        });
        _promptRelogin();
      }
    }
  }

  void _schedule() {
    _timer?.cancel();
    // 按二维码生命周期的一半续码（上限 5 秒、下限 2 秒），确保展示的码始终在有效期内。
    final life = _qr?.lifetime.inMilliseconds ?? 10000;
    final waitMs = (life ~/ 2).clamp(2000, 5000);
    _timer = Timer(Duration(milliseconds: waitMs), () {
      if (!mounted) return;
      unawaited(_refresh());
    });
  }

  Future<void> _manualRefresh() async {
    if (_busy) return;
    setState(() => _busy = true);
    _failureCount = 0;
    _retryTimer?.cancel();
    await _refresh(manual: true);
    if (mounted && _busy) {
      setState(() => _busy = false);
    }
  }

  String _describeError(Object error) {
    if (error is EcodeException) return error.message;
    final text = error.toString();
    if (text.contains('Failed host lookup') ||
        text.contains('SocketException') ||
        text.contains('Connection') ||
        text.contains('Timeout')) {
      return '网络连接失败，请检查网络后重试';
    }
    return '获取二维码失败，请稍后重试';
  }

  void _promptRelogin() {
    if (_reloginPrompted || !mounted) return;
    _reloginPrompted = true;
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('需要重新登录'),
        content: const Text('e码通登录状态已失效或网络异常，请检查网络后重试；若仍失败请重新登录后再使用。'),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('知道了'),
          ),
        ],
      ),
    );
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
              child: Center(child: _buildBody()),
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
              const SizedBox(height: 12),
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
