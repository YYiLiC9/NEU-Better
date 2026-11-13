part of '../timetable_page.dart';

/// 把不连续的周次集合压成可读文本，如 {1..16} → 「第1-16周」，
/// {2,4,6,8,10,12,14,16} → 「第2、4、6、8、10、12、14、16周」。
String formatWeeks(Set<int> weeks) {
  if (weeks.isEmpty) return '';
  final sorted = weeks.toList()..sort();
  final parts = <String>[];
  var rangeStart = sorted.first;
  var previous = sorted.first;
  for (var i = 1; i < sorted.length; i++) {
    final current = sorted[i];
    if (current == previous + 1) {
      previous = current;
      continue;
    }
    parts.add(rangeStart == previous ? '$rangeStart' : '$rangeStart-$previous');
    rangeStart = current;
    previous = current;
  }
  parts.add(rangeStart == previous ? '$rangeStart' : '$rangeStart-$previous');
  return '第${parts.join('、')}周';
}

/// 打开课程 / 考试详情弹窗。点弹窗外部即关闭返回课表（barrierDismissible）。
Future<void> showCourseDetail(
  BuildContext context, {
  CourseSession? session,
  ExamEntry? exam,
  String initialNote = '',
  ValueChanged<String>? onNoteChanged,
  VoidCallback? onEdit,
  VoidCallback? onDeleteThisCourse,
  VoidCallback? onDeleteThisWeek,
}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: true,
    builder: (_) => _CourseDetailDialog(
      session: session,
      exam: exam,
      initialNote: initialNote,
      onNoteChanged: onNoteChanged,
      onEdit: onEdit,
      onDeleteThisCourse: onDeleteThisCourse,
      onDeleteThisWeek: onDeleteThisWeek,
    ),
  );
}

class _CourseDetailDialog extends StatefulWidget {
  const _CourseDetailDialog({
    this.session,
    this.exam,
    this.initialNote = '',
    this.onNoteChanged,
    this.onEdit,
    this.onDeleteThisCourse,
    this.onDeleteThisWeek,
  });

  final CourseSession? session;
  final ExamEntry? exam;
  final String initialNote;
  final ValueChanged<String>? onNoteChanged;
  final VoidCallback? onEdit;
  final VoidCallback? onDeleteThisCourse;
  final VoidCallback? onDeleteThisWeek;

  @override
  State<_CourseDetailDialog> createState() => _CourseDetailDialogState();
}

class _CourseDetailDialogState extends State<_CourseDetailDialog> {
  late final TextEditingController _noteController = TextEditingController(
    text: widget.initialNote,
  );
  Timer? _debounce;
  late String _savedNote = widget.initialNote.trim();

  @override
  void dispose() {
    _debounce?.cancel();
    // 关闭时若还有未落盘的改动，补一次（保存是 fire-and-forget）。
    final pending = _noteController.text.trim();
    if (pending != _savedNote) {
      widget.onNoteChanged?.call(pending);
    }
    _noteController.dispose();
    super.dispose();
  }

  void _onNoteChanged(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      final text = _noteController.text.trim();
      if (text == _savedNote) return;
      _savedNote = text;
      widget.onNoteChanged?.call(text);
    });
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    final exam = widget.exam;
    final name = session?.name ?? exam?.name ?? '';
    final accent = session != null
        ? AppColors.pigmentFor(session.name).$2
        : AppColors.nowRed;

    final rows = <Widget>[];
    if (session != null) {
      final dayLabel = _weekdays[session.day - 1];
      final periodLabel = session.startPeriod == session.endPeriod
          ? '第${session.startPeriod}节'
          : '第${session.startPeriod}-${session.endPeriod}节';
      final timeLabel =
          '$dayLabel $periodLabel '
          '${PeriodTimes.startLabel(session.startPeriod)}–'
          '${PeriodTimes.endLabel(session.endPeriod)}';
      _addRow(rows, '地点', session.room);
      _addRow(rows, '教师', session.teacher);
      _addRow(rows, '时间', timeLabel);
      _addRow(rows, '周次', formatWeeks(session.weeks));
      _addRow(rows, '班级', session.className);
    } else if (exam != null) {
      _addRow(
        rows,
        '日期',
        '${exam.date.year}年${exam.date.month}月${exam.date.day}日',
      );
      final start = exam.startTime ?? '';
      final end = exam.endTime ?? '';
      final timeText = start.isEmpty
          ? ''
          : (end.isEmpty ? start : '$start–$end');
      _addRow(rows, '时间', timeText);
      _addRow(rows, '地点', exam.room);
      _addRow(rows, '考号', exam.seat);
      _addRow(rows, '类型', exam.type.isEmpty ? '考试' : exam.type);
    }

    return Dialog(
      backgroundColor: AppColors.surface,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: AppColors.line),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 430),
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            20,
            16,
            20,
            16 + MediaQuery.of(context).viewInsets.bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: accent,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      name,
                      style: TextStyle(
                        color: AppColors.ink,
                        fontSize: 18,
                        height: 1.28,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: Icon(
                      Icons.close_rounded,
                      size: 20,
                      color: AppColors.muted,
                    ),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints.tightFor(
                      width: 32,
                      height: 32,
                    ),
                  ),
                ],
              ),
              if (exam != null) ...[
                const SizedBox(height: 4),
                Text(
                  exam.type.trim().isEmpty ? '考试' : exam.type.trim(),
                  style: TextStyle(
                    color: AppColors.nowRed,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
              const SizedBox(height: 12),
              Container(height: 1, color: AppColors.line),
              const SizedBox(height: 10),
              ...rows,
              if (session != null) ...[
                const SizedBox(height: 6),
                Container(height: 1, color: AppColors.line),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Text(
                      '备注',
                      style: TextStyle(
                        color: AppColors.muted,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '仅本机保存',
                      style: TextStyle(color: AppColors.faint, fontSize: 9),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _noteController,
                  onChanged: _onNoteChanged,
                  minLines: 2,
                  maxLines: null,
                  maxLength: 200,
                  style: TextStyle(color: AppColors.ink, fontSize: 13, height: 1.4),
                  decoration: InputDecoration(
                    hintText: '添加备注，例如作业、复习或考试提醒…',
                    hintStyle: TextStyle(
                      color: AppColors.faint,
                      fontSize: 12,
                    ),
                    counterStyle: TextStyle(
                      color: AppColors.faint,
                      fontSize: 9,
                    ),
                  ),
                ),
              ],
              if (session != null &&
                  (widget.onEdit != null ||
                      widget.onDeleteThisCourse != null ||
                      widget.onDeleteThisWeek != null)) ...[
                const SizedBox(height: 4),
                Container(height: 1, color: AppColors.line),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    if (widget.onEdit != null)
                      OutlinedButton.icon(
                        onPressed: () {
                          Navigator.of(context).pop();
                          widget.onEdit!.call();
                        },
                        icon: const Icon(Icons.edit_outlined, size: 15),
                        label: const Text('编辑'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.campusBlue,
                          side: BorderSide(color: AppColors.line),
                          textStyle: const TextStyle(fontSize: 12),
                        ),
                      ),
                    if (widget.onDeleteThisCourse != null)
                      OutlinedButton.icon(
                        onPressed: () {
                          Navigator.of(context).pop();
                          widget.onDeleteThisCourse!.call();
                        },
                        icon: const Icon(Icons.delete_outline_rounded, size: 15),
                        label: const Text('删除本课程'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.danger,
                          side: BorderSide(
                            color: AppColors.danger.withValues(alpha: 0.4),
                          ),
                          textStyle: const TextStyle(fontSize: 12),
                        ),
                      ),
                    if (widget.onDeleteThisWeek != null)
                      TextButton.icon(
                        onPressed: () {
                          Navigator.of(context).pop();
                          widget.onDeleteThisWeek!.call();
                        },
                        icon: const Icon(Icons.event_busy_outlined, size: 15),
                        label: const Text('删除本周'),
                        style: TextButton.styleFrom(
                          foregroundColor: AppColors.danger,
                          textStyle: const TextStyle(fontSize: 12),
                        ),
                      ),
                  ],
                ),
              ],
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('完成'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _addRow(List<Widget> rows, String label, String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return;
    rows.add(_DetailRow(label: label, value: trimmed));
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 46,
            child: Text(
              label,
              style: TextStyle(
                color: AppColors.muted,
                fontSize: 11,
                fontWeight: FontWeight.w600,
                height: 1.5,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                color: AppColors.ink,
                fontSize: 13,
                height: 1.45,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
