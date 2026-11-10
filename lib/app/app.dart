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
  Timer? _scheduleTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final controller = ref.read(appSettingsProvider.notifier);
    controller.updatePlatformBrightness(
      WidgetsBinding.instance.platformDispatcher.platformBrightness,
    );
    unawaited(
      WindowsWindow.setCloseBehavior(
        minimizeToTaskbar: ref.read(appSettingsProvider).minimizeOnClose,
      ),
    );
    // 定时主题按分钟粒度刷新，保证跨过设定时间点时自动切换。
    _scheduleTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (!mounted) return;
      ref.read(appSettingsProvider.notifier).refreshSchedule();
    });
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
    _scheduleTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(appSettingsProvider);
    final isDark = settings.isDarkNow;
    AppColors.setDark(isDark);

    ref.listen<bool>(
      appSettingsProvider.select((value) => value.minimizeOnClose),
      (_, next) {
        unawaited(WindowsWindow.setCloseBehavior(minimizeToTaskbar: next));
      },
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
