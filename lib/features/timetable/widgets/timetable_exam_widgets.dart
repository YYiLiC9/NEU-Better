part of '../timetable_page.dart';

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

  TextStyle _timeStyle(double size) => TextStyle(
    color: _ExamColors.accent,
    fontSize: size,
    height: 1.2,
    fontWeight: FontWeight.w500,
    fontFeatures: const [FontFeature.tabularFigures()],
  );

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
                                  SizedBox(
                                    width: constraints.maxWidth,
                                    child: Text(
                                      exam.name,
                                      textAlign: TextAlign.center,
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
                                  if (exam.startTime != null) ...[
                                    const SizedBox(height: 2),
                                    Text(
                                      exam.startTime!,
                                      maxLines: 1,
                                      softWrap: false,
                                      overflow: TextOverflow.clip,
                                      style: _timeStyle(8),
                                    ),
                                    if (exam.endTime != null &&
                                        exam.endTime!.isNotEmpty)
                                      Text(
                                        exam.endTime!,
                                        maxLines: 1,
                                        softWrap: false,
                                        overflow: TextOverflow.clip,
                                        style: _timeStyle(8),
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
                                if (exam.startTime != null) ...[
                                  const SizedBox(height: 3),
                                  Text(exam.startTime!, style: _timeStyle(10)),
                                  if (exam.endTime != null &&
                                      exam.endTime!.isNotEmpty)
                                    Text(exam.endTime!, style: _timeStyle(10)),
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
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.line),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _filterOption('全部', _showAll, () => setState(() => _showAll = true)),
          _filterOption(
            '未考',
            !_showAll,
            () => setState(() => _showAll = false),
          ),
        ],
      ),
    );
  }

  Widget _filterOption(String label, bool selected, VoidCallback onTap) {
    return Tooltip(
      message: selected ? '当前显示$label' : '切换到$label',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
          decoration: BoxDecoration(
            color: selected ? AppColors.campusBlue : Colors.transparent,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: selected ? Colors.white : AppColors.muted,
              fontSize: 9,
              fontWeight: FontWeight.w600,
            ),
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
