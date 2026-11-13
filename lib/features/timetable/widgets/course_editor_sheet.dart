part of '../timetable_page.dart';

/// 课程编辑器返回结果：合并后的课程 + 作用范围（仅编辑官方课程时有效）。
class CourseEditorResult {
  const CourseEditorResult({
    required this.session,
    required this.scope,
    this.week,
  });

  final CourseSession session;

  /// `all` 或 `week`（新增 / 编辑自建课程时恒为 `all`，忽略）。
  final String scope;
  final int? week;
}

/// 打开「新增 / 编辑课程」表单。
///
/// - [editing] 非空表示编辑；为 null 表示新增（用 [presetDay]/[presetPeriod] 定位格子）。
/// - [allWeeks] 可选周次全集（新增时通常是 1..totalWeeks；编辑官方时是官方已存在周）。
/// - [validate] 每次输入变化调用，返回冲突列表；有冲突时禁用保存。
Future<CourseEditorResult?> showCourseEditor(
  BuildContext context, {
  CourseSession? editing,
  int? presetDay,
  int? presetPeriod,
  int? presetWeek,
  required Set<int> allWeeks,
  required Future<List<CourseConflict>> Function(
    CourseSession draft,
    String scope,
    int? week,
  )
  validate,
}) {
  return showDialog<CourseEditorResult>(
    context: context,
    barrierDismissible: true,
    builder: (_) => _CourseEditorDialog(
      editing: editing,
      presetDay: presetDay,
      presetPeriod: presetPeriod,
      presetWeek: presetWeek,
      allWeeks: allWeeks,
      validate: validate,
    ),
  );
}

class _CourseEditorDialog extends StatefulWidget {
  const _CourseEditorDialog({
    this.editing,
    this.presetDay,
    this.presetPeriod,
    this.presetWeek,
    required this.allWeeks,
    required this.validate,
  });

  final CourseSession? editing;
  final int? presetDay;
  final int? presetPeriod;
  final int? presetWeek;
  final Set<int> allWeeks;
  final Future<List<CourseConflict>> Function(
    CourseSession draft,
    String scope,
    int? week,
  )
  validate;

  @override
  State<_CourseEditorDialog> createState() => _CourseEditorDialogState();
}

class _CourseEditorDialogState extends State<_CourseEditorDialog> {
  late final TextEditingController _name;
  late final TextEditingController _room;
  late final TextEditingController _teacher;
  late int _day;
  late int _start;
  late int _end;
  late Set<int> _weeks;
  late String _scope;

  List<CourseConflict> _conflicts = const [];
  bool _checking = false;
  int _gen = 0;
  Timer? _debounce;

  bool get _editingOfficial =>
      widget.editing != null && !widget.editing!.id.startsWith('user-');

  bool get _weeksEditable => !_editingOfficial;

  Set<int> get _weekUniverse {
    if (widget.allWeeks.isNotEmpty) return widget.allWeeks;
    final week = widget.presetWeek ?? 1;
    return {for (var i = 1; i <= week; i++) i};
  }

  @override
  void initState() {
    super.initState();
    final editing = widget.editing;
    _name = TextEditingController(text: editing?.name ?? '');
    _room = TextEditingController(text: editing?.room ?? '');
    _teacher = TextEditingController(text: editing?.teacher ?? '');
    _day = editing?.day ?? widget.presetDay ?? 1;
    _start = editing?.startPeriod ?? widget.presetPeriod ?? 1;
    _end = editing?.endPeriod ?? widget.presetPeriod ?? 1;
    final presetWeek = widget.presetWeek ?? 1;
    if (editing == null) {
      _scope = 'all';
      _weeks = {presetWeek};
    } else if (_editingOfficial) {
      _scope = 'week';
      _weeks = {presetWeek};
    } else {
      _scope = 'all';
      _weeks = {...editing.weeks};
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _revalidate());
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _name.dispose();
    _room.dispose();
    _teacher.dispose();
    super.dispose();
  }

  CourseSession _buildCandidate() {
    final Set<int> weeks;
    if (_editingOfficial) {
      weeks = _scope == 'all'
          ? {...widget.allWeeks}
          : {widget.presetWeek ?? 1};
    } else {
      weeks = {..._weeks};
    }
    final rawName = _name.text.trim();
    return CourseSession(
      id: widget.editing?.id ?? 'draft',
      name: rawName.isEmpty ? '未命名课程' : rawName,
      teacher: _teacher.text.trim(),
      room: _room.text.trim(),
      className: widget.editing?.className ?? '',
      day: _day,
      startPeriod: _start,
      endPeriod: _end,
      weeks: weeks,
    );
  }

  void _scheduleValidate() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 220), _revalidate);
  }

  Future<void> _revalidate() async {
    final gen = ++_gen;
    final candidate = _buildCandidate();
    setState(() => _checking = true);
    final result = await widget.validate(
      candidate,
      _editingOfficial ? _scope : 'all',
      _editingOfficial && _scope == 'week' ? widget.presetWeek : null,
    );
    if (!mounted || gen != _gen) return;
    setState(() {
      _conflicts = result;
      _checking = false;
    });
  }

  bool get _basicValid {
    if (_name.text.trim().isEmpty) return false;
    if (_start > _end) return false;
    if (_weeksEditable && _weeks.isEmpty) return false;
    return true;
  }

  bool get _canSave => _basicValid && !_checking && _conflicts.isEmpty;

  void _save() {
    if (!_canSave) return;
    Navigator.of(context).pop(
      CourseEditorResult(
        session: _buildCandidate(),
        scope: _editingOfficial ? _scope : 'all',
        week: _editingOfficial && _scope == 'week' ? widget.presetWeek : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final weeks = _weekUniverse.toList()..sort();
    return Dialog(
      backgroundColor: AppColors.surface,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: AppColors.line),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
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
                children: [
                  Text(
                    widget.editing == null ? '新增课程' : '编辑课程',
                    style: TextStyle(
                      color: AppColors.ink,
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Spacer(),
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
              const SizedBox(height: 6),
              if (_weeksEditable) ...[
                _label('上课周次（至少选 1 周）'),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final week in weeks)
                      _WeekChip(
                        week: week,
                        active: _weeks.contains(week),
                        onTap: () {
                          setState(() {
                            if (_weeks.contains(week)) {
                              _weeks.remove(week);
                            } else {
                              _weeks.add(week);
                            }
                          });
                          _scheduleValidate();
                        },
                      ),
                  ],
                ),
                const SizedBox(height: 14),
              ] else ...[
                _label('作用范围'),
                const SizedBox(height: 8),
                Row(
                  children: [
                    _ScopeOption(
                      label: '所有周',
                      active: _scope == 'all',
                      onTap: () {
                        setState(() => _scope = 'all');
                        _scheduleValidate();
                      },
                    ),
                    const SizedBox(width: 10),
                    _ScopeOption(
                      label: '仅本周（第${widget.presetWeek ?? 1}周）',
                      active: _scope == 'week',
                      onTap: () {
                        setState(() => _scope = 'week');
                        _scheduleValidate();
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 14),
              ],
              _label('课程名 *'),
              const SizedBox(height: 6),
              _textField(
                _name,
                hint: '如：高级算法',
                onChanged: (_) {
                  setState(() {});
                  _scheduleValidate();
                },
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _label('地点'),
                        const SizedBox(height: 6),
                        _textField(_room, hint: '选填'),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _label('教师'),
                        const SizedBox(height: 6),
                        _textField(_teacher, hint: '选填'),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  _periodDropdown('开始节', _start, (value) {
                    setState(() {
                      _start = value;
                      if (_end < _start) _end = _start;
                    });
                    _scheduleValidate();
                  }),
                  const SizedBox(width: 10),
                  _periodDropdown('结束节', _end, (value) {
                    setState(() => _end = value);
                    _scheduleValidate();
                  }),
                ],
              ),
              const SizedBox(height: 12),
              _conflictPanel(),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('取消'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: _canSave ? _save : null,
                    child: const Text('保存'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _label(String text) {
    return Text(
      text,
      style: TextStyle(
        color: AppColors.muted,
        fontSize: 11,
        fontWeight: FontWeight.w600,
      ),
    );
  }

  Widget _textField(
    TextEditingController controller, {
    required String hint,
    ValueChanged<String>? onChanged,
  }) {
    return TextField(
      controller: controller,
      onChanged: onChanged,
      style: TextStyle(color: AppColors.ink, fontSize: 13),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: AppColors.faint, fontSize: 12),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 11,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: AppColors.line),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: AppColors.campusBlue),
        ),
      ),
    );
  }

  Widget _periodDropdown(String label, int value, ValueChanged<int> onChanged) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _label(label),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              color: AppColors.canvas,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.line),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<int>(
                value: value,
                isExpanded: true,
                isDense: true,
                style: TextStyle(color: AppColors.ink, fontSize: 13),
                items: [
                  for (var period = 1; period <= 12; period++)
                    DropdownMenuItem<int>(
                      value: period,
                      child: Text('第$period节'),
                    ),
                ],
                onChanged: (next) {
                  if (next != null) onChanged(next);
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _conflictPanel() {
    if (_checking) {
      return Row(
        children: [
          SizedBox(
            width: 12,
            height: 12,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: AppColors.muted,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '正在检测冲突…',
            style: TextStyle(color: AppColors.muted, fontSize: 11),
          ),
        ],
      );
    }
    if (_conflicts.isEmpty) {
      return Row(
        children: [
          Icon(Icons.check_circle_outline_rounded, size: 14, color: AppColors.campusBlue),
          const SizedBox(width: 6),
          Text(
            '没有时间冲突',
            style: TextStyle(color: AppColors.muted, fontSize: 11),
          ),
        ],
      );
    }
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      decoration: BoxDecoration(
        color: AppColors.danger.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.danger.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.error_outline_rounded, size: 14, color: AppColors.danger),
              const SizedBox(width: 6),
              Text(
                '存在冲突，无法保存',
                style: TextStyle(
                  color: AppColors.danger,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          for (final conflict in _conflicts)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                '• ${conflict.describe()}',
                style: TextStyle(color: AppColors.danger, fontSize: 10.5, height: 1.35),
              ),
            ),
        ],
      ),
    );
  }
}

class _WeekChip extends StatelessWidget {
  const _WeekChip({
    required this.week,
    required this.active,
    required this.onTap,
  });

  final int week;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
        decoration: BoxDecoration(
          color: active ? AppColors.campusBlue : AppColors.canvas,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: active ? AppColors.campusBlue : AppColors.line,
          ),
        ),
        child: Text(
          '第$week周',
          style: TextStyle(
            color: active ? Colors.white : AppColors.muted,
            fontSize: 11,
            fontWeight: active ? FontWeight.w600 : FontWeight.w500,
          ),
        ),
      ),
    );
  }
}

class _ScopeOption extends StatelessWidget {
  const _ScopeOption({
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
        duration: const Duration(milliseconds: 140),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: active
              ? AppColors.campusBlue.withValues(
                  alpha: AppColors.isDark ? 0.18 : 0.08,
                )
              : AppColors.canvas,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: active ? AppColors.campusBlue : AppColors.line,
            width: 1.4,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: active ? AppColors.ink : AppColors.muted,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
