import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../../app/theme/app_theme.dart';
import '../../core/settings/app_settings.dart';
import 'course_note_store.dart';
import 'course_override_store.dart';
import 'timetable_models.dart';
import 'timetable_overlay.dart';
import 'timetable_schedule.dart';
import 'timetable_store.dart';
import 'timetable_widget_service.dart';
import 'yjs_timetable_page.dart';

part 'widgets/timetable_chrome.dart';
part 'widgets/timetable_week_grid.dart';
part 'widgets/timetable_exam_widgets.dart';
part 'widgets/timetable_day_agenda.dart';
part 'widgets/course_detail_sheet.dart';
part 'widgets/course_editor_sheet.dart';

/// 课表数据的跨重建共享缓存：主题切换会重挂载根子树，把它放在
/// ProviderScope 层可在重建后立即恢复（含考试信息），不必再读磁盘。
final timetableDataProvider = StateProvider<TimetableData?>((ref) => null);

/// 课表本地覆盖层（新增/修改/删除）的跨重建共享缓存。
/// 主题切换会重挂载根子树，放在 ProviderScope 层可在重建后立刻恢复。
final timetableOverlayProvider = StateProvider<TimetableOverlay?>(
  (ref) => null,
);

/// 课表视图状态（当前周 / 选中星期 / 周或日视图）的跨重建缓存：
/// 主题切换会重挂载根子树，恢复这些状态避免跳回当前周/日视图，
/// 从而避免「切主题后原本查看那周的考试标签消失」。
class _TimetableViewState {
  const _TimetableViewState({this.week, this.day, this.weekView = true});

  final int? week;
  final int? day;
  final bool weekView;
}

final timetableViewProvider =
    StateProvider<_TimetableViewState>((ref) => const _TimetableViewState());

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
  /// 官方快照（只含同步结果，不含用户修改）。
  TimetableData _officialData = TimetableData.empty;

  /// 本地覆盖层（用户新增 / 修改 / 删除）。
  TimetableOverlay _overlay = TimetableOverlay.empty;

  /// 展示用数据 = applyOverlay(_officialData, _overlay)。
  TimetableData _data = TimetableData.empty;
  int _week = 1;
  int _selectedDay = DateTime.now().weekday.clamp(1, 7);
  int _direction = 1;
  bool _weekView = true;
  int? _selectedCellDay;
  int? _selectedCellPeriod;
  int _lastNowMinute = DateTime.now().hour * 60 + DateTime.now().minute;
  Timer? _minuteTimer;
  final ScrollController _scrollController = ScrollController();

  /// 课程备注（键 = 课程 id），独立存 course_notes.json，不受同步覆盖。
  Map<String, String> _courseNotes = <String, String>{};

  @override
  void initState() {
    super.initState();
    _loadNotes();
    final shared = ref.read(timetableDataProvider);
    final sharedOverlay = ref.read(timetableOverlayProvider);
    final savedView = ref.read(timetableViewProvider);
    // 周/日视图选择持久化在 settings.json；冷启动与主题重挂载都从设置读取。
    _weekView = ref.read(appSettingsProvider).timetableWeekView;
    if (shared != null) {
      // 从 Provider 恢复（主题重挂载后仍保留课表、考试数据与正在查看的周）。
      _officialData = shared;
      _overlay = sharedOverlay ?? TimetableOverlay.empty;
      _data = applyOverlay(_officialData, _overlay);
      _week =
          savedView.week ??
          TimetableSchedule(
            _officialData,
            weekStartSetting: ref.read(appSettingsProvider).weekStart,
          ).nowWeek();
      _selectedDay = (savedView.day ?? _selectedDay).clamp(1, 7);
      // Provider 里可能只有刚自动同步的官方数据（home 写入），覆盖层需从磁盘补读。
      if (sharedOverlay == null) _bootstrapOverlay();
    } else {
      if (savedView.day != null) {
        _selectedDay = savedView.day!.clamp(1, 7);
      }
      _bootstrap();
    }
    timetableChanged.addListener(_onTimetableChanged);
    courseOverridesChanged.addListener(_onOverridesChanged);
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
    courseOverridesChanged.removeListener(_onOverridesChanged);
    _minuteTimer?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  void _onTimetableChanged() {
    _loadCachedTimetable(force: true);
  }

  void _onOverridesChanged() {
    _reloadOverlay();
  }

  /// 冷启动 / 主题重挂载且 Provider 无缓存时：从磁盘读官方快照与覆盖层。
  Future<void> _bootstrap() async {
    final cached = await const TimetableStore().read();
    final overlay = await const CourseOverrideStore().read();
    if (!mounted) return;
    _overlay = overlay;
    if (cached != null && cached.sessions.isNotEmpty) {
      _applyOfficial(cached, resetView: true);
    } else {
      // 没有缓存：保持空课表（不显示示例课表），等 HomePage 自动同步后通过
      // timetableChanged 通知刷新；期间界面显示「正在同步」占位。
      _data = applyOverlay(_officialData, _overlay);
      setState(() {});
    }
  }

  /// 只补读覆盖层（Provider 已有官方数据但没有覆盖层时使用）。
  Future<void> _bootstrapOverlay() async {
    final overlay = await const CourseOverrideStore().read();
    if (!mounted) return;
    _overlay = overlay;
    _recomputeOverlay();
  }

  Future<void> _loadCachedTimetable({bool force = false}) async {
    final cached = await const TimetableStore().read();
    if (!mounted || cached == null || cached.sessions.isEmpty) return;
    if (!force && _officialData.sessions.isNotEmpty) return;
    _applyOfficial(cached, resetView: true);
  }

  /// 从磁盘重新读取覆盖层（设置里清除修改后会触发）。
  Future<void> _reloadOverlay() async {
    final overlay = await const CourseOverrideStore().read();
    if (!mounted) return;
    _overlay = overlay;
    _recomputeOverlay();
  }

  /// 落官方快照：更新官方数据并重算展示数据；[resetView] 时刷新到当前教学周。
  void _applyOfficial(TimetableData official, {bool resetView = false}) {
    _officialData = official;
    _data = applyOverlay(_officialData, _overlay);
    ref.read(timetableDataProvider.notifier).state = _officialData;
    ref.read(timetableOverlayProvider.notifier).state = _overlay;
    final savedView = ref.read(timetableViewProvider);
    setState(() {
      if (resetView) {
        _week =
            savedView.week ??
            TimetableSchedule(
              _officialData,
              weekStartSetting: ref.read(appSettingsProvider).weekStart,
            ).nowWeek();
        _selectedDay = (savedView.day ?? _selectedDay).clamp(1, 7);
      }
    });
    // 同步到桌面小部件（今日课程），用合并后的展示数据。
    unawaited(TimetableWidgetService.sync(_data));
  }

  /// 提交覆盖层改动：重算展示数据、写内存 Provider、落盘、刷小部件。
  void _commitOverlay(TimetableOverlay overlay) {
    _overlay = overlay;
    _data = applyOverlay(_officialData, _overlay);
    ref.read(timetableOverlayProvider.notifier).state = _overlay;
    ref.read(timetableDataProvider.notifier).state = _officialData;
    setState(() {});
    unawaited(const CourseOverrideStore().save(_overlay));
    unawaited(TimetableWidgetService.sync(_data));
  }

  void _recomputeOverlay() {
    _data = applyOverlay(_officialData, _overlay);
    ref.read(timetableOverlayProvider.notifier).state = _overlay;
    setState(() {});
    unawaited(TimetableWidgetService.sync(_data));
  }

  /// 记录当前视图状态，供主题重挂载后恢复。
  void _persistView() {
    ref.read(timetableViewProvider.notifier).state = _TimetableViewState(
      week: _week,
      day: _selectedDay,
      weekView: _weekView,
    );
  }

  Future<void> _loadNotes() async {
    final notes = await const CourseNoteStore().read();
    if (!mounted || notes.isEmpty) return;
    setState(() => _courseNotes = notes);
  }

  Future<void> _openCourse(CourseSession session) {
    return showCourseDetail(
      context,
      session: session,
      initialNote: _courseNotes[session.id] ?? '',
      onNoteChanged: (text) => _saveNote(session.id, text),
      onEdit: () => _editCourse(session),
      onDeleteThisCourse: () => _deleteCourse(session, allWeeks: true),
      onDeleteThisWeek: () => _deleteCourse(session, allWeeks: false),
    );
  }

  Future<void> _openExam(ExamEntry exam) {
    return showCourseDetail(context, exam: exam);
  }

  /// 官方课程的原指纹：用官方快照按 id 反查，避免课程被改过 day/period 后失配。
  CourseSession? _officialSessionFor(CourseSession session) {
    for (final item in _officialData.sessions) {
      if (item.id == session.id) return item;
    }
    return null;
  }

  String _targetKeyFor(CourseSession session) {
    final official = _officialSessionFor(session);
    return courseKey(official ?? session);
  }

  Set<int> _officialWeeksFor(String targetKey) {
    final weeks = <int>{};
    for (final item in _officialData.sessions) {
      if (courseKey(item) == targetKey) weeks.addAll(item.weeks);
    }
    return weeks;
  }

  /// 打开空白格：右键/长按先框选该格，再新增一门课程。
  Future<void> _openNewCourse(int day, int period) async {
    setState(() {
      _selectedCellDay = day;
      _selectedCellPeriod = period;
    });
    // 先让本帧把框选画出来，再弹出编辑卡片，避免“卡片先出现/框选被盖住”。
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;
    await Future<void>.delayed(const Duration(milliseconds: 60));
    if (!mounted) return;
    final result = await showCourseEditor(
      context,
      presetDay: day,
      presetPeriod: period,
      presetWeek: _week,
      allWeeks: {for (var i = 1; i <= _data.totalWeeks; i++) i},
      validate: (draft, scope, week) => _validateDraft(draft, null),
    );
    if (!mounted) return;
    setState(() {
      _selectedCellDay = null;
      _selectedCellPeriod = null;
    });
    if (result == null) return;
    final id = 'user-${DateTime.now().microsecondsSinceEpoch}';
    _commitOverlay(_overlay.addCourse(result.session.copyWith(id: id)));
  }

  Future<void> _editCourse(CourseSession session) async {
    final isUser = session.id.startsWith('user-');
    final targetKey = isUser ? '' : _targetKeyFor(session);
    final allWeeks = isUser ? {...session.weeks} : _officialWeeksFor(targetKey);
    final result = await showCourseEditor(
      context,
      editing: session,
      presetWeek: _week,
      allWeeks: allWeeks.isEmpty ? {...session.weeks} : allWeeks,
      validate: (draft, scope, week) => _validateDraft(draft, session),
    );
    if (result == null || !mounted) return;
    if (isUser) {
      _commitOverlay(
        _overlay.replaceAdded(result.session.copyWith(id: session.id)),
      );
      return;
    }
    if (result.scope == 'all') {
      _commitOverlay(
        _overlay.modify(
          targetKey: targetKey,
          scope: 'all',
          replacement: result.session.copyWith(weeks: allWeeks),
        ),
      );
    } else {
      final week = result.week ?? _week;
      _commitOverlay(
        _overlay.modify(
          targetKey: targetKey,
          scope: 'week',
          week: week,
          replacement: result.session.copyWith(weeks: {week}),
        ),
      );
    }
  }

  Future<void> _deleteCourse(
    CourseSession session, {
    required bool allWeeks,
  }) async {
    final message = allWeeks
        ? '删除「${session.name}」的全部安排？'
        : '仅删除「${session.name}」第 $_week 周的安排？';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text(allWeeks ? '删除本课程' : '删除本周'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    if (session.id.startsWith('user-')) {
      _commitOverlay(
        allWeeks
            ? _overlay.removeAdded(session.id)
            : _overlay.removeAddedWeek(session.id, _week),
      );
      return;
    }
    final targetKey = _targetKeyFor(session);
    _commitOverlay(
      _overlay.delete(
        targetKey: targetKey,
        scope: allWeeks ? 'all' : 'week',
        week: allWeeks ? null : _week,
      ),
    );
  }

  /// 编辑时的冲突校验：先排除正在编辑的课程，再交给纯函数 [findConflicts]。
  Future<List<CourseConflict>> _validateDraft(
    CourseSession draft,
    CourseSession? editing,
  ) async {
    final base = <CourseSession>[];
    for (final item in _data.sessions) {
      if (editing != null) {
        if (item.id == editing.id) continue; // 自建课程按 id 排除
        if (!editing.id.startsWith('user-') &&
            courseKey(item) == _targetKeyFor(editing)) {
          continue; // 官方课程按指纹排除
        }
      }
      base.add(item);
    }
    return findConflicts(
      sessions: base,
      exams: _data.exams,
      candidate: draft,
      totalWeeks: _data.totalWeeks,
      termStartDate: _data.termStartDate,
    );
  }

  Future<void> _saveNote(String id, String text) async {
    final trimmed = text.trim();
    final next = Map<String, String>.from(_courseNotes);
    if (trimmed.isEmpty) {
      next.remove(id);
    } else {
      next[id] = trimmed;
    }
    if (mounted) setState(() => _courseNotes = next);
    await const CourseNoteStore().save(next);
  }

  TimetableSchedule get _schedule => TimetableSchedule(
    _data,
    weekStartSetting: ref.read(appSettingsProvider).weekStart,
  );

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
    _persistView();
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
    _persistView();
  }

  void _onWeekDrag(DragEndDetails details) {
    // 阻尼加大：阈值从 ±400 提到 ±900（px/s），需要明显、快速的一次滑动才翻周。
    final velocity = details.primaryVelocity ?? 0;
    if (velocity < -900) {
      _changeWeek(_week + 1);
    } else if (velocity > 900) {
      _changeWeek(_week - 1);
    }
  }

  /// 日视图水平滑动切换星期；按「每周起始日」的显示顺序前进/后退，
  /// 到序列两端时跨周：最后一天左滑进入下一周第一天，第一天右滑进入
  /// 上一周最后一天，顶部 7 个日期标签随 _week / _selectedDay 自动更新。
  void _onDayDrag(DragEndDetails details) {
    final velocity = details.primaryVelocity ?? 0;
    if (velocity.abs() <= 400) return;
    final days = _orderedDaysFor(ref.read(appSettingsProvider).weekStart);
    final index = days.indexOf(_selectedDay);
    if (index < 0) return;
    final nextIndex = velocity < 0 ? index + 1 : index - 1;
    if (nextIndex >= 0 && nextIndex < days.length) {
      setState(() => _selectedDay = days[nextIndex]);
    } else if (velocity < 0) {
      if (_week >= _data.totalWeeks) return;
      setState(() {
        _week += 1;
        _selectedDay = days.first;
      });
    } else {
      if (_week <= 1) return;
      setState(() {
        _week -= 1;
        _selectedDay = days.last;
      });
    }
    _persistView();
  }

  Future<void> _syncTimetable() async {
    final result = await Navigator.of(context).push<TimetableData>(
      MaterialPageRoute(builder: (_) => const YjsTimetablePage()),
    );
    if (result == null || !mounted) return;
    // 手动同步若本次没拿到考试（接口偶发失败），沿用页面已有考试，避免“考试消失”。
    var imported = result;
    if (imported.exams.isEmpty && _data.exams.isNotEmpty) {
      imported = TimetableData(
        termName: imported.termName,
        totalWeeks: imported.totalWeeks,
        sessions: imported.sessions,
        isSample: imported.isSample,
        currentWeek: imported.currentWeek,
        termStartDate: imported.termStartDate ?? _data.termStartDate,
        exams: _data.exams,
      );
    }
    await const TimetableStore().save(imported);
    if (!mounted) return;
    // 官方快照更新后重算展示数据；覆盖层（用户修改）保持不变。
    _applyOfficial(imported, resetView: true);
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

  Widget _buildEmptyTimetable() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.calendar_month_outlined, size: 40, color: AppColors.faint),
          const SizedBox(height: 12),
          Text(
            '暂无课表数据',
            style: TextStyle(
              color: AppColors.muted,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '正在同步，或点右上角「同步」获取你的课表',
            style: TextStyle(color: AppColors.faint, fontSize: 11),
          ),
        ],
      ),
    );
  }

  Widget _buildWeekView(
    double slotHeight, {
    bool fitWidth = false,
    double gutterWidth = _timeGutterWidth,
    bool dense = false,
    required List<int> days,
  }) {
    if (_data.sessions.isEmpty) return _buildEmptyTimetable();
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
        onOpenCourse: _openCourse,
        onOpenExam: _openExam,
        notedCourseIds: _courseNotes.keys.toSet(),
        onCellLongPress: _openNewCourse,
        onCellSecondaryTap: _openNewCourse,
        onEditCourse: _editCourse,
        selectedDay: _selectedCellDay,
        selectedPeriod: _selectedCellPeriod,
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
    if (_data.sessions.isEmpty) return _buildEmptyTimetable();
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
          onOpenCourse: _openCourse,
          onOpenExam: _openExam,
          onEditCourse: _editCourse,
          notedCourseIds: _courseNotes.keys.toSet(),
          onOpenCourseLongPress: _openCourse,
          onDayChanged: (day) {
            setState(() => _selectedDay = day);
            _persistView();
          },
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
          onChanged: (value) {
            setState(() => _weekView = value);
            ref
                .read(appSettingsProvider.notifier)
                .setTimetableWeekView(value);
            _persistView();
          },
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
              onChanged: (value) {
            setState(() => _weekView = value);
            ref
                .read(appSettingsProvider.notifier)
                .setTimetableWeekView(value);
            _persistView();
          },
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
