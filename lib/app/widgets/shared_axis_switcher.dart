import 'package:flutter/material.dart';

/// 两段式（先退出、再进入）的水平平移转场。
///
/// 与普通 AnimatedSwitcher 的交叉淡入不同，这里把时间轴分成两段：
/// 前 45% 只显示旧页面滑出，后 55% 只显示新页面滑入，因此新旧页面的
/// 文字不会在同一时刻叠在一起。`forward=true` 表示进入下一层（旧页向左、
/// 新页从右来）；`forward=false` 表示返回上一层（方向相反）。
class SharedAxisSwitcher extends StatefulWidget {
  const SharedAxisSwitcher({
    super.key,
    required this.child,
    required this.forward,
    this.duration = const Duration(milliseconds: 320),
  });

  final Widget child;
  final bool forward;
  final Duration duration;

  @override
  State<SharedAxisSwitcher> createState() => _SharedAxisSwitcherState();
}

class _SharedAxisSwitcherState extends State<SharedAxisSwitcher>
    with SingleTickerProviderStateMixin {
  static const double _slide = 0.06;
  static const double _split = 0.45;

  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: widget.duration,
    value: 1,
  );
  late Widget _current = widget.child;
  Widget? _previous;
  bool _forward = true;

  @override
  void initState() {
    super.initState();
    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed &&
          mounted &&
          _previous != null) {
        // 动画结束后释放旧页面，避免它继续占用状态或拦截语义。
        setState(() => _previous = null);
      }
    });
  }

  @override
  void didUpdateWidget(covariant SharedAxisSwitcher oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (identical(oldWidget.child, widget.child)) return;

    // 页面数据可以在转场途中更新，仍沿用当前动画的方向和进度。
    _current = widget.child;
    if (oldWidget.child.key != widget.child.key) {
      _forward = widget.forward;
      _previous = oldWidget.child;
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
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final t = _controller.value;
        Widget page;
        double opacity;
        double dx;
        final exiting = _previous != null && t < _split;
        if (exiting) {
          final u = Curves.easeInCubic.transform((t / _split).clamp(0.0, 1.0));
          page = _previous!;
          opacity = 1.0 - u;
          dx = (_forward ? -_slide : _slide) * u;
        } else if (_previous != null) {
          final raw = ((t - _split) / (1 - _split)).clamp(0.0, 1.0);
          final u = Curves.easeOutCubic.transform(raw);
          page = _current;
          opacity = u;
          dx = (_forward ? _slide : -_slide) * (1.0 - u);
        } else {
          page = _current;
          opacity = 1;
          dx = 0;
        }
        return ClipRect(
          child: Stack(
            fit: StackFit.expand,
            alignment: Alignment.topLeft,
            children: [
              FractionalTranslation(
                translation: Offset(dx, 0),
                child: IgnorePointer(
                  ignoring: exiting,
                  child: Opacity(
                    opacity: opacity.clamp(0.0, 1.0),
                    child: RepaintBoundary(child: page),
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
