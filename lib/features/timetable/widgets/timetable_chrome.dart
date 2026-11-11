part of '../timetable_page.dart';

class _WeekStepper extends StatelessWidget {
  const _WeekStepper({
    required this.week,
    required this.totalWeeks,
    required this.onChanged,
    this.dense = false,
  });

  final int week;
  final int totalWeeks;
  final ValueChanged<int> onChanged;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: dense ? 34 : 36,
      padding: EdgeInsets.symmetric(horizontal: dense ? 2 : 4),
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
            icon: Icon(Icons.chevron_left_rounded, size: dense ? 16 : 18),
            padding: EdgeInsets.zero,
            constraints: BoxConstraints.tightFor(
              width: dense ? 24 : 28,
              height: dense ? 26 : 28,
            ),
          ),
          SizedBox(
            width: dense ? 44 : 58,
            child: Text(
              '第 $week 周',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.ink,
                fontSize: dense ? 10.5 : 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          IconButton(
            tooltip: '下一周',
            onPressed: week >= totalWeeks ? null : () => onChanged(week + 1),
            icon: Icon(Icons.chevron_right_rounded, size: dense ? 16 : 18),
            padding: EdgeInsets.zero,
            constraints: BoxConstraints.tightFor(
              width: dense ? 24 : 28,
              height: dense ? 26 : 28,
            ),
          ),
        ],
      ),
    );
  }
}

class _ViewToggle extends StatelessWidget {
  const _ViewToggle({
    required this.weekView,
    required this.onChanged,
    this.dense = false,
  });

  final bool weekView;
  final ValueChanged<bool> onChanged;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: dense ? 34 : 36,
      padding: EdgeInsets.all(dense ? 2 : 3),
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
            dense: dense,
          ),
          _ToggleItem(
            label: '日视图',
            active: !weekView,
            onTap: () => onChanged(false),
            dense: dense,
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
    this.dense = false,
  });

  final String label;
  final bool active;
  final VoidCallback onTap;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: EdgeInsets.symmetric(
          horizontal: dense ? 7 : 10,
          vertical: dense ? 5 : 6,
        ),
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
            fontSize: dense ? 9.5 : 10,
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
