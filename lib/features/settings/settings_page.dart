import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/app_theme.dart';
import '../../core/settings/app_settings.dart';
import '../../core/update/update_service.dart';
import '../../core/update/update_flow.dart';
import '../timetable/course_override_store.dart';
import '../notifications/notification_settings_page.dart';
import '../timetable/timetable_models.dart';
import '../timetable/timetable_overlay.dart';
import '../timetable/timetable_store.dart';

part 'widgets/settings_widgets.dart';

/// 以居中小对话框形式打开设置（右上角有关闭按钮）。
Future<void> showSettingsDialog(BuildContext context) {
  final isDark = AppColors.isDark;
  return showDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierColor: isDark ? const Color(0x66000000) : const Color(0x2E14243B),
    builder: (_) => const _SettingsDialog(),
  );
}

/// 桌面设置：左侧分类 + 右侧内容的两栏小窗。
class _SettingsDialog extends ConsumerStatefulWidget {
  const _SettingsDialog();

  @override
  ConsumerState<_SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends ConsumerState<_SettingsDialog> {
  int _category = 0;

  static const _categories = <(IconData, String)>[
    (Icons.palette_outlined, '外观'),
    (Icons.calendar_month_outlined, '课表'),
    (Icons.notifications_active_outlined, '通知'),
    (Icons.settings_outlined, '通用'),
  ];

  @override
  Widget build(BuildContext context) {
    ref.watch(appSettingsProvider);
    final controller = ref.read(appSettingsProvider.notifier);

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () {
          if (Navigator.of(context).canPop()) {
            Navigator.of(context).pop();
          }
        },
      },
      child: Focus(
        autofocus: true,
        child: Dialog(
          backgroundColor: Colors.transparent,
          child: Container(
            width: 760,
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * 0.84,
            ),
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
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 固定头部
                Padding(
                  padding: const EdgeInsets.fromLTRB(22, 16, 12, 0),
                  child: Row(
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
                ),
                const SizedBox(height: 14),
                Divider(height: 1, color: AppColors.line),
                Flexible(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // 左：分类导航
                      SizedBox(
                        width: 168,
                        child: Column(
                          children: [
                            const SizedBox(height: 12),
                            Expanded(
                              child: ListView(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 6,
                                ),
                                children: [
                                  for (var i = 0; i < _categories.length; i++)
                                    _SettingsNavItem(
                                      icon: _categories[i].$1,
                                      label: _categories[i].$2,
                                      selected: _category == i,
                                      onTap: () => setState(() => _category = i),
                                    ),
                                ],
                              ),
                            ),
                            const Padding(
                              padding: EdgeInsets.fromLTRB(16, 8, 16, 16),
                              child: _Footnote(),
                            ),
                          ],
                        ),
                      ),
                      VerticalDivider(width: 1, color: AppColors.line),
                      // 右：当前分类内容
                      Expanded(
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 140),
                          switchInCurve: Curves.easeOutCubic,
                          switchOutCurve: Curves.easeIn,
                          // 默认 Stack 居中会让内容在视口内垂直居中；改为左上对齐，
                          // 让每个分类的内容都从顶部开始排。
                          layoutBuilder: (currentChild, previousChildren) =>
                              Stack(
                                alignment: Alignment.topLeft,
                                children: [...previousChildren, ?currentChild],
                              ),
                          child: SingleChildScrollView(
                            key: ValueKey<int>(_category),
                            padding: const EdgeInsets.fromLTRB(20, 18, 20, 22),
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 520),
                              child: _buildPane(controller),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPane(AppSettingsController controller) {
    switch (_category) {
      case 0:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _SectionLabel(icon: Icons.palette_outlined, label: '主题'),
            const SizedBox(height: 10),
            _ThemeModeSelector(
              value: controller.themePreference,
              onChanged: controller.setThemePreference,
            ),
            const SizedBox(height: 24),
            const _SectionLabel(
              icon: Icons.calendar_today_outlined,
              label: '每周起始日',
            ),
            const SizedBox(height: 10),
            _WeekStartSelector(
              value: controller.weekStart,
              onChanged: controller.setWeekStart,
            ),
          ],
        );
      case 1:
        return const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [_CourseOverlaySection()],
        );
      case 2:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _SectionLabel(
              icon: Icons.notifications_active_outlined,
              label: '系统通知',
            ),
            const SizedBox(height: 10),
            const _NotificationSettingsEntry(),
            const SizedBox(height: 10),
            Text(
              '可分别开关校园通知、寝室用电提醒、邮件与插件通知。',
              style: TextStyle(fontSize: 11, color: AppColors.faint, height: 1.5),
            ),
          ],
        );
      default:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SettingsGroupCard(
              title: '更新',
              icon: Icons.system_update_alt_rounded,
              child: Column(
                children: [
                  _SwitchRow(
                    icon: Icons.autorenew_rounded,
                    title: '自动检查更新（来源 GitHub）',
                    value: controller.autoUpdate,
                    onChanged: controller.setAutoUpdate,
                  ),
                  Divider(height: 1, color: AppColors.line),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(
                      children: [
                        Icon(
                          Icons.info_outline_rounded,
                          size: 15,
                          color: AppColors.muted,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '当前版本 v${UpdateService.currentVersion}',
                          style: TextStyle(
                            color: AppColors.muted,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const Spacer(),
                        TextButton.icon(
                          onPressed: () =>
                              checkForUpdates(context, manual: true),
                          icon: const Icon(Icons.refresh_rounded, size: 16),
                          label: const Text('检查更新'),
                          style: TextButton.styleFrom(
                            foregroundColor: AppColors.campusBlue,
                            textStyle: const TextStyle(fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            if (Platform.isWindows) ...[
              const SizedBox(height: 24),
              _SettingsGroupCard(
                title: '启动',
                icon: Icons.power_settings_new_outlined,
                child: Column(
                  children: [
                    _SwitchRow(
                      icon: Icons.login_rounded,
                      title: '开机自启动',
                      value: controller.autoStart,
                      onChanged: controller.setAutoStart,
                    ),
                    Divider(height: 1, color: AppColors.line),
                    _SwitchRow(
                      icon: Icons.minimize_rounded,
                      title: '开机启动时自动最小化到托盘',
                      value: controller.startMinimizedToTray &&
                          controller.autoStart,
                      onChanged: controller.autoStart
                          ? controller.setStartMinimizedToTray
                          : null,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              _SettingsGroupCard(
                title: '窗口',
                icon: Icons.desktop_windows_outlined,
                child: Column(
                  children: [
                    _SwitchRow(
                      icon: Icons.notifications_active_outlined,
                      title: '显示托盘栏图标',
                      value: controller.showTrayIcon,
                      onChanged: (value) {
                        controller.setShowTrayIcon(value);
                        if (!value && controller.minimizeOnClose) {
                          controller.setMinimizeOnClose(false);
                        }
                      },
                    ),
                    Divider(height: 1, color: AppColors.line),
                    _SwitchRow(
                      icon: Icons.picture_in_picture_rounded,
                      title: '关闭窗口时最小化到托盘',
                      value:
                          controller.minimizeOnClose && controller.showTrayIcon,
                      onChanged: controller.showTrayIcon
                          ? controller.setMinimizeOnClose
                          : null,
                    ),
                  ],
                ),
              ),
            ],
          ],
        );
    }
  }
}

/// 手机端内嵌设置页：作为底部导航「设置」的常驻主界面。
///
/// 与桌面弹窗 [_SettingsDialog] 的差异：
/// - 不含「窗口」相关设置（托盘图标/最小化到托盘是 Windows 桌面能力）；
/// - 保留「外观」，并在底部提供「退出登录」按钮。
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
          icon: Icons.notifications_active_outlined,
          label: '通知',
        ),
        const SizedBox(height: 10),
        const _NotificationSettingsEntry(),
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
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Icon(
                      Icons.info_outline_rounded,
                      size: 15,
                      color: AppColors.muted,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '当前版本 v${UpdateService.currentVersion}',
                      style: TextStyle(
                        color: AppColors.muted,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
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
