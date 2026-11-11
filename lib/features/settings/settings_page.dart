import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/app_theme.dart';
import '../../core/settings/app_settings.dart';

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
            const _SectionLabel(
              icon: Icons.palette_outlined,
              label: '外观',
            ),
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
                    subtitle: '在系统托盘显示应用图标，鼠标悬浮可查看寝室用电。',
                    value: settings.showTrayIcon,
                    onChanged: (value) {
                      controller.setShowTrayIcon(value);
                      if (!value && settings.minimizeOnClose) {
                        controller.setMinimizeOnClose(false);
                      }
                    },
                    trailing: const _PlatformTag('Windows'),
                  ),
                  _SwitchRow(
                    icon: Icons.picture_in_picture_rounded,
                    title: '关闭窗口时最小化到托盘',
                    subtitle: settings.showTrayIcon
                        ? '点击关闭按钮时不退出应用，可从系统托盘恢复。'
                        : '托盘图标已隐藏，关闭窗口将直接退出应用。',
                    value: settings.minimizeOnClose && settings.showTrayIcon,
                    onChanged: settings.showTrayIcon
                        ? controller.setMinimizeOnClose
                        : null,
                    trailing: const _PlatformTag('Windows'),
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

/// 小节标签：图标 + 加宽字距的说明文字。
class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 12, color: AppColors.faint),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(
            color: AppColors.faint,
            fontSize: 10.5,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.2,
          ),
        ),
      ],
    );
  }
}

class _ThemeModeSelector extends StatelessWidget {
  const _ThemeModeSelector({required this.value, required this.onChanged});

  final ThemePreference value;
  final ValueChanged<ThemePreference> onChanged;

  @override
  Widget build(BuildContext context) {
    const options = <(ThemePreference, IconData, String, String)>[
      (ThemePreference.system, Icons.brightness_auto_outlined, '跟随系统', '随系统明暗'),
      (ThemePreference.light, Icons.light_mode_outlined, '浅色', '始终明亮'),
      (ThemePreference.dark, Icons.dark_mode_outlined, '深色', '始终深色'),
    ];

    return Row(
      children: [
        for (var index = 0; index < options.length; index++) ...[
          if (index > 0) const SizedBox(width: 10),
          Expanded(
            child: _ThemeOption(
              icon: options[index].$2,
              label: options[index].$3,
              hint: options[index].$4,
              selected: value == options[index].$1,
              onTap: () => onChanged(options[index].$1),
            ),
          ),
        ],
      ],
    );
  }
}

class _ThemeOption extends StatelessWidget {
  const _ThemeOption({
    required this.icon,
    required this.label,
    required this.hint,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String hint;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final accent = AppColors.campusBlue;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            color: selected
                ? accent.withValues(alpha: AppColors.isDark ? 0.18 : 0.08)
                : AppColors.canvas,
            borderRadius: BorderRadius.circular(13),
            border: Border.all(
              // 边框宽度保持不变，只让颜色参与动画：宽度变化会引起相邻文字
              // 重排抖动（外观切换时下方文字“颤抖”的原因）。
              color: selected ? accent : AppColors.line,
              width: 1.4,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    icon,
                    size: 18,
                    color: selected ? accent : AppColors.muted,
                  ),
                  const Spacer(),
                  AnimatedOpacity(
                    opacity: selected ? 1 : 0,
                    duration: const Duration(milliseconds: 160),
                    child: Icon(
                      Icons.check_circle_rounded,
                      size: 16,
                      color: accent,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                label,
                style: TextStyle(
                  color: selected ? AppColors.ink : AppColors.muted,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                hint,
                style: TextStyle(color: AppColors.faint, fontSize: 9.5),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SwitchRow extends StatelessWidget {
  const _SwitchRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
    this.trailing,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 17, color: AppColors.muted),
        const SizedBox(width: 11),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Flexible(
                    child: Text(
                      title,
                      style: TextStyle(
                        color: AppColors.ink,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (trailing != null) ...[
                    const SizedBox(width: 8),
                    trailing!,
                  ],
                ],
              ),
              const SizedBox(height: 3),
              Text(
                subtitle,
                style: TextStyle(
                  color: AppColors.muted,
                  fontSize: 10.5,
                  height: 1.5,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Switch.adaptive(
          value: value,
          onChanged: onChanged,
          activeTrackColor: AppColors.campusBlue,
        ),
      ],
    );
  }
}

class _PlatformTag extends StatelessWidget {
  const _PlatformTag(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppColors.line),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: AppColors.faint,
          fontSize: 8.5,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}

class _Footnote extends StatelessWidget {
  const _Footnote();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.lock_outline_rounded, size: 13, color: AppColors.faint),
        const SizedBox(width: 7),
        Flexible(
          child: Text(
            '设置仅保存在本机 data/settings.json，不会上传。',
            style: TextStyle(
              color: AppColors.faint,
              fontSize: 10,
              letterSpacing: 0.2,
            ),
          ),
        ),
      ],
    );
  }
}
