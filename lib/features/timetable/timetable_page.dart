import 'package:flutter/material.dart';

import '../../app/theme/app_theme.dart';
import 'timetable_models.dart';
import 'yjs_timetable_page.dart';
import 'yjsxk_timetable_page.dart';

const _weekdays = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];
const _periodStarts = [
  '08:00',
  '08:55',
  '09:50',
  '10:45',
  '11:40',
  '13:30',
  '14:25',
  '15:20',
  '16:15',
  '17:10',
  '18:30',
  '19:25',
];
const _slotHeight = 54.0;
const _headerHeight = 46.0;
const _timeGutterWidth = 58.0;

class TimetablePage extends StatefulWidget {
  const TimetablePage({super.key, this.compact = false});

  final bool compact;

  @override
  State<TimetablePage> createState() => _TimetablePageState();
}

class _TimetablePageState extends State<TimetablePage> {
  TimetableData _data = SampleTimetable.data;
  int _week = 8;
  int _selectedDay = DateTime.now().weekday.clamp(1, 5);
  bool _weekView = true;

  List<CourseSession> get _weekSessions => _data.forWeek(_week);

  List<CourseSession> get _daySessions =>
      _data.forDay(_selectedDay, _week);

  void _changeWeek(int value) {
    setState(() => _week = value.clamp(1, _data.totalWeeks));
  }

  Future<void> _syncTimetable() async {
    final source = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.white,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '同步课表',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: AppColors.ink,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                '选择学校提供的课程表来源',
                style: TextStyle(fontSize: 11, color: AppColors.muted),
              ),
              const SizedBox(height: 12),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.school_rounded),
                title: const Text('研究生系统（新）'),
                subtitle: const Text('培养 — 学生课程表'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => Navigator.pop(context, 'yjs'),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.history_rounded),
                title: const Text('研究生选课系统（旧）'),
                subtitle: const Text('学生课表查询'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => Navigator.pop(context, 'yjsxk'),
              ),
            ],
          ),
        ),
      ),
    );
    if (source == null || !mounted) return;
    final imported = await Navigator.of(context).push<TimetableData>(
      MaterialPageRoute(
        builder: (_) => source == 'yjs'
            ? const YjsTimetablePage()
            : const YjsxkTimetablePage(),
      ),
    );
    if (imported == null || !mounted) return;
    setState(() {
      _data = imported;
      _week = _week.clamp(1, _data.totalWeeks);
      _selectedDay = _selectedDay.clamp(1, 7);
    });
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        widget.compact ? 20 : 36,
        widget.compact ? 8 : 32,
        widget.compact ? 20 : 36,
        32,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(context),
          const SizedBox(height: 22),
          _buildSummary(),
          const SizedBox(height: 20),
          if (widget.compact)
            _DayAgenda(
              week: _week,
              selectedDay: _selectedDay,
              sessions: _daySessions,
              onDayChanged: (day) => setState(() => _selectedDay = day),
            )
          else if (_weekView)
            _WeekGrid(sessions: _weekSessions)
          else
            _DayAgenda(
              week: _week,
              selectedDay: _selectedDay,
              sessions: _daySessions,
              onDayChanged: (day) => setState(() => _selectedDay = day),
            ),
          const SizedBox(height: 18),
          Text(
            _data.isSample ? '示例课表 · 数据接入教务系统后可自动同步' : '来自研究生教务系统 · 本地缓存',
            style: const TextStyle(color: AppColors.faint, fontSize: 10),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final title = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '我的课表',
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
            fontSize: widget.compact ? 24 : 28,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '${_data.termName} · 第 $_week 周',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: AppColors.muted, fontSize: 11),
        ),
      ],
    );

    final controls = Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        _WeekStepper(
          week: _week,
          totalWeeks: _data.totalWeeks,
          onChanged: _changeWeek,
        ),
        OutlinedButton.icon(
          onPressed: () => _changeWeek(8),
          icon: const Icon(Icons.today_outlined, size: 15),
          label: const Text('今天'),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.campusBlue,
            side: const BorderSide(color: AppColors.line),
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
            textStyle: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600),
          ),
        ),
        if (!widget.compact)
          _ViewToggle(
            weekView: _weekView,
            onChanged: (value) => setState(() => _weekView = value),
          ),
        if (!widget.compact)
          FilledButton.icon(
            onPressed: _syncTimetable,
            icon: const Icon(Icons.sync_rounded, size: 15),
            label: const Text('同步课表'),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              textStyle: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
      ],
    );

    if (widget.compact) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: title),
              IconButton(
                tooltip: '同步课表',
                onPressed: _syncTimetable,
                icon: const Icon(Icons.sync_rounded, size: 19),
              ),
            ],
          ),
          const SizedBox(height: 14),
          controls,
        ],
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(child: title),
        controls,
      ],
    );
  }

  Widget _buildSummary() {
    final sessions = _weekSessions;
    final periods = sessions.fold<int>(0, (sum, item) => sum + item.span);
    final next = sessions.isEmpty ? null : sessions.first;
    final cards = [
      _Metric(label: '本周课程', value: '${_data.courseCount} 门', icon: Icons.menu_book_outlined),
      _Metric(label: '本周课时', value: '$periods 节', icon: Icons.schedule_outlined),
      _Metric(
        label: '下一节',
        value: next == null ? '没有课' : '${_weekdays[next.day - 1]} ${_periodStarts[next.startPeriod - 1]}',
        icon: Icons.arrow_forward_outlined,
      ),
    ];

    if (widget.compact) {
      return Column(
        children: [
          for (var i = 0; i < cards.length; i++) ...[
            cards[i],
            if (i != cards.length - 1) const SizedBox(height: 8),
          ],
        ],
      );
    }

    return Row(
      children: [
        for (var i = 0; i < cards.length; i++) ...[
          Expanded(child: cards[i]),
          if (i != cards.length - 1) const SizedBox(width: 12),
        ],
      ],
    );
  }
}

class _WeekStepper extends StatelessWidget {
  const _WeekStepper({
    required this.week,
    required this.totalWeeks,
    required this.onChanged,
  });

  final int week;
  final int totalWeeks;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: AppColors.line),
        borderRadius: BorderRadius.circular(9),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: '上一周',
            onPressed: week <= 1 ? null : () => onChanged(week - 1),
            icon: const Icon(Icons.chevron_left_rounded, size: 18),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints.tightFor(width: 28, height: 28),
          ),
          SizedBox(
            width: 58,
            child: Text(
              '第 $week 周',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.ink,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          IconButton(
            tooltip: '下一周',
            onPressed: week >= totalWeeks ? null : () => onChanged(week + 1),
            icon: const Icon(Icons.chevron_right_rounded, size: 18),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints.tightFor(width: 28, height: 28),
          ),
        ],
      ),
    );
  }
}

class _ViewToggle extends StatelessWidget {
  const _ViewToggle({required this.weekView, required this.onChanged});

  final bool weekView;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 36,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: AppColors.canvas,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: AppColors.line),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _ToggleItem(
            label: '周视图',
            active: weekView,
            onTap: () => onChanged(true),
          ),
          _ToggleItem(
            label: '日视图',
            active: !weekView,
            onTap: () => onChanged(false),
          ),
        ],
      ),
    );
  }
}

class _ToggleItem extends StatelessWidget {
  const _ToggleItem({
    required this.label,
    required this.active,
    required this.onTap,
  });

  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: active ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          boxShadow: active
              ? const [BoxShadow(color: Color(0x120B4F9C), blurRadius: 4)]
              : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            color: active ? AppColors.campusBlue : AppColors.muted,
            fontSize: 10,
            fontWeight: active ? FontWeight.w600 : FontWeight.w500,
          ),
        ),
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value, required this.icon});

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 13),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: AppColors.line),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: AppColors.campusBlue.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 16, color: AppColors.campusBlue),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: AppColors.muted, fontSize: 9),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.ink,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
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

class _WeekGrid extends StatelessWidget {
  const _WeekGrid({required this.sessions});

  final List<CourseSession> sessions;

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now().weekday;
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: AppColors.line),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          SizedBox(
            height: _headerHeight,
            child: Row(
              children: [
                const SizedBox(width: _timeGutterWidth),
                for (var day = 1; day <= 7; day++)
                  Expanded(
                    child: Container(
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: day == today
                            ? AppColors.campusBlue.withValues(alpha: 0.045)
                            : null,
                        border: const Border(
                          left: BorderSide(color: AppColors.line),
                        ),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            _weekdays[day - 1],
                            style: TextStyle(
                              color: day == today
                                  ? AppColors.campusBlue
                                  : AppColors.ink,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            day == today ? '今天' : '',
                            style: const TextStyle(
                              color: AppColors.accent,
                              fontSize: 8,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
          SizedBox(
            height: 12 * _slotHeight,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: _timeGutterWidth,
                  child: Column(
                    children: [
                      for (var period = 1; period <= 12; period++)
                        SizedBox(
                          height: _slotHeight,
                          child: Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  '$period',
                                  style: const TextStyle(
                                    color: AppColors.ink,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  _periodStarts[period - 1],
                                  style: const TextStyle(
                                    color: AppColors.faint,
                                    fontSize: 8,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                for (var day = 1; day <= 7; day++)
                  Expanded(
                    child: _DayColumn(
                      day: day,
                      sessions: sessions.where((s) => s.day == day).toList(),
                      isToday: day == today,
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

class _DayColumn extends StatelessWidget {
  const _DayColumn({
    required this.day,
    required this.sessions,
    required this.isToday,
  });

  final int day;
  final List<CourseSession> sessions;
  final bool isToday;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: isToday ? AppColors.campusBlue.withValues(alpha: 0.025) : null,
        border: const Border(left: BorderSide(color: AppColors.line)),
      ),
      child: Stack(
        children: [
          for (var period = 1; period <= 12; period++)
            Positioned(
              top: (period - 1) * _slotHeight,
              left: 0,
              right: 0,
              child: Container(height: 1, color: AppColors.line.withValues(alpha: 0.7)),
            ),
          for (final session in sessions)
            Positioned(
              top: (session.startPeriod - 1) * _slotHeight + 3,
              left: 4,
              right: 4,
              height: session.span * _slotHeight - 6,
              child: _CourseCard(session: session),
            ),
        ],
      ),
    );
  }
}

class _CourseCard extends StatelessWidget {
  const _CourseCard({required this.session});

  final CourseSession session;

  static const _palette = [
    (Color(0xFFE8F1FB), Color(0xFF0B4F9C)),
    (Color(0xFFE6F7F4), Color(0xFF0F766E)),
    (Color(0xFFF3EDFF), Color(0xFF6D4AAE)),
    (Color(0xFFFFF2E4), Color(0xFFB45309)),
    (Color(0xFFFDEBEF), Color(0xFFB42353)),
  ];

  @override
  Widget build(BuildContext context) {
    final pair = _palette[session.name.hashCode.abs() % _palette.length];
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 7, 6, 5),
      decoration: BoxDecoration(
        color: pair.$1,
        borderRadius: BorderRadius.circular(7),
        border: Border(left: BorderSide(color: pair.$2, width: 3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            session.name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: pair.$2,
              fontSize: 11,
              height: 1.2,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            session.room,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: pair.$2.withValues(alpha: 0.78),
              fontSize: 8,
              height: 1.3,
            ),
          ),
          if (session.span >= 2)
            Text(
              session.teacher,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: pair.$2.withValues(alpha: 0.65),
                fontSize: 8,
                height: 1.3,
              ),
            ),
        ],
      ),
    );
  }
}

class _DayAgenda extends StatelessWidget {
  const _DayAgenda({
    required this.week,
    required this.selectedDay,
    required this.sessions,
    required this.onDayChanged,
  });

  final int week;
  final int selectedDay;
  final List<CourseSession> sessions;
  final ValueChanged<int> onDayChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (var day = 1; day <= 7; day++) ...[
                _DayChip(
                  label: _weekdays[day - 1],
                  active: day == selectedDay,
                  onTap: () => onDayChanged(day),
                ),
                if (day != 7) const SizedBox(width: 6),
              ],
            ],
          ),
        ),
        const SizedBox(height: 12),
        if (sessions.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 40),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border.all(color: AppColors.line),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Column(
              children: [
                Icon(Icons.coffee_outlined, color: AppColors.faint, size: 26),
                SizedBox(height: 8),
                Text('这一天没有课', style: TextStyle(color: AppColors.muted, fontSize: 11)),
              ],
            ),
          )
        else
          for (final session in sessions) ...[
            _AgendaCard(session: session),
            const SizedBox(height: 8),
          ],
        const SizedBox(height: 4),
        Text(
          '第 $week 周 · ${_weekdays[selectedDay - 1]}',
          style: const TextStyle(color: AppColors.faint, fontSize: 9),
        ),
      ],
    );
  }
}

class _DayChip extends StatelessWidget {
  const _DayChip({required this.label, required this.active, required this.onTap});

  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: active ? AppColors.campusBlue : Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: active ? AppColors.campusBlue : AppColors.line),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: active ? Colors.white : AppColors.muted,
            fontSize: 10,
            fontWeight: active ? FontWeight.w600 : FontWeight.w500,
          ),
        ),
      ),
    );
  }
}

class _AgendaCard extends StatelessWidget {
  const _AgendaCard({required this.session});

  final CourseSession session;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(13, 12, 13, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: AppColors.line),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 74,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _periodStarts[session.startPeriod - 1],
                  style: const TextStyle(
                    color: AppColors.campusBlue,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${session.startPeriod}-${session.endPeriod} 节',
                  style: const TextStyle(color: AppColors.faint, fontSize: 8),
                ),
              ],
            ),
          ),
          Container(width: 2, height: 38, color: AppColors.campusBlue.withValues(alpha: 0.28)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  session.name,
                  style: const TextStyle(
                    color: AppColors.ink,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${session.room} · ${session.teacher}',
                  style: const TextStyle(color: AppColors.muted, fontSize: 9),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
