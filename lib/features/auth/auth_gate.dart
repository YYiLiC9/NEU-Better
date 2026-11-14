import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/app_theme.dart';
import '../../core/settings/app_settings.dart';
import '../home/home_page.dart';
import 'auth_controller.dart';
import 'login_page.dart';

class AuthGate extends ConsumerWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(authControllerProvider);
    // AppColors 是全局静态令牌，不经过 InheritedWidget；主题切换时显式重建
    // 路由内的页面，避免登录页 / 首页停留在旧配色。
    ref.watch(appSettingsProvider.select((settings) => settings.isDarkNow));
    final String key;
    final Widget child;
    if (state is AuthAuthenticated) {
      key = 'home';
      child = HomePage(session: state.session);
    } else if (state is AuthInitial) {
      key = 'launch';
      child = const _LaunchScreen();
    } else {
      key = 'login';
      child = const LoginPage();
    }
    // 登录进入主界面 / 退出登录回登录页 / 冷启动过场，都用同一套淡入 + 轻微
    // 缩放衔接，避免生硬硬切。AnimatedSwitcher 以状态种类为 key 触发动画。
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 340),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, animation) {
        final scale = Tween<double>(begin: 0.96, end: 1.0).animate(
          CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
        );
        return FadeTransition(
          opacity: animation,
          child: ScaleTransition(scale: scale, child: child),
        );
      },
      child: KeyedSubtree(key: ValueKey<String>(key), child: child),
    );
  }
}

class _LaunchScreen extends StatelessWidget {
  const _LaunchScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.canvas,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const _LaunchMark(),
            const SizedBox(height: 20),
            SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: AppColors.campusBlue,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LaunchMark extends StatelessWidget {
  const _LaunchMark();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 52,
      height: 52,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [AppColors.campusBlue, AppColors.campusBlueDeep],
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      alignment: Alignment.center,
      child: const Text(
        'N',
        style: TextStyle(
          color: Colors.white,
          fontSize: 25,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}
