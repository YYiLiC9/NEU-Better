import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/app_theme.dart';
import '../../core/settings/app_settings.dart';
import 'timetable_models.dart';
import 'timetable_schedule.dart';
import 'timetable_store.dart';
import 'yjs_timetable_page.dart';

part 'widgets/timetable_chrome.dart';
part 'widgets/timetable_week_grid.dart';
part 'widgets/timetable_exam_widgets.dart';
part 'widgets/timetable_day_agenda.dart';

const _weekdays = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];

/// 按「每周起始日」返回 7 列的显示顺序（元素是 1=周一 … 7=周日）。
/// 只调整显示顺序，数据里 [CourseSession.day] 的语义不变。
List<int> _orderedDaysFor(WeekStart weekStart) {
  return weekStart == WeekStart.sunday
      ? const [7, 1, 2, 3, 4, 5, 6]
      : const [1, 2, 3, 4, 5, 6, 7];
}
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

class TimetablePage extends ConsumerStatefulWidget {
  const TimetablePage({
    super.key,
    this.compact = false,
    this.mobile = false,
  });

  final bool compact;

  /// 手机端专属：竖屏满屏周视图（7 列完整显示、12 节完整显示）。
  final bool mobile;

  @override
  ConsumerState<TimetablePage> createState() => _TimetablePageState();
}

class _TimetablePageState extends ConsumerState<TimetablePage> {
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

  TimetableSchedule get _schedule => TimetableSchedule(_data);

  int get _nowWeek => _schedule.nowWeek();

  /// 「下一节」：当前周里今天还没开始、或本周后续、或下周第一节课。
  (CourseSession, String)? get _nextSession => _schedule.nextSession(_week);

  List<CourseSession> get _weekSessions => _schedule.weekSessions(_week);

  List<ExamEntry> _examsForWeek(int week) => _schedule.examsForWeek(week);

  List<ExamEntry> get _allExams => _schedule.allExams;

  List<CourseSession> get _daySessions =>
      _schedule.daySessions(_selectedDay, _week);

  List<ExamEntry> get _dayExams => _schedule.dayExams(_selectedDay, _week);

  DateTime? get _weekStart => _schedule.weekStartFor(_week);

  DateTime? _weekStartFor(int week) => _schedule.weekStartFor(week);

  bool _isWeekToday(int week) => _schedule.isWeekToday(week);

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
    // 阈值从 ±120 提到 ±400（px/s）：轻扫不再误翻周，需要明显的一次滑动。
    final velocity = details.primaryVelocity ?? 0;
    if (velocity < -400) {
      _changeWeek(_week + 1);
    } else if (velocity > 400) {
      _changeWeek(_week - 1);
    }
  }

  /// 日视图水平滑动切换相邻星期；按当前「每周起始日」的显示顺序前进/后退，
  /// 到显示序列两端不越界（保持不动）。
  void _onDayDrag(DragEndDetails details) {
    final velocity = details.primaryVelocity ?? 0;
    if (velocity.abs() <= 400) return;
    final days = _orderedDaysFor(ref.read(appSettingsProvider).weekStart);
    final index = days.indexOf(_selectedDay);
    if (index < 0) return;
    final nextIndex = velocity < 0 ? index + 1 : index - 1;
    if (nextIndex < 0 || nextIndex >= days.length) return;
    setState(() => _selectedDay = days[nextIndex]);
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
    final days = _orderedDaysFor(ref.watch(appSettingsProvider).weekStart);
    return LayoutBuilder(
      builder: (context, constraints) {
        if (widget.mobile) return _buildMobile(context, days);
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
                      _buildWeekView(slotHeight, days: days)
                    else
                      _buildDayAgenda(days: days),
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

  /// 手机端满屏布局：头部固定（仅学期+同步、周切换/今天/视图切换一行），
  /// 周视图独占剩余高度并精确换算节高，让 7 天 × 12 节一次性完整显示。
  Widget _buildMobile(BuildContext context, List<int> days) {
    final header = Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: _buildHeader(context),
    );
    if (!_weekView) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          header,
          const SizedBox(height: 10),
          Expanded(
            // 日视图也支持左右滑动切换星期。顶部 7 个 _DayChip 自带横向
            // 滚动，深处的手势优先，不受这里影响。
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onHorizontalDragEnd: _onDayDrag,
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
                child: _buildDayAgenda(days: days),
              ),
            ),
          ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        header,
        const SizedBox(height: 8),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
            child: LayoutBuilder(
              builder: (context, gridConstraints) {
                final slotHeight = _mobileSlotHeight(gridConstraints.maxHeight);
                // 正常高度：精确铺满剩余空间，12 节之后不留空白行。
                // 极矮屏（横屏/折叠态）节高过小，则保底 24 并允许滚动，避免溢出。
                if (slotHeight < 24) {
                  return SingleChildScrollView(
                    child: _buildWeekView(
                      24.0,
                      fitWidth: true,
                      gutterWidth: 34,
                      dense: true,
                      days: days,
                    ),
                  );
                }
                return _buildWeekView(
                  slotHeight,
                  fitWidth: true,
                  gutterWidth: 34,
                  dense: true,
                  days: days,
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  /// 手机端周视图节高：把 12 节精确铺满可用高度（含表头与两条休息带），
  /// 不取整、不设上限 —— 否则剩余像素会在第 12 节下堆成一条空白行。
  /// 减去的 2.0 是网格外框上下各 1px 的边框（BoxDecoration.border 会作为
  /// 内边距吃掉子节点 2px，算漏就会触发 2px 溢出）。
  double _mobileSlotHeight(double gridViewportHeight) {
    return (gridViewportHeight - _headerHeight - 2 * _breakGap - 2.0) /
        PeriodTimes.periodsPerDay;
  }

  Widget _buildWeekView(
    double slotHeight, {
    bool fitWidth = false,
    double gutterWidth = _timeGutterWidth,
    bool dense = false,
    required List<int> days,
  }) {
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
        gutterWidth: gutterWidth,
        dense: dense,
        days: days,
      ),
    );
    if (!widget.compact || fitWidth) return pager;
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

  Widget _buildDayAgenda({required List<int> days}) {
    return Align(
      alignment: Alignment.topCenter,
      child: SizedBox(
        width: double.infinity,
        child: _DayAgenda(
          week: _week,
          weekStart: _weekStart,
          selectedDay: _selectedDay,
          sessions: _daySessions,
          exams: _dayExams,
          days: days,
          onDayChanged: (day) => setState(() => _selectedDay = day),
        ),
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
    if (widget.compact) return _buildCompactHeader(context);

    final title = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '我的课表',
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
            fontSize: 24,
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

    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(child: title),
        controls,
      ],
    );
  }

  /// 手机端头部：第一行「学期 + 文字「同步」按钮」（不显示「我的课表」），
  /// 第二行把周切换 / 今天 / 周-日视图切换压到同一行。
  Widget _buildCompactHeader(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                _data.termName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: AppColors.muted,
                  fontSize: 11,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              onPressed: _syncTimetable,
              icon: const Icon(Icons.sync_rounded, size: 14),
              label: const Text('同步'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.campusBlue,
                side: BorderSide(color: AppColors.line),
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                minimumSize: const Size(0, 32),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                textStyle: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            _WeekStepper(
              week: _week,
              totalWeeks: _data.totalWeeks,
              onChanged: _changeWeek,
              dense: true,
            ),
            const SizedBox(width: 6),
            OutlinedButton(
              onPressed: _goToday,
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.ink,
                side: BorderSide(color: AppColors.line),
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                minimumSize: const Size(0, 34),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                textStyle: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
              child: const Text('今天'),
            ),
            const Spacer(),
            _ViewToggle(
              weekView: _weekView,
              onChanged: (value) => setState(() => _weekView = value),
              dense: true,
            ),
          ],
        ),
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
