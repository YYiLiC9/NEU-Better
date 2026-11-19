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
        const SizedBox(width: 8),
        Transform.scale(
          scale: 0.8,
          child: Switch.adaptive(
            value: value,
            onChanged: onChanged,
            activeTrackColor: AppColors.campusBlue,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
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
    // 课表页在别处改了本地覆盖层时，设置页常驻（IndexedStack）不会重建，
    // 这里监听通知，及时刷新计数，避免显示“0 处”的过期数据。
    courseOverridesChanged.addListener(_onOverridesChanged);
  }

  @override
  void dispose() {
    courseOverridesChanged.removeListener(_onOverridesChanged);
    super.dispose();
  }

  void _onOverridesChanged() {
    if (mounted) _refresh();
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

  Future<void> _showDetails() async {
    final overlay = await const CourseOverrideStore().read();
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (_) => _OverlayDetailsDialog(overlay: overlay),
    );
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
                  TextButton(
                    onPressed: _total == 0 ? null : _showDetails,
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.campusBlue,
                      disabledForegroundColor: AppColors.faint,
                      textStyle: const TextStyle(fontSize: 11.5),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 16,
                          height: 16,
                          child: Center(
                            child: Text(
                              '≡',
                              style: TextStyle(
                                fontSize: 18,
                                height: 1,
                                fontWeight: FontWeight.w700,
                                color: _total == 0
                                    ? AppColors.faint
                                    : AppColors.campusBlue,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        const Text('查看详情'),
                      ],
                    ),
                  ),
                  const SizedBox(width: 4),
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

/// 课表本地修改详情：列出新增 / 修改 / 删除的具体内容。
class _OverlayDetailsDialog extends StatelessWidget {
  const _OverlayDetailsDialog({required this.overlay});

  final TimetableOverlay overlay;

  static const _dayNames = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];

  static String _dayName(int day) =>
      (day >= 1 && day <= 7) ? _dayNames[day - 1] : '周?';

  static String _weeksText(Set<int> weeks) {
    final sorted = weeks.toList()..sort();
    if (sorted.isEmpty) return '无';
    final parts = <String>[];
    var start = sorted.first;
    var prev = sorted.first;
    for (var i = 1; i < sorted.length; i++) {
      final w = sorted[i];
      if (w == prev + 1) {
        prev = w;
        continue;
      }
      parts.add(start == prev ? '第$start周' : '第$start–$prev周');
      start = w;
      prev = w;
    }
    parts.add(start == prev ? '第$start周' : '第$start–$prev周');
    return parts.join('、');
  }

  /// targetKey = `name|day|startPeriod|endPeriod`
  static (String, int, int, int) _parseKey(String key) {
    final parts = key.split('|');
    final name = parts.isNotEmpty ? parts[0] : key;
    final day = parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0;
    final start = parts.length > 2 ? int.tryParse(parts[2]) ?? 0 : 0;
    final end = parts.length > 3 ? int.tryParse(parts[3]) ?? 0 : 0;
    return (name, day, start, end);
  }

  String _sessionLine(CourseSession s) {
    final room = s.room.trim();
    final teacher = s.teacher.trim();
    final extra = [
      if (room.isNotEmpty) room,
      if (teacher.isNotEmpty) teacher,
    ].join(' · ');
    return '${_dayName(s.day)} 第${s.startPeriod}–${s.endPeriod}节'
        '${extra.isEmpty ? '' : ' · $extra'}'
        '${_weeksText(s.weeks).isEmpty ? '' : ' · ${_weeksText(s.weeks)}'}';
  }

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[];
    if (overlay.added.isNotEmpty) {
      children.add(_group('新增课程', overlay.added.map((s) => _item(
            Icons.add_circle_outline_rounded,
            AppColors.campusBlue,
            s.name,
            _sessionLine(s),
          ))));
    }
    if (overlay.modified.isNotEmpty) {
      children.add(_group('修改课程', overlay.modified.map((m) {
        final (name, day, start, end) = _parseKey(m.targetKey);
        final scope = m.scope == 'all'
            ? '所有周'
            : (m.week == null ? '仅本周' : '仅第${m.week}周');
        return _item(
          Icons.edit_outlined,
          const Color(0xFFB26A00),
          name,
          '原：${_dayName(day)} 第$start–$end节（$scope）\n'
              '现：${_sessionLine(m.replacement)}',
        );
      })));
    }
    if (overlay.deleted.isNotEmpty) {
      children.add(_group('删除课程', overlay.deleted.map((d) {
        final (name, day, start, end) = _parseKey(d.targetKey);
        final scope = d.scope == 'all'
            ? '所有周'
            : (d.week == null ? '仅本周' : '仅第${d.week}周');
        return _item(
          Icons.remove_circle_outline_rounded,
          AppColors.danger,
          name,
          '${_dayName(day)} 第$start–$end节（$scope）',
        );
      })));
    }

    return AlertDialog(
      backgroundColor: AppColors.surface,
      title: const Text('课表修改详情'),
      content: SizedBox(
        width: 460,
        child: overlay.isEmpty
            ? const Text('暂无本地课表修改。')
            : ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 460),
                child: ListView(
                  shrinkWrap: true,
                  children: children,
                ),
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('关闭'),
        ),
      ],
    );
  }

  Widget _group(String title, Iterable<Widget> items) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 6, bottom: 6),
          child: Text(
            title,
            style: TextStyle(
              color: AppColors.muted,
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        ...items,
        const SizedBox(height: 4),
      ],
    );
  }

  Widget _item(IconData icon, Color color, String title, String detail) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      decoration: BoxDecoration(
        color: AppColors.canvas,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.line),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: AppColors.ink,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  detail,
                  style: TextStyle(
                    color: AppColors.muted,
                    fontSize: 11,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
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

/// 「通知」二级设置入口（桌面弹窗与手机内嵌共用）。
class _NotificationSettingsEntry extends StatelessWidget {
  const _NotificationSettingsEntry();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.canvas,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: AppColors.line),
      ),
      child: ListTile(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
        contentPadding: EdgeInsets.zero,
        leading: Icon(
          Icons.notifications_active_outlined,
          size: 20,
          color: AppColors.muted,
        ),
        title: Text(
          '通知',
          style: TextStyle(
            fontSize: 13.5,
            fontWeight: FontWeight.w600,
            color: AppColors.ink,
          ),
        ),
        subtitle: Text(
          '系统通知与来源开关',
          style: TextStyle(fontSize: 11, color: AppColors.muted),
        ),
        trailing: Icon(Icons.chevron_right_rounded, size: 20, color: AppColors.faint),
        onTap: () {
          if (Platform.isWindows) {
            showNotificationSettingsDialog(context);
          } else {
            Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const NotificationSettingsPage(),
              ),
            );
          }
        },
      ),
    );
  }
}

/// 桌面设置左侧分类项。
class _SettingsNavItem extends StatefulWidget {
  const _SettingsNavItem({
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
  State<_SettingsNavItem> createState() => _SettingsNavItemState();
}

class _SettingsNavItemState extends State<_SettingsNavItem> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final selected = widget.selected;
    final bg = selected
        ? AppColors.campusBlue.withValues(alpha: AppColors.isDark ? 0.20 : 0.10)
        : (_hover ? AppColors.line.withValues(alpha: 0.45) : Colors.transparent);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          margin: const EdgeInsets.only(bottom: 4),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              Icon(
                widget.icon,
                size: 18,
                color: selected ? AppColors.campusBlue : AppColors.muted,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  widget.label,
                  style: TextStyle(
                    color: selected ? AppColors.campusBlue : AppColors.ink,
                    fontSize: 12.5,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 设置分组卡：小标题 + 统一容器（canvas 底、14 圆角、1px 线）。
class _SettingsGroupCard extends StatelessWidget {
  const _SettingsGroupCard({
    required this.title,
    required this.icon,
    required this.child,
  });

  final String title;
  final IconData icon;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionLabel(icon: icon, label: title),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
          decoration: BoxDecoration(
            color: AppColors.canvas,
            borderRadius: BorderRadius.circular(13),
            border: Border.all(color: AppColors.line),
          ),
          child: child,
        ),
      ],
    );
  }
}
