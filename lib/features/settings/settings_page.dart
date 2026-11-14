import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/app_theme.dart';
import '../../core/settings/app_settings.dart';
import '../../core/update/update_flow.dart';
import '../timetable/course_override_store.dart';
import '../timetable/timetable_overlay.dart';
import '../timetable/timetable_store.dart';

part 'widgets/settings_widgets.dart';

/// 以居中小对话框形式打开设置（右上角有关闭按钮）。
///
/// 设置项很少（外观 + 窗口行为），整页跳转显得过重，因此用 Dialog 承载；
/// 点击遮罩或右上角 × 均可关闭。
Future<void> showSettingsDialog(BuildContext context) {
  final isDark = AppColors.isDark;
  return showDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierColor: isDark ? const Color(0x66000000) : const Color(0x2E14243B),
    builder: (_) => const _SettingsDialog(),
  );
}

class _SettingsDialog extends ConsumerWidget {
  const _SettingsDialog();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(appSettingsProvider);
    final controller = ref.read(appSettingsProvider.notifier);

    return ScrollbarTheme(
      data: ScrollbarThemeData(
        thickness: const WidgetStatePropertyAll(4),
        radius: const Radius.circular(2),
        thumbColor: WidgetStatePropertyAll(
          AppColors.muted.withValues(alpha: 0.45),
        ),
        trackColor: const WidgetStatePropertyAll(Colors.transparent),
      ),
      child: Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        width: 560,
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.82,
        ),
        padding: const EdgeInsets.fromLTRB(22, 18, 8, 16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.line),
          boxShadow: AppColors.isDark
              ? null
              : const [
                  BoxShadow(
                    color: Color(0x140B2E5C),
                    blurRadius: 32,
                    offset: Offset(0, 16),
                  ),
                ],
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.only(right: 14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
            // 头部：调色板徽标 + 标题 + 右上角关闭。
            Row(
              children: [
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: AppColors.campusBlue.withValues(
                      alpha: AppColors.isDark ? 0.22 : 0.10,
                    ),
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Icon(
                    Icons.settings_outlined,
                    size: 16,
                    color: AppColors.campusBlue,
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  '设置',
                  style: TextStyle(
                    color: AppColors.ink,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                Tooltip(
                  message: '关闭',
                  waitDuration: const Duration(milliseconds: 500),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: () => Navigator.of(context).pop(),
                    child: Padding(
                      padding: const EdgeInsets.all(5),
                      child: Icon(
                        Icons.close_rounded,
                        size: 17,
                        color: AppColors.muted,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const _SectionLabel(icon: Icons.palette_outlined, label: '主题'),
            const SizedBox(height: 10),
            _ThemeModeSelector(
              value: settings.themePreference,
              onChanged: controller.setThemePreference,
            ),
            const SizedBox(height: 18),
            const _SectionLabel(
              icon: Icons.calendar_today_outlined,
              label: '每周起始日',
            ),
            const SizedBox(height: 10),
            _WeekStartSelector(
              value: settings.weekStart,
              onChanged: controller.setWeekStart,
            ),
            const SizedBox(height: 18),
            const _CourseOverlaySection(),
            const SizedBox(height: 16),
            const _SectionLabel(
              icon: Icons.system_update_alt_rounded,
              label: '更新',
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.canvas,
                borderRadius: BorderRadius.circular(13),
                border: Border.all(color: AppColors.line),
              ),
              child: Column(
                children: [
                  _SwitchRow(
                    icon: Icons.autorenew_rounded,
                    title: '自动检查更新（来源 GitHub）',
                    value: settings.autoUpdate,
                    onChanged: controller.setAutoUpdate,
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      onPressed: () => checkForUpdates(context, manual: true),
                      icon: const Icon(Icons.refresh_rounded, size: 16),
                      label: const Text('检查更新'),
                      style: TextButton.styleFrom(
                        foregroundColor: AppColors.campusBlue,
                        textStyle: const TextStyle(fontSize: 12),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            if (Platform.isWindows) ...[
              const _SectionLabel(
                icon: Icons.power_settings_new_outlined,
                label: '启动',
              ),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: AppColors.canvas,
                  borderRadius: BorderRadius.circular(13),
                  border: Border.all(color: AppColors.line),
                ),
                child: _SwitchRow(
                  icon: Icons.login_rounded,
                  title: '开机自启动',
                  value: settings.autoStart,
                  onChanged: controller.setAutoStart,
                ),
              ),
              const SizedBox(height: 16),
            ],
            const _SectionLabel(
              icon: Icons.desktop_windows_outlined,
              label: '窗口',
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.canvas,
                borderRadius: BorderRadius.circular(13),
                border: Border.all(color: AppColors.line),
              ),
              child: Column(
                children: [
                  _SwitchRow(
                    icon: Icons.notifications_active_outlined,
                    title: '显示托盘栏图标',
                    value: settings.showTrayIcon,
                    onChanged: (value) {
                      controller.setShowTrayIcon(value);
                      if (!value && settings.minimizeOnClose) {
                        controller.setMinimizeOnClose(false);
                      }
                    },
                  ),
                  _SwitchRow(
                    icon: Icons.picture_in_picture_rounded,
                    title: '关闭窗口时最小化到托盘',
                    value: settings.minimizeOnClose && settings.showTrayIcon,
                    onChanged: settings.showTrayIcon
                        ? controller.setMinimizeOnClose
                        : null,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            const _Footnote(),
          ],
          ),
        ),
      ),
      ),
    );
  }
}

/// 手机端内嵌设置页：作为底部导航「设置」的第三项常驻主界面。
///
/// 与桌面弹窗 [_SettingsDialog] 的差异：
/// - 不含「窗口」相关设置（托盘图标/最小化到托盘是 Windows 桌面能力）；
/// - 保留「外观」，并在底部提供「退出登录」按钮（退出入口从顶部移到这里）。
class MobileSettingsPage extends ConsumerWidget {
  const MobileSettingsPage({super.key, required this.onLogout});

  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(appSettingsProvider);
    final controller = ref.read(appSettingsProvider.notifier);

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
      children: [
        Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: AppColors.campusBlue.withValues(
                  alpha: AppColors.isDark ? 0.22 : 0.10,
                ),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                Icons.settings_outlined,
                size: 17,
                color: AppColors.campusBlue,
              ),
            ),
            const SizedBox(width: 10),
            Text(
              '设置',
              style: TextStyle(
                color: AppColors.ink,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        const SizedBox(height: 22),
        const _SectionLabel(icon: Icons.palette_outlined, label: '主题'),
        const SizedBox(height: 10),
        _ThemeModeSelector(
          value: settings.themePreference,
          onChanged: controller.setThemePreference,
        ),
        const SizedBox(height: 20),
        const _SectionLabel(
          icon: Icons.calendar_today_outlined,
          label: '每周起始日',
        ),
        const SizedBox(height: 10),
        _WeekStartSelector(
          value: settings.weekStart,
          onChanged: controller.setWeekStart,
        ),
        const SizedBox(height: 20),
        const _CourseOverlaySection(),
        const SizedBox(height: 20),
        const _SectionLabel(
          icon: Icons.system_update_alt_rounded,
          label: '更新',
        ),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: AppColors.canvas,
            borderRadius: BorderRadius.circular(13),
            border: Border.all(color: AppColors.line),
          ),
          child: Column(
            children: [
              _SwitchRow(
                icon: Icons.autorenew_rounded,
                title: '自动检查更新（来源 GitHub）',
                value: settings.autoUpdate,
                onChanged: controller.setAutoUpdate,
              ),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: () => checkForUpdates(context, manual: true),
                  icon: const Icon(Icons.refresh_rounded, size: 16),
                  label: const Text('检查更新'),
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.campusBlue,
                    textStyle: const TextStyle(fontSize: 12),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        const _Footnote(),
        const SizedBox(height: 28),
        SizedBox(
          width: double.infinity,
          height: 46,
          child: OutlinedButton.icon(
            onPressed: onLogout,
            icon: const Icon(Icons.logout_rounded, size: 18),
            label: const Text('退出登录'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.danger,
              side: BorderSide(color: AppColors.danger.withValues(alpha: 0.4)),
              textStyle: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
