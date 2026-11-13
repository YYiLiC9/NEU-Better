part of '../settings_page.dart';

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
    required this.value,
    required this.onChanged,
  });

  final IconData icon;
  final String title;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 17, color: AppColors.muted),
        const SizedBox(width: 11),
        Expanded(
          child: Text(
            title,
            style: TextStyle(
              color: AppColors.ink,
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
            ),
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

class _WeekStartSelector extends StatelessWidget {
  const _WeekStartSelector({required this.value, required this.onChanged});

  final WeekStart value;
  final ValueChanged<WeekStart> onChanged;

  @override
  Widget build(BuildContext context) {
    const options = <(WeekStart, String)>[
      (WeekStart.monday, '周一'),
      (WeekStart.sunday, '周日'),
    ];
    final accent = AppColors.campusBlue;
    return Row(
      children: [
        for (var index = 0; index < options.length; index++) ...[
          if (index > 0) const SizedBox(width: 10),
          Expanded(
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                onTap: () => onChanged(options[index].$1),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  curve: Curves.easeOutCubic,
                  alignment: Alignment.center,
                  padding: const EdgeInsets.symmetric(vertical: 11),
                  decoration: BoxDecoration(
                    color: value == options[index].$1
                        ? accent.withValues(alpha: AppColors.isDark ? 0.18 : 0.08)
                        : AppColors.canvas,
                    borderRadius: BorderRadius.circular(11),
                    border: Border.all(
                      color: value == options[index].$1 ? accent : AppColors.line,
                      width: 1.4,
                    ),
                  ),
                  child: Text(
                    options[index].$2,
                    style: TextStyle(
                      color: value == options[index].$1
                          ? AppColors.ink
                          : AppColors.muted,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// 「课表修改」小节：显示本地覆盖层计数，并提供一键清除 / 清除孤立修改。
class _CourseOverlaySection extends StatefulWidget {
  const _CourseOverlaySection();

  @override
  State<_CourseOverlaySection> createState() => _CourseOverlaySectionState();
}

class _CourseOverlaySectionState extends State<_CourseOverlaySection> {
  int _added = 0;
  int _modified = 0;
  int _deleted = 0;
  int _orphans = 0;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<Set<String>> _officialKeys() async {
    final official = await const TimetableStore().read();
    final keys = <String>{};
    if (official != null) {
      for (final session in official.sessions) {
        keys.add(courseKey(session));
      }
    }
    return keys;
  }

  Future<void> _refresh() async {
    final overlay = await const CourseOverrideStore().read();
    final keys = await _officialKeys();
    var orphans = 0;
    for (final modification in overlay.modified) {
      if (!keys.contains(modification.targetKey)) orphans++;
    }
    for (final deletion in overlay.deleted) {
      if (!keys.contains(deletion.targetKey)) orphans++;
    }
    if (!mounted) return;
    setState(() {
      _added = overlay.added.length;
      _modified = overlay.modified.length;
      _deleted = overlay.deleted.length;
      _orphans = orphans;
      _loading = false;
    });
  }

  int get _total => _added + _modified + _deleted;

  Future<void> _clearAll() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('清除课表修改'),
        content: const Text(
          '将删除全部本地新增 / 修改 / 删除记录，官方课表不受影响；课程备注会保留。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('清除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await const CourseOverrideStore().clear();
    await _refresh();
  }

  Future<void> _clearOrphans() async {
    final overlay = await const CourseOverrideStore().read();
    final keys = await _officialKeys();
    final next = TimetableOverlay(
      added: overlay.added,
      modified: overlay.modified
          .where((m) => keys.contains(m.targetKey))
          .toList(),
      deleted: overlay.deleted
          .where((d) => keys.contains(d.targetKey))
          .toList(),
    );
    await const CourseOverrideStore().save(next);
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final summary = _loading
        ? '读取中…'
        : '本地修改 $_total 处（新增 $_added · 修改 $_modified · 删除 $_deleted）';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionLabel(icon: Icons.edit_note_rounded, label: '课表修改'),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
          decoration: BoxDecoration(
            color: AppColors.canvas,
            borderRadius: BorderRadius.circular(13),
            border: Border.all(color: AppColors.line),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                summary,
                style: TextStyle(
                  color: AppColors.ink,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '长按（手机）/ 右键（电脑）课表格子可新增课程；点开课程可编辑或删除。',
                style: TextStyle(color: AppColors.faint, fontSize: 10),
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  if (_orphans > 0)
                    TextButton.icon(
                      onPressed: _clearOrphans,
                      icon: const Icon(
                        Icons.cleaning_services_outlined,
                        size: 15,
                      ),
                      label: Text('清除孤立修改 ($_orphans)'),
                      style: TextButton.styleFrom(
                        foregroundColor: AppColors.muted,
                        textStyle: const TextStyle(fontSize: 11.5),
                      ),
                    ),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: _total == 0 ? null : _clearAll,
                    icon: const Icon(Icons.delete_sweep_outlined, size: 16),
                    label: const Text('一键清除课表修改'),
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.danger,
                      disabledForegroundColor: AppColors.faint,
                      textStyle: const TextStyle(fontSize: 11.5),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
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
