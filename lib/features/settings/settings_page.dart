import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/app_theme.dart';
import '../../core/settings/app_settings.dart';

/// 设置页：外观（明暗主题）与窗口行为。
/// 通过 `Navigator.push` 直接打开，无必填参数。
class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(appSettingsProvider);
    final controller = ref.read(appSettingsProvider.notifier);

    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        foregroundColor: AppColors.ink,
        elevation: 0,
        titleSpacing: 0,
        title: const Text(
          '设置',
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: AppColors.line),
        ),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 780),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(24, 30, 24, 36),
              children: [
                const _PageHeader(),
                const SizedBox(height: 24),
                _SectionCard(
                  icon: Icons.palette_outlined,
                  title: '外观',
                  subtitle: '选择界面的明暗风格。',
                  children: [
                    _ThemeModeSelector(
                      value: settings.themePreference,
                      onChanged: controller.setThemePreference,
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                _SectionCard(
                  icon: Icons.desktop_windows_outlined,
                  title: '窗口',
                  subtitle: '控制桌面窗口的关闭行为。',
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
                    const SizedBox(height: 6),
                    _SwitchRow(
                      icon: Icons.minimize_rounded,
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
                const SizedBox(height: 24),
                const _Footnote(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PageHeader extends StatelessWidget {
  const _PageHeader();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '设置',
          style: Theme.of(context).textTheme.displaySmall
              ?.copyWith(fontSize: 32, letterSpacing: -0.4),
        ),
        const SizedBox(height: 8),
        Text(
          '外观与窗口行为，仅保存在本机。',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 13),
        ),
      ],
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.children,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(22, 20, 22, 18),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.line),
        boxShadow: AppColors.isDark
            ? null
            : const [
                BoxShadow(
                  color: Color(0x0D0B2E5C),
                  blurRadius: 22,
                  offset: Offset(0, 10),
                ),
              ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: AppColors.campusBlue.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(icon, size: 16, color: AppColors.campusBlue),
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: AppColors.ink,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(color: AppColors.muted, fontSize: 10.5),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 18),
          ...children,
        ],
      ),
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
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
          decoration: BoxDecoration(
            color: selected
                ? accent.withValues(alpha: AppColors.isDark ? 0.18 : 0.08)
                : AppColors.canvas,
            borderRadius: BorderRadius.circular(13),
            border: Border.all(
              color: selected ? accent : AppColors.line,
              width: selected ? 1.4 : 1,
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
              const SizedBox(height: 12),
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
        Icon(icon, size: 18, color: AppColors.muted),
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
        color: AppColors.canvas,
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
