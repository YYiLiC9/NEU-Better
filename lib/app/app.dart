import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/platform/app_launch.dart';
import '../core/platform/windows_window.dart';
import '../core/settings/app_font.dart';
import '../core/settings/app_settings.dart';
import '../core/update/update_flow.dart';
import '../core/update/update_manager.dart';
import '../features/auth/auth_gate.dart';
import 'theme/app_theme.dart';
import 'theme/windows_font_library.dart';

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
    // 桌面端限制窗口最小尺寸（逻辑像素），保证首页固定像素网格至少 4 列、
    // 左栏 3 项正常；原生端按当前 DPI 缩放为物理像素。
    if (Platform.isWindows) {
      unawaited(WindowsWindow.setMinimumSize(780, 520));
    }
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

  bool _startupHideApplied = false;

  void _applyWindowSettings(AppSettingsController settings) {
    // 开机自启且开启“启动时最小化到托盘”时，首帧后隐藏主窗口到托盘一次。
    if (!_startupHideApplied &&
        Platform.isWindows &&
        launchedFromWindowsStartup &&
        settings.startMinimizedToTray &&
        settings.showTrayIcon) {
      _startupHideApplied = true;
      unawaited(WindowsWindow.setWindowVisible(false));
    }
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
    // 从「允许安装未知应用」设置页返回后，若已有待安装包则自动续装。
    unawaited(UpdateManager.instance.onAppResumed());
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
    final importedFont = settings.importedFont;
    String? windowsFontFamily;
    if (defaultTargetPlatform == TargetPlatform.windows) {
      windowsFontFamily = switch (settings.fontPreference) {
        AppFontPreference.system => AppTheme.windowsSystemFontFamily,
        AppFontPreference.imported when importedFont != null =>
          ref.watch(importedFontFamilyProvider(importedFont.id)).value,
        _ => null,
      };
    }
    AppColors.setDark(isDark);

    ref.listen<AppSettingsController>(
      appSettingsProvider,
      (_, next) => _applyWindowSettings(next),
    );

    return MaterialApp(
      navigatorKey: _rootNavigatorKey,
      title: 'NEU Better',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.forBrightness(
        Brightness.light,
        windowsFontFamily: windowsFontFamily,
      ),
      darkTheme: AppTheme.forBrightness(
        Brightness.dark,
        windowsFontFamily: windowsFontFamily,
      ),
      themeMode: isDark ? ThemeMode.dark : ThemeMode.light,
      themeAnimationDuration: const Duration(milliseconds: 200),
      themeAnimationCurve: Curves.easeOutCubic,
      builder: (context, child) {
        final scale = settings.fontSizePreference.scale;
        if (Theme.of(context).platform != TargetPlatform.windows ||
            scale == 1) {
          return child!;
        }
        final media = MediaQuery.of(context);
        return MediaQuery(
          data: media.copyWith(
            textScaler: _AppTextScaler(media.textScaler, scale),
          ),
          child: child!,
        );
      },
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

final class _AppTextScaler extends TextScaler {
  const _AppTextScaler(this.systemScaler, this.multiplier);

  final TextScaler systemScaler;
  final double multiplier;

  @override
  double scale(double fontSize) => systemScaler.scale(fontSize) * multiplier;

  @override
  double get textScaleFactor => scale(14) / 14;

  @override
  bool operator ==(Object other) =>
      other is _AppTextScaler &&
      systemScaler == other.systemScaler &&
      multiplier == other.multiplier;

  @override
  int get hashCode => Object.hash(systemScaler, multiplier);
}
