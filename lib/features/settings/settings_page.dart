import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/app_theme.dart';
import '../../app/theme/windows_font_library.dart';
import '../../core/settings/app_font.dart';
import '../../core/settings/app_settings.dart';
import '../../core/storage/account_scope.dart';
import '../../core/update/update_service.dart';
import '../../core/update/update_flow.dart';
import '../timetable/course_override_store.dart';
import '../notifications/notification_settings_page.dart';
import '../timetable/timetable_models.dart';
import '../timetable/timetable_overlay.dart';
import '../timetable/timetable_store.dart';

part 'widgets/settings_widgets.dart';
part 'widgets/font_settings.dart';

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
    const fontSizes = FontSizePreference.values;
    switch (_category) {
      case 0:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _SectionLabel(icon: Icons.palette_outlined, label: '主题'),
            const SizedBox(height: 10),
            const SizedBox(height: 10),
            _ThemeModeSelector(
              value: controller.themePreference,
              onChanged: controller.setThemePreference,
            ),
            if (Theme.of(context).platform == TargetPlatform.windows) ...[
              const SizedBox(height: 18),
              const _SectionLabel(
                icon: Icons.font_download_outlined,
                label: '界面字体',
              ),
              const SizedBox(height: 8),
              const _FontSettings(),
              const SizedBox(height: 18),
              const _SectionLabel(icon: Icons.format_size, label: '字体大小'),
              Row(
                children: [
                  const Text('小'),
                  Expanded(
                    child: Semantics(
                      label: '字体大小',
                      child: Slider(
                        value: controller.settings.fontSizePreference.index
                            .toDouble(),
                        max: (fontSizes.length - 1).toDouble(),
                        divisions: fontSizes.length - 1,
                        onChanged: (position) =>
                            controller.setFontSizePreference(
                              fontSizes[position.round()],
                            ),
                        semanticFormatterCallback: (position) {
                          final scale = fontSizes[position.round()].scale;
                          return '${(scale * 100).round()}%';
                        },
                      ),
                    ),
                  ),
                  const Text('大'),
                ],
              ),
            ],
            const SizedBox(height: 18),
          ],
        );
      case 1:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _SectionLabel(
              icon: Icons.calendar_today_outlined,
              label: '每周起始日',
            ),
            const SizedBox(height: 10),
            _WeekStartSelector(
              value: controller.weekStart,
              onChanged: controller.setWeekStart,
            ),
            const SizedBox(height: 24),
            const _CourseOverlaySection(),
          ],
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
            const NotificationSettingsContent(),
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
/// 手机端用顶部「大类标签」切换同类设置，和电脑端的两栏分类对应：
/// 外观 / 课表 / 通知 / 通用。每个分类下只显示该类的设置项。
class MobileSettingsPage extends ConsumerStatefulWidget {
  const MobileSettingsPage({super.key, required this.onLogout});

  final VoidCallback onLogout;

  @override
  ConsumerState<MobileSettingsPage> createState() => _MobileSettingsPageState();
}

class _MobileSettingsPageState extends ConsumerState<MobileSettingsPage> {
  int _category = 0;

  static const _tabs = <(IconData, String)>[
    (Icons.palette_outlined, '外观'),
    (Icons.calendar_today_outlined, '课表'),
    (Icons.notifications_active_outlined, '通知'),
    (Icons.settings_outlined, '通用'),
  ];

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(appSettingsProvider);
    final controller = ref.read(appSettingsProvider.notifier);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 10),
          child: Row(
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
        ),
        SizedBox(
          height: 44,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
            itemCount: _tabs.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (context, index) => _MobileSettingsTab(
              icon: _tabs[index].$1,
              label: _tabs[index].$2,
              selected: _category == index,
              onTap: () => setState(() => _category = index),
            ),
          ),
        ),
        Divider(height: 1, color: AppColors.line),
        Expanded(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 160),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeIn,
            layoutBuilder: (currentChild, previousChildren) => Stack(
              alignment: Alignment.topLeft,
              children: [...previousChildren, ?currentChild],
            ),
            child: ListView(
              key: ValueKey<int>(_category),
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
              children: _buildPane(settings, controller),
            ),
          ),
        ),
      ],
    );
  }

  List<Widget> _buildPane(
    AppSettingsController settings,
    AppSettingsController controller,
  ) {
    switch (_category) {
      case 0:
        return [
          _SettingsGroupCard(
            title: '主题',
            icon: Icons.palette_outlined,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: _ThemeModeSelector(
                value: settings.themePreference,
                onChanged: controller.setThemePreference,
              ),
            ),
          ),
        ];
      case 1:
        return [
          _SettingsGroupCard(
            title: '每周起始日',
            icon: Icons.calendar_today_outlined,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: _WeekStartSelector(
                value: settings.weekStart,
                onChanged: controller.setWeekStart,
              ),
            ),
          ),
          const SizedBox(height: 20),
          const _CourseOverlaySection(),
        ];
      case 2:
        return [
          _SettingsGroupCard(
            title: '系统通知',
            icon: Icons.notifications_active_outlined,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: const NotificationSettingsContent(),
            ),
          ),
        ];
      default:
        return [
          _SettingsGroupCard(
            title: '更新',
            icon: Icons.system_update_alt_rounded,
            child: Column(
              children: [
                _SwitchRow(
                  icon: Icons.autorenew_rounded,
                  title: '自动检查更新（来源 GitHub）',
                  value: settings.autoUpdate,
                  onChanged: controller.setAutoUpdate,
                ),
                Divider(height: 1, color: AppColors.line),
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
              onPressed: widget.onLogout,
              icon: const Icon(Icons.logout_rounded, size: 18),
              label: const Text('退出登录'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.danger,
                side: BorderSide(
                  color: AppColors.danger.withValues(alpha: 0.4),
                ),
                textStyle: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ];
    }
  }
}

class _MobileSettingsTab extends StatelessWidget {
  const _MobileSettingsTab({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final accent = AppColors.campusBlue;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
          decoration: BoxDecoration(
            color: selected
                ? accent.withValues(alpha: AppColors.isDark ? 0.22 : 0.09)
                : AppColors.surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected ? accent.withValues(alpha: 0.55) : AppColors.line,
            ),
          ),
          child: Row(
            children: [
              Icon(
                icon,
                size: 15,
                color: selected ? accent : AppColors.muted,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: selected ? accent : AppColors.muted,
                  fontSize: 12.5,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
