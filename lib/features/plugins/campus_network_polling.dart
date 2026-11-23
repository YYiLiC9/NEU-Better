import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'campus_network_controller.dart';
import 'campus_network_provider.dart';

/// Only the currently visible detail page or expanded home card needs polling.
class CampusNetworkPolling extends ConsumerStatefulWidget {
  const CampusNetworkPolling({
    super.key,
    required this.child,
    this.active = true,
  });

  final Widget child;
  final bool active;

  @override
  ConsumerState<CampusNetworkPolling> createState() =>
      _CampusNetworkPollingState();
}

class _CampusNetworkPollingState extends ConsumerState<CampusNetworkPolling>
    with WidgetsBindingObserver {
  ScrollPosition? _scroll;
  CampusNetworkController? _attached;
  bool _scheduled = false;
  bool _routeIsCurrent = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final scroll = Scrollable.maybeOf(context)?.position;
    if (scroll == _scroll) return;
    _scroll?.removeListener(_schedule);
    _scroll = scroll;
    _scroll?.addListener(_schedule);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_windowVisible) {
      _setAttached(null);
    } else {
      if (state == AppLifecycleState.resumed) {
        unawaited(_attached?.refresh());
      }
      _schedule();
    }
  }

  @override
  void didChangeMetrics() => _schedule();

  bool get _windowVisible => switch (WidgetsBinding.instance.lifecycleState) {
    AppLifecycleState.hidden ||
    AppLifecycleState.paused ||
    AppLifecycleState.detached => false,
    _ => true,
  };

  bool get _insideViewport {
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) return false;
    final RenderObject? viewport = RenderAbstractViewport.maybeOf(box);
    if (viewport is! RenderBox || !viewport.hasSize) return true;
    final bounds = MatrixUtils.transformRect(
      box.getTransformTo(viewport),
      Offset.zero & box.size,
    );
    return bounds.overlaps(Offset.zero & viewport.size);
  }

  void _schedule() {
    if (_scheduled) return;
    _scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      if (!mounted) return;
      final visible =
          widget.active && _windowVisible && _routeIsCurrent && _insideViewport;
      _setAttached(visible ? ref.read(campusNetworkControllerProvider) : null);
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  void _setAttached(CampusNetworkController? controller) {
    if (identical(_attached, controller)) return;
    _attached?.detach();
    _attached = controller;
    _attached?.attach();
  }

  @override
  Widget build(BuildContext context) {
    _routeIsCurrent = ModalRoute.isCurrentOf(context) ?? true;
    ref.watch(campusNetworkControllerProvider.notifier);
    _schedule();
    return widget.child;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _scroll?.removeListener(_schedule);
    _setAttached(null);
    super.dispose();
  }
}
