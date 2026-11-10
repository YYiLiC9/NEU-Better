import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/theme/app_theme.dart';
import 'timetable_models.dart';
import 'timetable_store.dart';
import 'yjs_timetable_page.dart';

const _weekdays = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];
const _slotHeight = 54.0;
const _headerHeight = 52.0;
const _timeGutterWidth = 58.0;

String _dateLabel(DateTime date) =>
    '${date.month}/${date.day}';

class TimetablePage extends StatefulWidget {
  const TimetablePage({super.key, this.compact = false});

  final bool compact;

  @override
  State<TimetablePage> createState() => _TimetablePageState();
}

class _TimetablePageState extends State<TimetablePage> {
  TimetableData _data = SampleTimetable.data;
  int _week = SampleTimetable.data.weekFor(DateTime.now());
  int _selectedDay = DateTime.now().weekday.clamp(1, 7);
  int _direction = 1;
  bool _weekView = true;
  int _lastNowMinute = DateTime.now().hour * 60 + DateTime.now().minute;
  Timer? _minuteTimer;

  @override
  void initState() {
    super.initState();
    _loadCachedTimetable();
    // "当前时间线"是信息不是装饰：每半分钟检查一次，只在跨过整分时重建。
    _minuteTimer = Timer.periodic(const Duration(milliseconds: 15000), (_) {
      final now = DateTime.now();
      final minute = now.hour * 60 + now.minute;
      if (minute != _lastNowMinute && mounted) {
        setState(() => _lastNowMinute = minute);
      }
    });
  }

  @override
  void dispose() {
    _minuteTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadCachedTimetable() async {
    final cached = await const TimetableStore().read();
    if (!mounted || cached == null || !_data.isSample) return;
    setState(() {
      _data = cached;
      _week = cached.weekFor(DateTime.now());
      _selectedDay = _selectedDay.clamp(1, 7);
    });
  }

  int get _nowWeek => _data.weekFor(DateTime.now());

  /// 「下一节」：当前周里今天还没开始、或本周后续、或下周第一节课。
  /// 第二个值是前缀（下周的课加「下」字）。
  (CourseSession, String)? get _nextSession {
    final sessions = _weekSessions;
    if (sessions.isEmpty) return null;
    if (_week != _nowWeek) {
      final sorted = [...sessions]..sort(_sessionOrder);
      return (sorted.first, '');
    }
    final minutesNow = DateTime.now().hour * 60 + DateTime.now().minute;
    final sorted = [...sessions]..sort(_sessionOrder);
    for (final session in sorted.where((s) => s.day == DateTime.now().weekday)) {
      if (PeriodTimes.startMinutes(session.startPeriod) > minutesNow) {
        return (session, '');
      }
    }
    for (final session in sorted) {
      if (session.day > DateTime.now().weekday) return (session, '');
    }
    final nextWeek = _data.forWeek(_week + 1);
    if (nextWeek.isEmpty) return null;
    final sortedNext = [...nextWeek]..sort(_sessionOrder);
    return (sortedNext.first, '下');
  }

  static int _sessionOrder(CourseSession a, CourseSession b) {
    final byDay = a.day.compareTo(b.day);
    if (byDay != 0) return byDay;
    return a.startPeriod.compareTo(b.startPeriod);
  }

  List<CourseSession> get _weekSessions => _data.forWeek(_week);

  List<ExamEntry> get _weekExams => _data.examsForWeek(_week);

  List<CourseSession> get _daySessions =>
      _data.forDay(_selectedDay, _week);

  List<ExamEntry> get _dayExams {
    final start = _weekStart;
    if (start == null) return const [];
    return _data.examsOn(start.add(Duration(days: _selectedDay - 1)));
  }

  /// Monday of the displayed week, or null when the term start is unknown.
  ///
  /// 旧版缓存没有 termStartDate：用 currentWeek + 本周一兜底推导
  /// （与同步时 welcomeWords 的推导一致，重新同步即可校正）。
  DateTime? get _weekStart {
    final start =
        _data.termStartDate ?? _inferTermStartFromCurrentWeek();
    if (start == null) return null;
    return TimetableData.mondayOf(start).add(Duration(days: (_week - 1) * 7));
  }

  DateTime? _inferTermStartFromCurrentWeek() {
    final week = _data.currentWeek;
    if (week <= 0 || week > 40) return null;
    return TimetableData.mondayOf(DateTime.now())
        .subtract(Duration(days: (week - 1) * 7));
  }

  void _changeWeek(int value) {
    final next = value.clamp(1, _data.totalWeeks);
    if (next == _week) return;
    setState(() {
      _direction = next > _week ? 1 : -1;
      _week = next;
    });
  }

  void _onWeekDrag(DragEndDetails details) {
    final velocity = details.primaryVelocity ?? 0;
    if (velocity < -120) {
      _changeWeek(_week + 1);
    } else if (velocity > 120) {
      _changeWeek(_week - 1);
    }
  }

  Future<void> _syncTimetable() async {
    final imported = await Navigator.of(context).push<TimetableData>(
      MaterialPageRoute(builder: (_) => const YjsTimetablePage()),
    );
    if (imported == null || !mounted) return;
    await const TimetableStore().save(imported);
    if (!mounted) return;
    setState(() {
      _data = imported;
      _week = imported.weekFor(DateTime.now());
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
              weekStart: _weekStart,
              selectedDay: _selectedDay,
              sessions: _daySessions,
              exams: _dayExams,
              onDayChanged: (day) => setState(() => _selectedDay = day),
            )
          else if (_weekView)
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 280),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              layoutBuilder: (currentChild, previousChildren) => Stack(
                alignment: Alignment.topLeft,
                children: [
                  ...previousChildren,
                  ?currentChild,
                ],
              ),
              transitionBuilder: (child, animation) {
                final incoming = child.key == ValueKey(_week);
                return SlideTransition(
                  position: Tween<Offset>(
                    begin: Offset(
                      incoming ? _direction * 0.14 : -_direction * 0.14,
                      0,
                    ),
                    end: Offset.zero,
                  ).animate(animation),
                  child: child,
                );
              },
              child: _WeekGrid(
                key: ValueKey(_week),
                weekStart: _weekStart,
                sessions: _weekSessions,
                exams: _weekExams,
                today: _isThisWeekToday(),
                onWeekDrag: _onWeekDrag,
              ),
            )
          else
            _DayAgenda(
              week: _week,
              weekStart: _weekStart,
              selectedDay: _selectedDay,
              sessions: _daySessions,
              exams: _dayExams,
              onDayChanged: (day) => setState(() => _selectedDay = day),
            ),
          const SizedBox(height: 18),
          Text(
            _data.isSample
                ? '示例课表 · 数据接入教务系统后可自动同步'
                : '来自研究生教务系统 · 本地缓存',
            style: const TextStyle(color: AppColors.faint, fontSize: 10),
          ),
        ],
      ),
    );
  }

  /// The today highlight only applies to the week that actually contains
  /// today; browsing another week must not highlight a column.
  bool _isThisWeekToday() {
    final now = DateTime.now();
    final start = _weekStart;
    if (start == null) return false;
    final end = start.add(const Duration(days: 6));
    return !now.isBefore(start) && !now.isAfter(end);
  }

  Widget _buildHeader(BuildContext context) {
    final range = _weekStart == null
        ? ''
        : '${_dateLabel(_weekStart!)}–${_dateLabel(_weekStart!.add(const Duration(days: 6)))}';
    final title = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '我的课表',
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
            fontSize: widget.compact ? 21 : 24,
            height: 1.2,
            letterSpacing: -0.3,
          ),
        ),
        const SizedBox(height: 5),
        Text(
          '${_data.termName} · 第 $_week 周${range.isEmpty ? '' : ' · $range'}',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: AppColors.muted,
            fontSize: 11,
            fontFeatures: [FontFeature.tabularFigures()],
          ),
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
          onPressed: () => _changeWeek(_nowWeek),
          icon: const Icon(Icons.today_outlined, size: 15),
          label: const Text('今天'),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.ink,
            side: const BorderSide(color: AppColors.line),
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
            minimumSize: const Size(0, 36),
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
              minimumSize: const Size(0, 36),
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
    final next = _nextSession;
    final courseCount = sessions.map((s) => s.id).toSet().length;
    final items = [
      ('$courseCount', '门课程'),
      ('$periods', '节课时'),
      (
        next == null
            ? '没有课'
            : '${next.$2}${_weekdays[next.$1.day - 1]} '
                '${PeriodTimes.startLabel(next.$1.startPeriod)}',
        '下一节',
      ),
    ];

    // 单条摘要带替代三张同质卡片：数字是内容，卡片不是。
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: AppColors.line),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          for (var i = 0; i < items.length; i++) ...[
            if (i != 0)
              Container(
                width: 1,
                height: 26,
                margin: const EdgeInsets.symmetric(horizontal: 16),
                color: AppColors.line,
              ),
            Expanded(
              child: RichText(
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                text: TextSpan(
                  children: [
                    TextSpan(
                      text: items[i].$1,
                      style: const TextStyle(
                        color: AppColors.ink,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                    const TextSpan(
                      text: ' ',
                      style: TextStyle(fontSize: 12),
                    ),
                    TextSpan(
                      text: items[i].$2,
                      style: const TextStyle(
                        color: AppColors.muted,
                        fontSize: 11,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
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
          border: Border.all(color: active ? AppColors.line : Colors.transparent),
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

class _WeekGrid extends StatelessWidget {
  const _WeekGrid({
    super.key,
    required this.weekStart,
    required this.sessions,
    required this.exams,
    required this.today,
    required this.onWeekDrag,
  });

  final DateTime? weekStart;
  final List<CourseSession> sessions;
  final List<ExamEntry> exams;
  final bool today;

  /// Horizontal swipe on the grid switches weeks; the state owns the
  /// direction bookkeeping for the slide transition.
  final ValueChanged<DragEndDetails> onWeekDrag;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: AppColors.line),
        borderRadius: BorderRadius.circular(10),
      ),
      child: GestureDetector(
        behavior: HitTestBehavior.deferToChild,
        onHorizontalDragEnd: onWeekDrag,
        child: Column(
          children: [
            SizedBox(
              height: _headerHeight,
              child: Row(
                children: [
                  const SizedBox(width: _timeGutterWidth),
                  for (var day = 1; day <= 7; day++)
                    Expanded(
                      child: _DayHeader(
                        label: _weekdays[day - 1],
                        date: weekStart?.add(Duration(days: day - 1)),
                        isToday: today && day == now.weekday,
                      ),
                    ),
                ],
              ),
            ),
            SizedBox(
              height: PeriodTimes.periodsPerDay * _slotHeight,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: _timeGutterWidth,
                    child: Column(
                      children: [
                        for (var period = 1;
                            period <= PeriodTimes.periodsPerDay;
                            period++)
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
                                    PeriodTimes.startLabel(period),
                                    style: const TextStyle(
                                      color: AppColors.faint,
                                      fontSize: 8,
                                      height: 1.2,
                                      fontFeatures: [
                                        FontFeature.tabularFigures(),
                                      ],
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
                        exams: exams
                            .where(
                              (e) =>
                                  weekStart != null &&
                                  _sameDay(
                                    e.date,
                                    weekStart!.add(Duration(days: day - 1)),
                                  ),
                            )
                            .toList(),
                        isToday: today && day == now.weekday,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}

class _DayHeader extends StatelessWidget {
  const _DayHeader({
    required this.label,
    required this.date,
    required this.isToday,
  });

  final String label;
  final DateTime? date;
  final bool isToday;

  @override
  Widget build(BuildContext context) {
    return Container(
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        border: Border(left: BorderSide(color: AppColors.line)),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (isToday)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
              decoration: BoxDecoration(
                color: AppColors.campusBlue,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            )
          else
            Text(
              label,
              style: const TextStyle(
                color: AppColors.ink,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          const SizedBox(height: 3),
          if (date != null)
            Text(
              isToday ? '今天 ${_dateLabel(date!)}' : _dateLabel(date!),
              style: TextStyle(
                color: isToday ? AppColors.campusBlue : AppColors.faint,
                fontSize: 8,
                height: 1.2,
                fontWeight: isToday ? FontWeight.w600 : FontWeight.w400,
                fontFeatures: const [FontFeature.tabularFigures()],
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
    required this.exams,
    required this.isToday,
  });

  final int day;
  final List<CourseSession> sessions;
  final List<ExamEntry> exams;
  final bool isToday;

  @override
  Widget build(BuildContext context) {
    final gridHeight = PeriodTimes.periodsPerDay * _slotHeight;
    final now = DateTime.now();
    final nowMinutes = now.hour * 60 + now.minute;
    final showNowLine =
        isToday &&
        nowMinutes >= PeriodTimes.firstStartMinutes &&
        nowMinutes <=
            PeriodTimes.firstStartMinutes +
                PeriodTimes.periodMinutes * PeriodTimes.periodsPerDay;
    return Container(
      decoration: BoxDecoration(
        color: isToday ? AppColors.campusBlue.withValues(alpha: 0.03) : null,
        border: Border(
          left: BorderSide(
            width: isToday ? 2 : 1,
            color: isToday
                ? AppColors.campusBlue.withValues(alpha: 0.45)
                : AppColors.line,
          ),
        ),
      ),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          for (var period = 1; period <= PeriodTimes.periodsPerDay; period++)
            Positioned(
              top: (period - 1) * _slotHeight,
              left: 0,
              right: 0,
              child: Container(height: 1, color: AppColors.line.withValues(alpha: 0.7)),
            ),
          if (showNowLine)
            Positioned(
              top: PeriodTimes.slotOffset(nowMinutes) * _slotHeight - 1,
              left: 0,
              right: 0,
              height: 2,
              child: Container(color: AppColors.nowRed),
            ),
          if (showNowLine)
            Positioned(
              left: -3,
              top: PeriodTimes.slotOffset(nowMinutes) * _slotHeight - 3,
              width: 8,
              height: 8,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: AppColors.nowRed,
                  shape: BoxShape.circle,
                ),
              ),
            ),
          for (final session in sessions)
            Positioned(
              top: (session.startPeriod - 1) * _slotHeight + 3,
              left: 4,
              right: 4,
              height: session.span * _slotHeight - 6,
              child: _CourseCard(session: session),
            ),
          for (final exam in exams)
            _examPositioned(exam, gridHeight),
        ],
      ),
    );
  }

  Widget _examPositioned(ExamEntry exam, double gridHeight) {
    const cardHeight = 46.0;
    final start = PeriodTimes.parseTime(exam.startTime);
    var top = start == null
        ? 4.0
        : PeriodTimes.slotOffset(start) * _slotHeight + 3;
    if (top < 0) top = 4;
    if (top + cardHeight > gridHeight) top = gridHeight - cardHeight - 4;
    return Positioned(
      top: top,
      left: 4,
      right: 4,
      height: cardHeight,
      child: _ExamCard(exam: exam, compact: true),
    );
  }
}

class _CourseCard extends StatelessWidget {
  const _CourseCard({required this.session});

  final CourseSession session;

  @override
  Widget build(BuildContext context) {
    final (tint, inkColor) = AppColors.pigmentFor(session.name);
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 6, 6, 5),
      decoration: BoxDecoration(
        color: tint,
        borderRadius: BorderRadius.circular(8),
        border: Border(left: BorderSide(color: inkColor, width: 3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            session.name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: inkColor,
              fontSize: 11,
              height: 1.25,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            session.room,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: inkColor.withValues(alpha: 0.75),
              fontSize: 8,
              height: 1.3,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          if (session.span >= 2)
            Text(
              session.teacher,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: inkColor.withValues(alpha: 0.6),
                fontSize: 8,
                height: 1.3,
              ),
            ),
        ],
      ),
    );
  }
}

/// Exam cards share the 朱 (now-red) family: red in this app always means
/// "此刻/紧要" — exams and the current-time line, never decoration.
class _ExamColors {
  static const background = Color(0xFFFFF1EE);
  static const accent = AppColors.nowRed;
  static const soft = Color(0x2EC2402A);
}

class _ExamCard extends StatelessWidget {
  const _ExamCard({required this.exam, this.compact = false});

  final ExamEntry exam;
  final bool compact;

  String get _timeLabel {
    if (exam.startTime == null) return '';
    return exam.endTime == null
        ? exam.startTime!
        : '${exam.startTime}–${exam.endTime}';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(
        compact ? 7 : 13,
        compact ? 6 : 11,
        compact ? 6 : 13,
        compact ? 5 : 11,
      ),
      decoration: BoxDecoration(
        color: _ExamColors.background,
        borderRadius: BorderRadius.circular(compact ? 7 : 12),
        border: Border(
          left: BorderSide(color: _ExamColors.accent, width: 3),
          top: BorderSide(color: _ExamColors.soft),
          right: BorderSide(color: _ExamColors.soft),
          bottom: BorderSide(color: _ExamColors.soft),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.quiz_outlined,
            size: compact ? 11 : 14,
            color: _ExamColors.accent,
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  exam.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: _ExamColors.accent,
                    fontSize: compact ? 10 : 13,
                    height: 1.2,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (_timeLabel.isNotEmpty || exam.room.isNotEmpty)
                  Text(
                    [
                      if (_timeLabel.isNotEmpty) _timeLabel,
                      if (exam.room.isNotEmpty) exam.room,
                    ].join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: _ExamColors.accent.withValues(alpha: 0.75),
                      fontSize: compact ? 8 : 10,
                      height: 1.3,
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

class _DayAgenda extends StatelessWidget {
  const _DayAgenda({
    required this.week,
    required this.weekStart,
    required this.selectedDay,
    required this.sessions,
    required this.exams,
    required this.onDayChanged,
  });

  final int week;
  final DateTime? weekStart;
  final int selectedDay;
  final List<CourseSession> sessions;
  final List<ExamEntry> exams;
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
                  date: weekStart?.add(Duration(days: day - 1)),
                  active: day == selectedDay,
                  onTap: () => onDayChanged(day),
                ),
                if (day != 7) const SizedBox(width: 6),
              ],
            ],
          ),
        ),
        const SizedBox(height: 12),
        if (exams.isNotEmpty) ...[
          for (final exam in exams) ...[
            _ExamCard(exam: exam),
            const SizedBox(height: 8),
          ],
          const SizedBox(height: 4),
        ],
        if (sessions.isEmpty && exams.isEmpty)
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
                Text('这一天没有安排', style: TextStyle(color: AppColors.muted, fontSize: 11)),
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
  const _DayChip({
    required this.label,
    required this.date,
    required this.active,
    required this.onTap,
  });

  final String label;
  final DateTime? date;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: active ? AppColors.campusBlue : Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: active ? AppColors.campusBlue : AppColors.line),
        ),
        child: Column(
          children: [
            Text(
              label,
              style: TextStyle(
                color: active ? Colors.white : AppColors.muted,
                fontSize: 10,
                fontWeight: active ? FontWeight.w600 : FontWeight.w500,
              ),
            ),
            if (date != null)
              Text(
                _dateLabel(date!),
                style: TextStyle(
                  color: active
                      ? Colors.white.withValues(alpha: 0.8)
                      : AppColors.faint,
                  fontSize: 8,
                ),
              ),
          ],
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
    final (_, inkColor) = AppColors.pigmentFor(session.name);
    return Container(
      padding: const EdgeInsets.fromLTRB(13, 12, 13, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: AppColors.line),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 78,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  PeriodTimes.rangeLabel(session.startPeriod, session.endPeriod),
                  style: TextStyle(
                    color: inkColor,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    fontFeatures: const [FontFeature.tabularFigures()],
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
          Container(width: 2, height: 38, color: inkColor.withValues(alpha: 0.28)),
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
