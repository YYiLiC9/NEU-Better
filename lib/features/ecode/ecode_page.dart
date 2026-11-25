import 'dart:async';

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../app/theme/app_theme.dart';
import '../../core/auth/auth_session.dart';
import '../../core/auth/credential_store.dart';
import '../../core/network/ecode_client.dart';
import 'ecode_feed.dart';

/// 安卓 e码通：原生拉取 `ecode/api/qr-code` 并在本地渲染二维码。
///
/// 相比内嵌官方 H5（WebView 首屏约 5~11 秒），原生接口 + 本地 QR 渲染可在
/// 已有 Cookie 时亚秒级出码，并可按二维码有效期自动刷新。
class EcodePage extends StatefulWidget {
  const EcodePage({
    super.key,
    required this.session,
    this.active = true,
    this.feed,
  });

  final AuthSession session;
  final EcodeFeed? feed;

  /// 当前是否处于可见的 e码通 tab。后台预热时 active=false：
  /// 仍会尝试加载一次二维码，但失败不重试、不弹「需要重新登录」，
  /// 避免在首页/余额中心等其它页面打扰用户。
  final bool active;

  @override
  State<EcodePage> createState() => _EcodePageState();
}

class _EcodePageState extends State<EcodePage> with WidgetsBindingObserver {
  late final _feed =
      widget.feed ??
      EcodeFeed(widget.session, credentials: const SecureCredentialStore());

  EcodeQr? _qr;
  String? _error;
  bool _loading = true;
  bool _busy = false;
  Timer? _timer;
  Timer? _retryTimer;
  Timer? _expiryTimer;
  bool _refreshing = false;
  bool _foreground = true;
  int _failureCount = 0;
  bool _reloginPrompted = false;
  final Stopwatch _watch = Stopwatch()..start();
  bool _loggedReady = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _qr = _feed.current;
    _loading = _qr == null;
    unawaited(_refresh(initial: _loading, preferCached: true));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _retryTimer?.cancel();
    _expiryTimer?.cancel();
    if (widget.feed == null) _feed.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant EcodePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.active && widget.active) {
      // 从后台预热切到可见：立即刷新一次（旧码可能已过期）。
      _failureCount = 0;
      _reloginPrompted = false;
      if (mounted) {
        setState(() {
          _error = null;
          if (_qr == null) _loading = true;
        });
      }
      unawaited(_refresh(preferCached: true));
    } else if (oldWidget.active && !widget.active) {
      _timer?.cancel();
      _retryTimer?.cancel();
      _expiryTimer?.cancel();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      // 息屏/切后台时停止定时器，避免无效请求；恢复时立即补一次。
      _foreground = false;
      _timer?.cancel();
      _retryTimer?.cancel();
      _expiryTimer?.cancel();
      return;
    }
    if (state == AppLifecycleState.resumed) {
      _foreground = true;
      if (!widget.active) return;
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

  Future<void> _refresh({
    bool initial = false,
    bool manual = false,
    bool preferCached = false,
  }) async {
    if (_refreshing) return;
    _refreshing = true;
    _retryTimer?.cancel();
    if (initial && mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final qr = await _feed.fetch(preferCached: preferCached);
      if (!mounted) return;
      _failureCount = 0;
      _reloginPrompted = false;
      if (!_loggedReady) {
        _loggedReady = true;
        debugPrint(
          '[ecode-native] first ready in ${_watch.elapsedMilliseconds}ms',
        );
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
      if (widget.active && _foreground) _schedule();
    } catch (error) {
      if (!mounted) return;
      _failureCount++;
      debugPrint('[ecode-native] fetch failed ($_failureCount/3): $error');
      if (!widget.active || !_foreground) {
        // 后台预热失败：静默记录错误，不重试也不弹窗。
        setState(() {
          _loading = false;
          _busy = false;
          _error = _describeError(error);
        });
        return;
      }
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
    } finally {
      _refreshing = false;
    }
  }

  void _schedule() {
    _timer?.cancel();
    _expiryTimer?.cancel();
    final qr = _qr;
    if (qr == null) return;
    _expiryTimer = Timer(qr.invalidTime.difference(DateTime.now()), () {
      if (mounted && identical(qr, _qr)) setState(() => _qr = null);
    });
    // 按二维码生命周期的一半续码（上限 5 秒、下限 2 秒），确保展示的码始终在有效期内。
    final life = _qr?.lifetime.inMilliseconds ?? 10000;
    final waitMs = (life ~/ 2).clamp(2000, 5000);
    final remaining =
        _qr?.invalidTime.difference(DateTime.now()).inMilliseconds ?? waitMs;
    final delay = remaining > 0 ? waitMs.clamp(1, remaining) : waitMs;
    _timer = Timer(Duration(milliseconds: delay), () {
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
    if (_reloginPrompted || !mounted || !widget.active) return;
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
            Expanded(child: Center(child: _buildBody())),
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
              style: TextStyle(
                color: AppColors.muted,
                fontSize: 12.5,
                height: 1.5,
              ),
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
    if (_qr == null || !DateTime.now().isBefore(_qr!.invalidTime)) {
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
