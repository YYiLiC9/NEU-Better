import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/theme/app_theme.dart';
import 'timetable_models.dart';
import 'timetable_store.dart';
import 'yjs_timetable_page.dart';

const _weekdays = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];
const _headerHeight = 40.0;
const _timeGutterWidth = 64.0;
const _minSlotHeight = 34.0;
const _maxSlotHeight = 54.0;

/// 午休（第 4 节后）与晚休（第 8 节后）的视觉留白。格子本身按节次等分，
/// 这里把真实作息中的长间隔折成一条横条；22px 才能放下「午休/晚休」
/// 字样（12px 会裁字）。
const _breakGap = 22.0;

double _gridHeightFor(double slotHeight) =>
    PeriodTimes.periodsPerDay * slotHeight + 2 * _breakGap;

double _slotTopFor(double slotHeight, int period) {
  var top = (period - 1) * slotHeight;
  if (period > 4) top += _breakGap;
  if (period > 8) top += _breakGap;
  return top;
}

double _slotSpanHeightFor(double slotHeight, int startPeriod, int endPeriod) {
  var height = (endPeriod - startPeriod + 1) * slotHeight;
  if (startPeriod <= 4 && endPeriod >= 5) height += _breakGap;
  if (startPeriod <= 8 && endPeriod >= 9) height += _breakGap;
  return height;
}

String _dateLabel(DateTime date) => '${date.month}/${date.day}';

String _examTimeLabel(ExamEntry exam) {
  final start = exam.startTime;
  if (start == null || start.isEmpty) return '';
  final end = exam.endTime;
  if (end == null || end.isEmpty) return start;
  return '$start–$end';
}

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
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _loadCachedTimetable();
    timetableChanged.addListener(_onTimetableChanged);
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
    timetableChanged.removeListener(_onTimetableChanged);
    _minuteTimer?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  void _onTimetableChanged() {
    _loadCachedTimetable(force: true);
  }

  Future<void> _loadCachedTimetable({bool force = false}) async {
    final cached = await const TimetableStore().read();
    if (!mounted || cached == null) return;
    if (!force && !_data.isSample) return;
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
    for (final session in sorted.where(
      (s) => s.day == DateTime.now().weekday,
    )) {
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

  static int _examOrder(ExamEntry a, ExamEntry b) {
    final byDate = a.date.compareTo(b.date);
    if (byDate != 0) return byDate;
    final aStart = PeriodTimes.parseTime(a.startTime) ?? 0;
    final bStart = PeriodTimes.parseTime(b.startTime) ?? 0;
    return aStart.compareTo(bStart);
  }

  List<CourseSession> get _weekSessions => _data.forWeek(_week);

  /// All exams of one teaching week. The week is anchored on the same
  /// [_weekStartFor] as the grid header, so legacy caches without a stored
  /// term start still line up correctly.
  List<ExamEntry> _examsForWeek(int week) {
    final start = _weekStartFor(week);
    if (start == null) return const [];
    final end = start.add(const Duration(days: 7));
    return _data.exams
        .where((exam) => !exam.date.isBefore(start) && exam.date.isBefore(end))
        .toList()
      ..sort(_examOrder);
  }

  List<ExamEntry> get _allExams => [..._data.exams]..sort(_examOrder);

  List<CourseSession> get _daySessions => _data.forDay(_selectedDay, _week);

  List<ExamEntry> get _dayExams {
    final start = _weekStart;
    if (start == null) return const [];
    return (_data.examsOn(start.add(Duration(days: _selectedDay - 1))).toList()
      ..sort(_examOrder));
  }

  /// Monday of the displayed week, or null when the term start is unknown.
  ///
  /// 旧版缓存没有 termStartDate：用 currentWeek + 本周一兜底推导
  /// （与同步时 welcomeWords 的推导一致，重新同步即可校正）。
  DateTime? get _weekStart => _weekStartFor(_week);

  DateTime? _weekStartFor(int week) {
    final start = _data.termStartDate ?? _inferTermStartFromCurrentWeek();
    if (start == null) return null;
    return TimetableData.mondayOf(start).add(Duration(days: (week - 1) * 7));
  }

  bool _isWeekToday(int week) {
    final now = DateTime.now();
    final start = _weekStartFor(week);
    if (start == null) return false;
    final end = start.add(const Duration(days: 6));
    return !now.isBefore(start) && !now.isAfter(end);
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

  /// 回到今天：周视图回到当前教学周；日视图还要把选中的星期切回今天。
  void _goToday() {
    final todayWeek = _nowWeek;
    setState(() {
      if (todayWeek != _week) {
        _direction = todayWeek > _week ? 1 : -1;
        _week = todayWeek;
      }
      _selectedDay = DateTime.now().weekday.clamp(1, 7);
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
    return LayoutBuilder(
      builder: (context, constraints) {
        final viewportHeight =
            constraints.maxHeight.isFinite && constraints.maxHeight > 0
            ? constraints.maxHeight
            : 800.0;
        final slotHeight = _slotHeightFor(viewportHeight);
        return ScrollConfiguration(
          // The Material desktop default scrollbar is a thick grey bar that
          // fights the hairline system. Disable it and paint our own 4px rail.
          behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
          child: ScrollbarTheme(
            data: ScrollbarThemeData(
              thumbColor: WidgetStateProperty.resolveWith<Color?>((states) {
                final active =
                    states.contains(WidgetState.hovered) ||
                    states.contains(WidgetState.dragged);
                return (active ? AppColors.muted : AppColors.faint).withValues(
                  alpha: active ? 0.55 : 0.32,
                );
              }),
              trackColor: const WidgetStatePropertyAll(Colors.transparent),
            ),
            child: Scrollbar(
              controller: _scrollController,
              thickness: 4,
              radius: const Radius.circular(2),
              interactive: true,
              child: SingleChildScrollView(
                controller: _scrollController,
                padding: EdgeInsets.fromLTRB(
                  widget.compact ? 20 : 36,
                  widget.compact ? 8 : 20,
                  widget.compact ? 20 : 36,
                  widget.compact ? 24 : 12,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildHeader(context),
                    SizedBox(height: widget.compact ? 18 : 12),
                    _buildSummary(),
                    SizedBox(height: widget.compact ? 16 : 12),
                    if (_weekView)
                      _buildWeekView(slotHeight)
                    else
                      _buildDayAgenda(),
                    if (!widget.compact && _weekView) ...[
                      const SizedBox(height: 8),
                      _ExamScheduleSection(exams: _allExams),
                    ],
                    SizedBox(height: widget.compact ? 18 : 12),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildWeekView(double slotHeight) {
    final pager = _WeekPager(
      week: _week,
      direction: _direction,
      pageBuilder: (week) => _WeekGrid(
        weekStart: _weekStartFor(week),
        sessions: _data.forWeek(week),
        exams: _examsForWeek(week),
        today: _isWeekToday(week),
        onWeekDrag: _onWeekDrag,
        slotHeight: slotHeight,
      ),
    );
    if (!widget.compact) return pager;
    // 窄窗口也保留完整的周视图；宽度不够时允许横向滚动，
    // 而不是直接退化成单日列表。
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth < 620 ? 620.0 : constraints.maxWidth;
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SizedBox(width: width, child: pager),
        );
      },
    );
  }

  Widget _buildDayAgenda() {
    return SizedBox(
      width: double.infinity,
      child: _DayAgenda(
        week: _week,
        weekStart: _weekStart,
        selectedDay: _selectedDay,
        sessions: _daySessions,
        exams: _dayExams,
        onDayChanged: (day) => setState(() => _selectedDay = day),
      ),
    );
  }

  /// Fit all 12 periods into the default 1280x800 window: the grid itself
  /// gets whatever vertical budget is left after the page chrome, bounded so
  /// the cards stay legible and never become taller than the old design.
  double _slotHeightFor(double viewportHeight) {
    if (widget.compact) return _maxSlotHeight;
    // 330 是标题/摘要/间距、底部状态栏与考试安排标题的实测占用，
    // 让默认窗口里既能放下 12 节，也能完整看到下方考试列表的开头。
    const chrome = 330.0;
    final raw =
        (viewportHeight - chrome - _headerHeight - 2 * _breakGap) /
        PeriodTimes.periodsPerDay;
    return raw.clamp(_minSlotHeight, _maxSlotHeight).floorToDouble();
  }

  Widget _buildHeader(BuildContext context) {
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
          _data.termName,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
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
          onPressed: _goToday,
          icon: Icon(Icons.today_outlined, size: 15),
          label: Text('今天'),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.ink,
            side: BorderSide(color: AppColors.line),
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
            minimumSize: const Size(0, 36),
            textStyle: TextStyle(fontSize: 10, fontWeight: FontWeight.w600),
          ),
        ),
        _ViewToggle(
          weekView: _weekView,
          onChanged: (value) => setState(() => _weekView = value),
        ),
        if (!widget.compact)
          FilledButton.icon(
            onPressed: _syncTimetable,
            icon: Icon(Icons.sync_rounded, size: 15),
            label: Text('同步课表'),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              minimumSize: const Size(0, 36),
              textStyle: TextStyle(fontSize: 10, fontWeight: FontWeight.w600),
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
                icon: Icon(Icons.sync_rounded, size: 19),
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
    // 同一门课一周可能排多次（如周一、周五各一节），摘要按课程名去重。
    final courseCount = sessions.map((s) => s.name).toSet().length;
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
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.line),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          for (var i = 0; i < items.length; i++) ...[
            if (i != 0)
              Container(
                width: 1,
                height: 24,
                margin: const EdgeInsets.symmetric(horizontal: 14),
                color: AppColors.line,
              ),
            Expanded(
              child: Text.rich(
                // 数值与“门/节”使用同一字号，避免“门”落到更小的字号
                // 而显得像另一个字形（5 门课程要读得自然）。
                TextSpan(
                  children: [
                    TextSpan(
                      text: items[i].$1,
                      style: TextStyle(
                        color: AppColors.ink,
                        fontSize: 13,
                        height: 1.3,
                        fontWeight: FontWeight.w600,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                    TextSpan(
                      // 中文数量短语不加空格：5门课程、14节课时。
                      // 第三项是「周五 08:30 下一节」，保留一个空格断句。
                      text: i == 2 ? ' ${items[i].$2}' : items[i].$2,
                      style: TextStyle(
                        color: AppColors.muted,
                        fontSize: 13,
                        height: 1.3,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  ],
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
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
        color: AppColors.surface,
        border: Border.all(color: AppColors.line),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: '上一周',
            onPressed: week <= 1 ? null : () => onChanged(week - 1),
            icon: Icon(Icons.chevron_left_rounded, size: 18),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints.tightFor(width: 28, height: 28),
          ),
          SizedBox(
            width: 58,
            child: Text(
              '第 $week 周',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.ink,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          IconButton(
            tooltip: '下一周',
            onPressed: week >= totalWeeks ? null : () => onChanged(week + 1),
            icon: Icon(Icons.chevron_right_rounded, size: 18),
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
        borderRadius: BorderRadius.circular(8),
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
          color: active ? AppColors.surface : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: active ? AppColors.line : Colors.transparent,
          ),
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

/// One page of the week pager: the outgoing and incoming weeks are laid out
/// at full width and translated together, with a `ClipRect` + per-page
/// `RepaintBoundary` making absolutely sure no residue from the previous
/// week can paint outside the grid.
class _WeekPager extends StatefulWidget {
  const _WeekPager({
    required this.week,
    required this.direction,
    required this.pageBuilder,
  });

  final int week;
  final int direction;
  final Widget Function(int week) pageBuilder;

  @override
  State<_WeekPager> createState() => _WeekPagerState();
}

class _WeekPagerState extends State<_WeekPager>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 280),
  );
  late int _previousWeek = widget.week;
  late int _previousDirection = widget.direction;
  bool _animating = false;

  @override
  void initState() {
    super.initState();
    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed && mounted && _animating) {
        setState(() => _animating = false);
      }
    });
  }

  @override
  void didUpdateWidget(covariant _WeekPager oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.week != widget.week) {
      _previousWeek = oldWidget.week;
      _previousDirection = widget.direction;
      _animating = true;
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Build both pages exactly once per week change; only the transform is
    // recomputed on each animation tick, so the grids never rebuild per frame.
    final incomingPage = RepaintBoundary(
      key: ValueKey('week-${widget.week}'),
      child: widget.pageBuilder(widget.week),
    );
    final outgoingPage = _animating
        ? RepaintBoundary(
            key: ValueKey('week-$_previousWeek'),
            child: widget.pageBuilder(_previousWeek),
          )
        : null;
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        return ClipRect(
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, _) {
              if (!_animating || outgoingPage == null) return incomingPage;
              final t = Curves.easeOutCubic.transform(_controller.value);
              final outgoingShift = -_previousDirection * width * t;
              final incomingShift = _previousDirection > 0
                  ? width * (1 - t)
                  : -width * (1 - t);
              return Stack(
                alignment: Alignment.topLeft,
                clipBehavior: Clip.none,
                children: [
                  Transform.translate(
                    offset: Offset(outgoingShift, 0),
                    child: SizedBox(
                      width: width,
                      child: IgnorePointer(child: outgoingPage),
                    ),
                  ),
                  Transform.translate(
                    offset: Offset(incomingShift, 0),
                    child: SizedBox(width: width, child: incomingPage),
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }
}

class _WeekGrid extends StatelessWidget {
  const _WeekGrid({
    required this.weekStart,
    required this.sessions,
    required this.exams,
    required this.today,
    required this.onWeekDrag,
    required this.slotHeight,
  });

  final DateTime? weekStart;
  final List<CourseSession> sessions;
  final List<ExamEntry> exams;
  final bool today;
  final double slotHeight;

  /// Horizontal swipe on the grid switches weeks; the state owns the
  /// direction bookkeeping for the slide transition.
  final ValueChanged<DragEndDetails> onWeekDrag;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.line),
        borderRadius: BorderRadius.circular(8),
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
              height: _gridHeightFor(slotHeight),
              child: Stack(
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: _timeGutterWidth,
                        child: Column(
                          children: [
                            for (
                              var period = 1;
                              period <= PeriodTimes.periodsPerDay;
                              period++
                            ) ...[
                              SizedBox(
                                height: slotHeight,
                                child: Center(
                                  child: FittedBox(
                                    fit: BoxFit.scaleDown,
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Text(
                                          '$period',
                                          style: TextStyle(
                                            color: AppColors.ink,
                                            fontSize: 11,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          '${PeriodTimes.startLabel(period)}'
                                          '–${PeriodTimes.endLabel(period)}',
                                          style: TextStyle(
                                            color: AppColors.faint,
                                            fontSize: 8,
                                            height: 1.15,
                                            fontFeatures: [
                                              FontFeature.tabularFigures(),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                              if (period == 4 || period == 8)
                                const SizedBox(height: _breakGap),
                            ],
                          ],
                        ),
                      ),
                      for (var day = 1; day <= 7; day++)
                        Expanded(
                          child: _DayColumn(
                            day: day,
                            sessions: sessions
                                .where((s) => s.day == day)
                                .toList(),
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
                            slotHeight: slotHeight,
                          ),
                        ),
                    ],
                  ),
                  Positioned(
                    left: 0,
                    right: 0,
                    top: 4 * slotHeight,
                    height: _breakGap,
                    child: const _BreakBand(label: '午休'),
                  ),
                  Positioned(
                    left: 0,
                    right: 0,
                    top: 8 * slotHeight + _breakGap,
                    height: _breakGap,
                    child: const _BreakBand(label: '晚休'),
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

/// 午休 / 晚休横条：不透明底色覆盖整行，覆盖掉各天列的竖分隔线。
/// 底色取分隔线的半透明色叠在网格 surface 上，明暗两套主题下都与网格
/// 同色系（不直接用 canvas，避免暗黑模式下与格子底色脱节）。
class _BreakBand extends StatelessWidget {
  const _BreakBand({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    // 用与 surface 混合后的不透明底色，完整盖住各天列的分隔竖线，
    // 让午休/晚休在视觉上合并成一整行。
    final bandColor = Color.alphaBlend(
      AppColors.line.withValues(alpha: 0.22),
      AppColors.surface,
    );
    return Container(
      decoration: BoxDecoration(
        color: bandColor,
        border: Border.symmetric(
          horizontal: BorderSide(color: AppColors.line.withValues(alpha: 0.6)),
        ),
      ),
      alignment: Alignment.center,
      child: Text(
        label,
        style: TextStyle(
          color: AppColors.muted,
          fontSize: 9.5,
          fontWeight: FontWeight.w600,
          letterSpacing: 3,
        ),
      ),
    );
  }
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
      padding: const EdgeInsets.only(top: 8),
      decoration: BoxDecoration(
        border: Border(left: BorderSide(color: AppColors.line)),
      ),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.center,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (isToday)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.campusBlue,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  label,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              )
            else
              Text(
                label,
                style: TextStyle(
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
    required this.slotHeight,
  });

  final int day;
  final List<CourseSession> sessions;
  final List<ExamEntry> exams;
  final bool isToday;
  final double slotHeight;

  @override
  Widget build(BuildContext context) {
    final gridHeight = _gridHeightFor(slotHeight);
    return Container(
      decoration: BoxDecoration(
        color: isToday ? AppColors.campusBlue.withValues(alpha: 0.03) : null,
        border: Border(left: BorderSide(color: AppColors.line)),
      ),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          for (var period = 1; period <= PeriodTimes.periodsPerDay; period++)
            Positioned(
              top: _slotTopFor(slotHeight, period),
              left: 0,
              right: 0,
              child: Container(
                height: 1,
                color: AppColors.line.withValues(alpha: 0.7),
              ),
            ),
          for (final session in sessions)
            Positioned(
              top: _slotTopFor(slotHeight, session.startPeriod) + 3,
              left: 4,
              right: 4,
              height:
                  _slotSpanHeightFor(
                    slotHeight,
                    session.startPeriod,
                    session.endPeriod,
                  ) -
                  6,
              child: _CourseCard(session: session),
            ),
          for (final exam in exams) _examPositioned(exam, gridHeight),
        ],
      ),
    );
  }

  Widget _examPositioned(ExamEntry exam, double gridHeight) {
    final start = PeriodTimes.parseTime(exam.startTime);
    final end = PeriodTimes.parseTime(exam.endTime);
    // 考试卡必须严格落在课表格子上：按开始时间吸附到所在节次，
    // 再按 1 小时 1 格、超过 1 小时 2 格取固定高度。不能按真实分钟差
    // 直接算像素，否则 10:20–12:20 这类考试会从 10:20 起跨过 2 格后
    // 压到下一节。
    final startSlot = start == null
        ? 0
        : PeriodTimes.slotOffset(start)
              .floor()
              .clamp(0, PeriodTimes.periodsPerDay - 1);
    final durationMinutes = (start != null && end != null)
        ? (end - start).clamp(0, 24 * 60)
        : 0;
    final spanSlots = durationMinutes > 60 ? 2 : 1;
    final startPeriod = startSlot + 1;
    final endPeriod = (startSlot + spanSlots).clamp(
      1,
      PeriodTimes.periodsPerDay,
    );
    final top = _slotTopFor(slotHeight, startPeriod) + 3;
    final cardHeight =
        _slotSpanHeightFor(slotHeight, startPeriod, endPeriod) - 6;
    var safeTop = top;
    if (safeTop < 4) safeTop = 4;
    if (safeTop + cardHeight > gridHeight) {
      safeTop = gridHeight - cardHeight - 4;
    }
    return Positioned(
      top: safeTop,
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
    return LayoutBuilder(
      builder: (context, constraints) {
        // 默认 1280x800 时单节课约 36-48px，卡片自动收成「课名 + 教室」，
        // 只有多节连堂才补教师，信息密度随可用高度变化。
        final compact =
            constraints.maxHeight.isFinite && constraints.maxHeight < 54;
        final showRoom = !compact || constraints.maxHeight >= 33;
        return Tooltip(
          message: '${session.name}\n${session.room} · ${session.teacher}',
          waitDuration: const Duration(milliseconds: 700),
          child: Container(
            padding: EdgeInsets.fromLTRB(
              8,
              compact ? 3 : 6,
              6,
              compact ? 3 : 5,
            ),
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
                  maxLines: compact ? 1 : 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: inkColor,
                    fontSize: compact ? 10.5 : 11,
                    height: 1.25,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (showRoom) ...[
                  SizedBox(height: compact ? 1 : 3),
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
                ],
                if (!compact && session.span >= 2)
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
          ),
        );
      },
    );
  }
}

/// Exam cards share the 朱 (now-red) family: red in this app always means
/// "此刻/紧要" — exams and the current-time line, never decoration.
class _ExamColors {
  static Color get background =>
      AppColors.isDark ? const Color(0xFF3A1F1A) : const Color(0xFFFFF1EE);
  static Color get accent => AppColors.nowRed;
  static Color get soft =>
      AppColors.isDark ? const Color(0x33E97A63) : const Color(0x2EC2402A);

  /// Day-view exam cards use a visible, closed outline. Keep it in the same
  /// 朱红 family instead of a neutral divider colour.
  static Color get outline =>
      AppColors.isDark ? const Color(0x99E97A63) : const Color(0x99C2402A);
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
    final location = exam.room.trim();
    final seat = exam.seat.trim();
    final detail = [
      if (location.isNotEmpty) location,
      if (seat.isNotEmpty) '考号 $seat',
    ].join(' · ');
    final typeLabel = exam.type.trim().isEmpty ? '考试' : exam.type.trim();
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: LayoutBuilder(
        builder: (context, constraints) {
          // 周视图用 Positioned 给了固定高度，Stack 必须撑满这格；
          // 日视图高度由内容决定，保持 loose 以免无界高度报错。
          return Stack(
            fit: constraints.hasBoundedHeight
                ? StackFit.expand
                : StackFit.loose,
            children: [
              Container(
                padding: EdgeInsets.fromLTRB(
                  compact ? 6 : 13,
                  compact ? 4 : 11,
                  compact ? 5 : 13,
                  compact ? 3 : 11,
                ),
                decoration: BoxDecoration(color: _ExamColors.background),
                child: compact
                    ? LayoutBuilder(
                        builder: (context, constraints) {
                          // 考试卡高度固定（1 格或 2 格），用 FittedBox 保证科目、时间、
                          // 地点/考号在有限高度内始终完整可见，不因卡片矮而丢字段。
                          return FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.topLeft,
                            child: SizedBox(
                              width: constraints.maxWidth,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Padding(
                                        padding: const EdgeInsets.only(top: 1),
                                        child: Icon(
                                          Icons.event_note_rounded,
                                          size: 10,
                                          color: _ExamColors.accent,
                                        ),
                                      ),
                                      const SizedBox(width: 3),
                                      Expanded(
                                        child: Text(
                                          exam.name,
                                          maxLines: 3,
                                          softWrap: true,
                                          overflow: TextOverflow.clip,
                                          style: TextStyle(
                                            color: _ExamColors.accent,
                                            fontSize: 10,
                                            height: 1.15,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  if (_timeLabel.isNotEmpty) ...[
                                    const SizedBox(height: 2),
                                    Text(
                                      _timeLabel,
                                      maxLines: 1,
                                      softWrap: false,
                                      overflow: TextOverflow.clip,
                                      style: TextStyle(
                                        color: _ExamColors.accent,
                                        fontSize: 8,
                                        height: 1.2,
                                        fontWeight: FontWeight.w500,
                                        fontFeatures: const [
                                          FontFeature.tabularFigures(),
                                        ],
                                      ),
                                    ),
                                  ],
                                  if (detail.isNotEmpty) ...[
                                    const SizedBox(height: 1),
                                    Text(
                                      detail,
                                      maxLines: 2,
                                      softWrap: true,
                                      overflow: TextOverflow.clip,
                                      style: TextStyle(
                                        color: _ExamColors.accent.withValues(
                                          alpha: 0.78,
                                        ),
                                        fontSize: 8,
                                        height: 1.2,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          );
                        },
                      )
                    : Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Icon(
                              Icons.event_note_rounded,
                              size: 15,
                              color: _ExamColors.accent,
                            ),
                          ),
                          const SizedBox(width: 7),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(
                                      child: Text(
                                        exam.name,
                                        maxLines: 3,
                                        softWrap: true,
                                        overflow: TextOverflow.clip,
                                        style: TextStyle(
                                          color: _ExamColors.accent,
                                          fontSize: 13,
                                          height: 1.25,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 6,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: _ExamColors.soft,
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        typeLabel,
                                        style: TextStyle(
                                          color: _ExamColors.accent,
                                          fontSize: 8,
                                          height: 1.2,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                if (_timeLabel.isNotEmpty) ...[
                                  const SizedBox(height: 3),
                                  Text(
                                    _timeLabel,
                                    style: TextStyle(
                                      color: _ExamColors.accent,
                                      fontSize: 10,
                                      height: 1.3,
                                      fontWeight: FontWeight.w500,
                                      fontFeatures: [
                                        FontFeature.tabularFigures(),
                                      ],
                                    ),
                                  ),
                                ],
                                if (detail.isNotEmpty) ...[
                                  const SizedBox(height: 2),
                                  Text(
                                    detail,
                                    maxLines: 2,
                                    softWrap: true,
                                    overflow: TextOverflow.clip,
                                    style: TextStyle(
                                      color: _ExamColors.accent.withValues(
                                        alpha: 0.78,
                                      ),
                                      fontSize: 9,
                                      height: 1.35,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
              ),
              if (!compact)
                Positioned.fill(
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: _ExamColors.outline,
                          width: 1,
                        ),
                      ),
                    ),
                  ),
                ),
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                height: 3,
                child: ColoredBox(color: _ExamColors.accent),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// 周视图下方的“考试安排”列表：日期、时间段、科目、地点、考号都直接给出，
/// 与课程卡片保持明显不同的朱红色系。
class _ExamScheduleSection extends StatefulWidget {
  const _ExamScheduleSection({required this.exams});

  final List<ExamEntry> exams;

  @override
  State<_ExamScheduleSection> createState() => _ExamScheduleSectionState();
}

class _ExamScheduleSectionState extends State<_ExamScheduleSection> {
  bool _showAll = true;

  bool _isExamEnded(ExamEntry exam, DateTime now) {
    final day = DateTime(exam.date.year, exam.date.month, exam.date.day);
    final startMinutes = PeriodTimes.parseTime(exam.startTime);
    final endMinutes =
        PeriodTimes.parseTime(exam.endTime) ??
        (startMinutes == null
            ? null
            : startMinutes + PeriodTimes.periodMinutes);
    if (endMinutes == null) {
      return day.isBefore(DateTime(now.year, now.month, now.day));
    }
    final end = day.add(Duration(minutes: endMinutes));
    return !now.isBefore(end);
  }

  Widget _filterButton() {
    return Tooltip(
      message: _showAll ? '只显示未考考试' : '显示所有考试',
      child: InkWell(
        onTap: () => setState(() => _showAll = !_showAll),
        borderRadius: BorderRadius.circular(6),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: AppColors.surface,
            border: Border.all(color: AppColors.line),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                _showAll ? Icons.filter_alt_outlined : Icons.filter_alt,
                size: 12,
                color: AppColors.campusBlue,
              ),
              const SizedBox(width: 4),
              Text(
                _showAll ? '全部' : '未考',
                style: TextStyle(
                  color: AppColors.campusBlue,
                  fontSize: 9,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final exams = _showAll
        ? widget.exams
        : widget.exams.where((exam) => !_isExamEnded(exam, now)).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.event_note_outlined, size: 14, color: AppColors.muted),
            const SizedBox(width: 6),
            Text(
              '考试安排',
              style: TextStyle(
                color: AppColors.ink,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (exams.isNotEmpty) ...[
              const SizedBox(width: 8),
              Text(
                '共 ${exams.length} 场',
                style: TextStyle(color: AppColors.faint, fontSize: 9),
              ),
            ],
            const Spacer(),
            _filterButton(),
          ],
        ),
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: AppColors.surface,
            border: Border.all(color: AppColors.line),
            borderRadius: BorderRadius.circular(8),
          ),
          clipBehavior: Clip.antiAlias,
          child: exams.isEmpty
              ? Padding(
                  padding: EdgeInsets.symmetric(vertical: 22),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.event_available_outlined,
                        size: 16,
                        color: AppColors.faint,
                      ),
                      SizedBox(width: 8),
                      Text(
                        _showAll ? '本学期暂无考试安排' : '暂无未考考试',
                        style: TextStyle(color: AppColors.muted, fontSize: 10),
                      ),
                    ],
                  ),
                )
              : Column(
                  children: [
                    for (var i = 0; i < exams.length; i++) ...[
                      if (i != 0)
                        Divider(height: 1, thickness: 1, color: AppColors.line),
                      _ExamScheduleRow(
                        exam: exams[i],
                        isEnded: _isExamEnded(exams[i], now),
                      ),
                    ],
                  ],
                ),
        ),
      ],
    );
  }
}

class _ExamScheduleRow extends StatelessWidget {
  const _ExamScheduleRow({required this.exam, required this.isEnded});

  final ExamEntry exam;
  final bool isEnded;

  @override
  Widget build(BuildContext context) {
    final detail = [
      if (_examTimeLabel(exam).isNotEmpty) _examTimeLabel(exam),
      if (exam.room.trim().isNotEmpty) '地点 ${exam.room.trim()}',
      if (exam.seat.trim().isNotEmpty) '考号 ${exam.seat.trim()}',
    ].join(' · ');
    final nameColor = isEnded ? AppColors.faint : _ExamColors.accent;
    final now = DateTime.now();
    final isToday =
        exam.date.year == now.year &&
        exam.date.month == now.month &&
        exam.date.day == now.day;
    final typeLabel = exam.type.trim().isEmpty ? '考试' : exam.type.trim();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 50,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _dateLabel(exam.date),
                  style: TextStyle(
                    color: isEnded ? AppColors.faint : AppColors.ink,
                    fontSize: 13,
                    height: 1.25,
                    fontWeight: FontWeight.w600,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  isToday ? '今天' : _weekdays[exam.date.weekday - 1],
                  style: TextStyle(
                    color: isToday && !isEnded
                        ? _ExamColors.accent
                        : AppColors.faint,
                    fontSize: 8,
                    height: 1.2,
                    fontWeight: isToday ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ],
            ),
          ),
          Container(width: 1, height: 30, color: AppColors.line),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        exam.name,
                        maxLines: 2,
                        softWrap: true,
                        overflow: TextOverflow.clip,
                        style: TextStyle(
                          color: nameColor,
                          fontSize: 11,
                          height: 1.3,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 5,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: isEnded
                            ? AppColors.line.withValues(alpha: 0.35)
                            : _ExamColors.soft,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        typeLabel,
                        style: TextStyle(
                          color: isEnded ? AppColors.faint : _ExamColors.accent,
                          fontSize: 8,
                          height: 1.2,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                if (detail.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    detail,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: isEnded ? AppColors.faint : AppColors.muted,
                      fontSize: 9,
                      height: 1.35,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
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
      mainAxisSize: MainAxisSize.min,
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
              color: AppColors.surface,
              border: Border.all(color: AppColors.line),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              children: [
                Icon(Icons.coffee_outlined, color: AppColors.faint, size: 26),
                SizedBox(height: 8),
                Text(
                  '这一天没有安排',
                  style: TextStyle(color: AppColors.muted, fontSize: 11),
                ),
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
          style: TextStyle(color: AppColors.faint, fontSize: 9),
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
          color: active ? AppColors.campusBlue : AppColors.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: active ? AppColors.campusBlue : AppColors.line,
          ),
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
        color: AppColors.surface,
        border: Border.all(color: AppColors.line),
        borderRadius: BorderRadius.circular(8),
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
                  PeriodTimes.rangeLabel(
                    session.startPeriod,
                    session.endPeriod,
                  ),
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
                  style: TextStyle(color: AppColors.faint, fontSize: 8),
                ),
              ],
            ),
          ),
          Container(
            width: 2,
            height: 38,
            color: inkColor.withValues(alpha: 0.28),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  session.name,
                  style: TextStyle(
                    color: AppColors.ink,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${session.room} · ${session.teacher}',
                  style: TextStyle(color: AppColors.muted, fontSize: 9),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
