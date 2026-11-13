part of '../timetable_page.dart';

class _WeekGrid extends StatelessWidget {
  const _WeekGrid({
    required this.weekStart,
    required this.sessions,
    required this.exams,
    required this.today,
    required this.onWeekDrag,
    required this.slotHeight,
    required this.days,
    this.gutterWidth = _timeGutterWidth,
    this.dense = false,
    this.onOpenCourse,
    this.onOpenExam,
    this.notedCourseIds = const <String>{},
    this.onCellLongPress,
    this.onCellSecondaryTap,
  });

  final DateTime? weekStart;
  final List<CourseSession> sessions;
  final List<ExamEntry> exams;
  final bool today;
  final double slotHeight;
  final double gutterWidth;
  final bool dense;
  final void Function(CourseSession session)? onOpenCourse;
  final void Function(ExamEntry exam)? onOpenExam;
  final Set<String> notedCourseIds;

  /// 空白格长按（手机）/ 右键（电脑）：新增课程。
  final void Function(int day, int period)? onCellLongPress;
  final void Function(int day, int period)? onCellSecondaryTap;

  /// 7 列的显示顺序（1=周一 … 7=周日），由「每周起始日」决定。
  final List<int> days;

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
                  SizedBox(width: gutterWidth),
                  for (final day in days)
                    Expanded(
                      child: _DayHeader(
                        label: _weekdays[day - 1],
                        date: weekStart?.add(
                          Duration(days: days.indexOf(day)),
                        ),
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
                        width: gutterWidth,
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
                                        // 开始/结束时间分两行，去掉中间的横杠，
                                        // 窄的窄条里更好读、不折行。
                                        Column(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Text(
                                              PeriodTimes.startLabel(period),
                                              style: TextStyle(
                                                color: AppColors.faint,
                                                fontSize: 8,
                                                height: 1.1,
                                                fontFeatures: [
                                                  FontFeature.tabularFigures(),
                                                ],
                                              ),
                                            ),
                                            Text(
                                              PeriodTimes.endLabel(period),
                                              style: TextStyle(
                                                color: AppColors.faint,
                                                fontSize: 8,
                                                height: 1.1,
                                                fontFeatures: [
                                                  FontFeature.tabularFigures(),
                                                ],
                                              ),
                                            ),
                                          ],
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
                      for (final day in days)
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
                                        weekStart!.add(
                                          Duration(days: days.indexOf(day)),
                                        ),
                                      ),
                                )
                                .toList(),
                            isToday: today && day == now.weekday,
                            slotHeight: slotHeight,
                            dense: dense,
                            onOpenCourse: onOpenCourse,
                            onOpenExam: onOpenExam,
                            notedCourseIds: notedCourseIds,
                            onCellLongPress: onCellLongPress,
                            onCellSecondaryTap: onCellSecondaryTap,
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
                _dateLabel(date!),
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
    this.dense = false,
    this.onOpenCourse,
    this.onOpenExam,
    this.notedCourseIds = const <String>{},
    this.onCellLongPress,
    this.onCellSecondaryTap,
  });

  final int day;
  final List<CourseSession> sessions;
  final List<ExamEntry> exams;
  final bool isToday;
  final double slotHeight;
  final bool dense;
  final void Function(CourseSession session)? onOpenCourse;
  final void Function(ExamEntry exam)? onOpenExam;
  final Set<String> notedCourseIds;
  final void Function(int day, int period)? onCellLongPress;
  final void Function(int day, int period)? onCellSecondaryTap;

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
          // 空白格手势层（在课程卡之下）：长按（手机）/ 右键（电脑）新增课程。
          for (var period = 1; period <= PeriodTimes.periodsPerDay; period++)
            Positioned(
              top: _slotTopFor(slotHeight, period),
              left: 0,
              right: 0,
              height: slotHeight,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onLongPress: onCellLongPress == null
                    ? null
                    : () => onCellLongPress!(day, period),
                onSecondaryTap: onCellSecondaryTap == null
                    ? null
                    : () => onCellSecondaryTap!(day, period),
              ),
            ),
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
              left: dense ? 2 : 4,
              right: dense ? 2 : 4,
              height:
                  _slotSpanHeightFor(
                    slotHeight,
                    session.startPeriod,
                    session.endPeriod,
                  ) -
                  (dense ? 4 : 6),
              child: _CourseCard(
                session: session,
                dense: dense,
                hasNote: notedCourseIds.contains(session.id),
                onTap: onOpenCourse == null
                    ? null
                    : () => onOpenCourse!(session),
                onLongPress: onOpenCourse == null
                    ? null
                    : () => onOpenCourse!(session),
                onSecondaryTap: onOpenCourse == null
                    ? null
                    : () => onOpenCourse!(session),
              ),
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
      child: _ExamCard(
        exam: exam,
        compact: true,
        onTap: onOpenExam == null ? null : () => onOpenExam!(exam),
      ),
    );
  }
}

class _CourseCard extends StatelessWidget {
  const _CourseCard({
    required this.session,
    this.dense = false,
    this.hasNote = false,
    this.onTap,
    this.onLongPress,
    this.onSecondaryTap,
  });

  final CourseSession session;
  final bool dense;
  final bool hasNote;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final VoidCallback? onSecondaryTap;

  @override
  Widget build(BuildContext context) {
    final (tint, inkColor) = AppColors.pigmentFor(session.name);
    return LayoutBuilder(
      builder: (context, constraints) {
        // 默认 1280x800 时单节课约 36-48px，卡片自动收成「课名 + 教室」，
        // 只有多节连堂才补教师，信息密度随可用高度变化。
        final compact =
            constraints.maxHeight.isFinite && constraints.maxHeight < 54;
        final showRoom = session.room.trim().isNotEmpty;
        final padLeft = dense ? 5.0 : 8.0;
        final padRight = dense ? 4.0 : 6.0;
        final card = Tooltip(
          message: '${session.name}\n${session.room} · ${session.teacher}',
          waitDuration: const Duration(milliseconds: 700),
          child: Container(
            padding: EdgeInsets.fromLTRB(
              padLeft,
              compact ? 3 : 6,
              padRight,
              compact ? 3 : 5,
            ),
            decoration: BoxDecoration(
              color: tint,
              borderRadius: BorderRadius.circular(8),
              // 手机端（dense）去掉左侧 3px 深色竖条，改用与底色同系的极淡
              // 1px 描边；桌面端保持原有的深色左边条。
              border: dense
                  ? Border.all(color: inkColor.withValues(alpha: 0.18))
                  : Border(left: BorderSide(color: inkColor, width: 3)),
            ),
            // 课名 / 地点 / 教师都【完整显示】：不再用省略号，允许换行；
            // 卡片高度固定时用 FittedBox(scaleDown) 整体等比缩小兜底，
            // 保证长课名（如「中国式现代化的理论与实践」）不被截断、也不溢出。
            child: LayoutBuilder(
              builder: (context, inner) {
                final maxW = inner.maxWidth;
                return FittedBox(
                  fit: BoxFit.scaleDown,
                  // 水平居中：长课名被整体等比缩小后，内容仍对准卡片中线，
                  // 而不是缩到左上角显得左偏（课程/考试名称要求左右居中）。
                  alignment: Alignment.topCenter,
                  child: SizedBox(
                    width: maxW,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // 课程名：字号最大且加粗、居中；超长自然换行、完整显示。
                        SizedBox(
                          width: maxW,
                          child: Text(
                            session.name,
                            textAlign: TextAlign.center,
                            softWrap: true,
                            overflow: TextOverflow.clip,
                            style: TextStyle(
                              color: inkColor,
                              fontSize: dense ? 12.5 : (compact ? 11.5 : 12.5),
                              height: 1.18,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        if (showRoom) ...[
                          SizedBox(height: compact ? 1 : 2),
                          Text(
                            session.room,
                            softWrap: true,
                            overflow: TextOverflow.clip,
                            style: TextStyle(
                              color: inkColor.withValues(alpha: 0.72),
                              fontSize: dense ? 9 : 8.5,
                              height: 1.15,
                              fontFeatures: const [FontFeature.tabularFigures()],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        );
        return GestureDetector(
          onTap: onTap,
          onLongPress: onLongPress,
          onSecondaryTap: onSecondaryTap,
          behavior: HitTestBehavior.opaque,
          child: Stack(
            children: [
              Positioned.fill(child: card),
              if (hasNote)
                Positioned(
                  top: 4,
                  right: 4,
                  child: Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: inkColor,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

/// Exam cards share the 朱 (now-red) family: red in this app always means
/// "此刻/紧要" — exams and the current-time line, never decoration.
