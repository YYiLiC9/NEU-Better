import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/platform/windows_window.dart';
import '../core/settings/app_settings.dart';
import '../features/auth/auth_gate.dart';
import 'theme/app_theme.dart';

class NeuBetterApp extends ConsumerStatefulWidget {
  const NeuBetterApp({super.key});

  @override
  ConsumerState<NeuBetterApp> createState() => _NeuBetterAppState();
}

class _NeuBetterAppState extends ConsumerState<NeuBetterApp>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final controller = ref.read(appSettingsProvider.notifier);
    controller.updatePlatformBrightness(
      WidgetsBinding.instance.platformDispatcher.platformBrightness,
    );
    _applyWindowSettings(ref.read(appSettingsProvider));
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
  void dispose() {
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
      title: 'NEU Better',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: isDark ? ThemeMode.dark : ThemeMode.light,
      themeAnimationDuration: const Duration(milliseconds: 200),
      themeAnimationCurve: Curves.easeOutCubic,
      home: const AuthGate(),
    );
  }
}
