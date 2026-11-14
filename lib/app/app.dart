import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/platform/windows_window.dart';
import '../core/settings/app_settings.dart';
import '../core/update/update_flow.dart';
import '../core/update/update_manager.dart';
import '../features/auth/auth_gate.dart';
import 'theme/app_theme.dart';

/// 根导航 key：供启动时的自动更新检查在没有 BuildContext 的情况下弹窗。
final GlobalKey<NavigatorState> _rootNavigatorKey = GlobalKey<NavigatorState>();

class NeuBetterApp extends ConsumerStatefulWidget {
  const NeuBetterApp({super.key});

  @override
  ConsumerState<NeuBetterApp> createState() => _NeuBetterAppState();
}

class _NeuBetterAppState extends ConsumerState<NeuBetterApp>
    with WidgetsBindingObserver {
  final UpdateManager _updates = UpdateManager.instance;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _updates.addListener(_onUpdateChanged);
    final controller = ref.read(appSettingsProvider.notifier);
    controller.updatePlatformBrightness(
      WidgetsBinding.instance.platformDispatcher.platformBrightness,
    );
    _applyWindowSettings(ref.read(appSettingsProvider));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (!ref.read(appSettingsProvider).autoUpdate) return;
      unawaited(_bootstrapUpdate());
    });
  }

  /// 启动时自动检查：若有更新，弹「发现新版本」；若安装包已下载完成，直接提示安装。
  Future<void> _bootstrapUpdate() async {
    final ctx = _rootNavigatorKey.currentContext;
    if (ctx == null) return;
    final info = await _updates.check();
    if (!mounted || info == null) return;
    final current = _rootNavigatorKey.currentContext;
    if (current == null || !current.mounted) return;
    if (_updates.readyFile != null) {
      _updates.promptedReady = true;
      await showUpdateReadyDialog(current);
    } else {
      await showUpdateAvailableDialog(current);
    }
  }

  /// 后台下载完成且在应用前台时弹「立即更新 / 下次重启更新」。
  void _onUpdateChanged() {
    if (!mounted) return;
    if (_updates.readyFile == null || _updates.downloading) return;
    if (_updates.promptedReady) return;
    if (WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) {
      return;
    }
    final ctx = _rootNavigatorKey.currentContext;
    if (ctx == null) return;
    _updates.promptedReady = true;
    unawaited(showUpdateReadyDialog(ctx));
  }

  void _applyWindowSettings(AppSettingsController settings) {
    unawaited(WindowsWindow.setTrayIconVisible(settings.showTrayIcon));
    unawaited(
      WindowsWindow.setCloseBehavior(
        minimizeToTaskbar: settings.minimizeOnClose && settings.showTrayIcon,
      ),
    );
  }

  @override
  void didChangePlatformBrightness() {
    ref
        .read(appSettingsProvider.notifier)
        .updatePlatformBrightness(
          WidgetsBinding.instance.platformDispatcher.platformBrightness,
        );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    if (_updates.readyFile == null || _updates.promptedReady) return;
    final ctx = _rootNavigatorKey.currentContext;
    if (ctx == null) return;
    _updates.promptedReady = true;
    unawaited(showUpdateReadyDialog(ctx));
  }

  @override
  void dispose() {
    _updates.removeListener(_onUpdateChanged);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(appSettingsProvider);
    final isDark = settings.isDarkNow;
    AppColors.setDark(isDark);

    ref.listen<AppSettingsController>(
      appSettingsProvider,
      (_, next) => _applyWindowSettings(next),
    );

    return MaterialApp(
      navigatorKey: _rootNavigatorKey,
      title: 'NEU Better',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: isDark ? ThemeMode.dark : ThemeMode.light,
      themeAnimationDuration: const Duration(milliseconds: 200),
      themeAnimationCurve: Curves.easeOutCubic,
      // 界面取色走 AppColors 静态令牌（不是 Theme.of），而大量子树以 const
      // 实例化——明暗切换时 Element 因 widget identical 被跳过，烘焙在
      // build 里的旧颜色不会刷新。用随明暗变化的 key 强制重挂载根子树，
      // 让所有静态取色重新求值。
      home: KeyedSubtree(
        key: ValueKey<String>('root-$isDark'),
        child: const AuthGate(),
      ),
    );
  }
}
