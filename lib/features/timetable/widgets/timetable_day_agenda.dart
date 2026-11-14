part of '../timetable_page.dart';

class _DayAgenda extends StatelessWidget {
  const _DayAgenda({
    required this.week,
    required this.weekStart,
    required this.selectedDay,
    required this.sessions,
    required this.exams,
    required this.days,
    required this.onDayChanged,
    this.onOpenCourse,
    this.onOpenExam,
    this.onOpenCourseLongPress,
    this.onEditCourse,
    this.notedCourseIds = const <String>{},
  });

  final int week;
  final DateTime? weekStart;
  final int selectedDay;
  final List<CourseSession> sessions;
  final List<ExamEntry> exams;

  /// 7 个星期标签的显示顺序（1=周一 … 7=周日），由「每周起始日」决定。
  final List<int> days;
  final ValueChanged<int> onDayChanged;
  final void Function(CourseSession session)? onOpenCourse;
  final void Function(ExamEntry exam)? onOpenExam;

  /// 卡片长按（手机）/ 右键（电脑）也进详情。
  final void Function(CourseSession session)? onOpenCourseLongPress;
  final void Function(CourseSession session)? onEditCourse;
  final Set<String> notedCourseIds;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.start,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (var index = 0; index < days.length; index++) ...[
                _DayChip(
                  label: _weekdays[days[index] - 1],
                  date: weekStart?.add(Duration(days: index)),
                  active: days[index] == selectedDay,
                  onTap: () => onDayChanged(days[index]),
                ),
                if (index != days.length - 1) const SizedBox(width: 6),
              ],
            ],
          ),
        ),
        const SizedBox(height: 12),
        if (exams.isNotEmpty) ...[
          for (final exam in exams) ...[
            _ExamCard(
              exam: exam,
              onTap: onOpenExam == null ? null : () => onOpenExam!(exam),
            ),
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
            _AgendaCard(
              session: session,
              hasNote: notedCourseIds.contains(session.id),
              onTap: onOpenCourse == null
                  ? null
                  : () => onOpenCourse!(session),
              onLongPress: onEditCourse == null
                  ? null
                  : () => onEditCourse!(session),
              onSecondaryTap: onEditCourse == null
                  ? null
                  : () => onEditCourse!(session),
            ),
            const SizedBox(height: 8),
          ],
        const SizedBox(height: 4),
        Text(
          '第 $week 周',
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
  const _AgendaCard({
    required this.session,
    this.hasNote = false,
    this.onTap,
    this.onLongPress,
    this.onSecondaryTap,
  });

  final CourseSession session;
  final bool hasNote;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final VoidCallback? onSecondaryTap;

  @override
  Widget build(BuildContext context) {
    final (_, inkColor) = AppColors.pigmentFor(session.name);
    final card = Container(
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
                // 开始 / 结束时间分两行，去掉中间的横杠，避免 78 宽里
                // 折成「08:30-」/「09:15」的难读断行。
                Text(
                  PeriodTimes.startLabel(session.startPeriod),
                  style: TextStyle(
                    color: inkColor,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                Text(
                  PeriodTimes.endLabel(session.endPeriod),
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
                  softWrap: true,
                  style: TextStyle(
                    color: AppColors.ink,
                    fontSize: 14.5,
                    height: 1.25,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (session.room.trim().isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    session.room,
                    softWrap: true,
                    style: TextStyle(
                      color: AppColors.muted,
                      fontSize: 10,
                      height: 1.25,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      onSecondaryTap: onSecondaryTap,
      behavior: HitTestBehavior.opaque,
      child: Stack(
        children: [
          card,
          if (hasNote)
            Positioned(
              top: 8,
              right: 8,
              child: Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  color: inkColor,
                  shape: BoxShape.circle,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
