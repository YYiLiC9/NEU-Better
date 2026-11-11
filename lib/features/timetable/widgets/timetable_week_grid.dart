part of '../timetable_page.dart';

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
