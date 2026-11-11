import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/app_theme.dart';
import '../../core/settings/app_settings.dart';

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

    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        width: 460,
        padding: const EdgeInsets.fromLTRB(22, 18, 22, 16),
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
                    Icons.palette_outlined,
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
            const _SectionLabel(icon: Icons.palette_outlined, label: '外观'),
            const SizedBox(height: 10),
            _ThemeModeSelector(
              value: settings.themePreference,
              onChanged: controller.setThemePreference,
            ),
            const SizedBox(height: 16),
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
    );
  }
}
