part of '../home_page.dart';

// ─────────────────────────── 首页问候条 ───────────────────────────

class _HomeMasthead extends StatelessWidget {
  const _HomeMasthead({
    required this.accountLabel,
    required this.week,
    required this.designMode,
    required this.onAdd,
    required this.onDone,
  });

  final String accountLabel;
  final int? week;
  final bool designMode;
  final VoidCallback onAdd;
  final VoidCallback onDone;

  String get _greeting {
    final hour = DateTime.now().hour;
    if (hour < 6) return '夜深了';
    if (hour < 9) return '早上好';
    if (hour < 12) return '上午好';
    if (hour < 14) return '中午好';
    if (hour < 18) return '下午好';
    return '晚上好';
  }

  String _dateLine(DateTime now) {
    const weekdays = <String>['一', '二', '三', '四', '五', '六', '日'];
    return '${now.month}月${now.day}日 周${weekdays[now.weekday - 1]}';
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final name = accountLabel.trim();
    final who = name.isEmpty ? '同学' : name;
    final meta = <String>[_dateLine(now)];
    if (week != null && week! > 0) meta.add('第 $week 周');
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$_greeting，$who',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 30,
                  height: 1.15,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.6,
                  color: AppColors.ink,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                meta.join(' · '),
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: AppColors.muted,
                ),
              ),
            ],
          ),
        ),
        if (designMode)
          TextButton(
            onPressed: onDone,
            style: TextButton.styleFrom(foregroundColor: AppColors.campusBlue),
            child: const Text('完成'),
          )
        else
          IconButton(
            onPressed: onAdd,
            tooltip: '添加卡片',
            icon: Icon(Icons.add_rounded, color: AppColors.ink),
          ),
      ],
    );
  }
}

// ─────────────────────────── 卡片网格 ───────────────────────────

class _HomeGrid extends StatefulWidget {
  const _HomeGrid({
    required this.cards,
    required this.unit,
    required this.columns,
    required this.designMode,
    required this.buildCard,
    required this.onReorder,
    required this.onResize,
    required this.onDelete,
    required this.onRequestEnterDesign,
    required this.onExitDesign,
  });

  final List<HomeCardLayout> cards;

  /// 桌面固定像素单元；手机传 null 走等比列。
  final double? unit;
  final int columns;
  final bool designMode;
  final Widget Function(String id) buildCard;
  final void Function(List<String> newOrder) onReorder;
  final void Function(String id, HomeCardSize size) onResize;
  final void Function(String id) onDelete;
  final VoidCallback onRequestEnterDesign;
  final VoidCallback onExitDesign;

  @override
  State<_HomeGrid> createState() => _HomeGridState();
}

class _HomeGridState extends State<_HomeGrid> {
  final _gridKey = GlobalKey();

  HomePackResult _pack(double width) => packHomeCards(
    widget.cards,
    width,
    unit: widget.unit,
    columns: widget.columns,
  );

  /// 实时拖动重排：手指移到某张卡范围内即把它插到该卡位置（顺序变化才回调）。
  void _handleDragMove(String id, Offset globalPosition) {
    final box = _gridKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return;
    final local = box.globalToLocal(globalPosition);
    final pack = _pack(box.size.width);
    int? targetIndex;
    for (final placed in pack.cards) {
      if (placed.id == id) continue;
      if (placed.rect.contains(local)) {
        targetIndex = placed.index;
        break;
      }
    }
    if (targetIndex == null) return;
    final ids = <String>[for (final card in widget.cards) card.id];
    final from = ids.indexOf(id);
    if (from < 0 || from == targetIndex) return;
    ids.removeAt(from);
    final to = targetIndex.clamp(0, ids.length);
    ids.insert(to, id);
    if (listEquals(ids, [for (final card in widget.cards) card.id])) return;
    widget.onReorder(ids);
  }

  void _handleDrop(String id, Offset globalPosition) {
    _handleDragMove(id, globalPosition);
  }

  final Map<String, HomeCardSize> _lastSizes = <String, HomeCardSize>{};

  /// 尺寸发生变化的那一帧不做位置/尺寸补间（否则大卡内容在 1×1 的小框里
  /// 被裁切会闪出「奇怪的东西」）；普通拖动重排仍保留 200ms 平滑动画。
  Widget _cardWidget(PlacedHomeCard placed) {
    final size = widget.cards.firstWhere((card) => card.id == placed.id).size;
    final prev = _lastSizes[placed.id];
    final duration = (prev == null || prev == size)
        ? const Duration(milliseconds: 200)
        : Duration.zero;
    _lastSizes[placed.id] = size;
    return AnimatedPositioned(
      key: ValueKey<String>('card-${placed.id}'),
      duration: duration,
      curve: Curves.easeOutCubic,
      left: placed.left,
      top: placed.top,
      width: placed.width,
      height: placed.height,
      child: _DraggableCard(
        id: placed.id,
        size: size,
        designMode: widget.designMode,
        onMove: (global) => _handleDragMove(placed.id, global),
        onDrop: (global) => _handleDrop(placed.id, global),
        onResize: widget.onResize,
        onDelete: widget.onDelete,
        onRequestEnterDesign: widget.onRequestEnterDesign,
        child: widget.buildCard(placed.id),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.cards.isEmpty) return const _HomeEmpty();
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : 1120.0;
        final pack = _pack(width);
        return Center(
          child: SizedBox(
            width: pack.usedWidth,
            height: pack.totalHeight,
            child: Stack(
              key: _gridKey,
              children: [
                if (widget.designMode)
                  Positioned.fill(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: widget.onExitDesign,
                    ),
                  ),
                for (final placed in pack.cards) _cardWidget(placed),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _DraggableCard extends StatefulWidget {
  const _DraggableCard({
    required this.id,
    required this.size,
    required this.designMode,
    required this.child,
    required this.onMove,
    required this.onDrop,
    required this.onResize,
    required this.onDelete,
    required this.onRequestEnterDesign,
  });

  final String id;
  final HomeCardSize size;
  final bool designMode;
  final Widget child;
  final ValueChanged<Offset> onMove;
  final ValueChanged<Offset> onDrop;
  final void Function(String id, HomeCardSize size) onResize;
  final ValueChanged<String> onDelete;
  final VoidCallback onRequestEnterDesign;

  @override
  State<_DraggableCard> createState() => _DraggableCardState();
}

class _DraggableCardState extends State<_DraggableCard> {
  Offset _dragDelta = Offset.zero;
  Offset _startBase = Offset.zero;
  bool _dragging = false;

  bool get _isAndroid =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// 桌面临时（非安卓）始终可长按拖动；安卓仅在设计模式内可拖。
  bool get _canDrag => !_isAndroid || widget.designMode;

  Future<void> _showSizeMenu(TapDownDetails details) async {
    final box = context.findRenderObject() as RenderBox?;
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (box == null || overlay == null) return;
    final origin = box.localToGlobal(details.localPosition);
    final rect = RelativeRect.fromRect(
      Rect.fromPoints(origin, origin),
      Offset.zero & overlay.size,
    );
    final result = await showMenu<String>(
      context: context,
      position: rect,
      items: const <PopupMenuEntry<String>>[
        PopupMenuItem<String>(value: 'small', child: Text('小 · 1×1')),
        PopupMenuItem<String>(value: 'medium', child: Text('中 · 2×2')),
        PopupMenuItem<String>(value: 'large', child: Text('大 · 2×4')),
        PopupMenuDivider(),
        PopupMenuItem<String>(value: 'delete', child: Text('删除卡片')),
      ],
    );
    if (result == null) return;
    if (result == 'delete') {
      widget.onDelete(widget.id);
      return;
    }
    final size = switch (result) {
      'small' => HomeCardSize.s1x1,
      'medium' => HomeCardSize.s2x2,
      _ => HomeCardSize.s2x4,
    };
    widget.onResize(widget.id, size);
  }

  @override
  Widget build(BuildContext context) {
    final showDesignAffordances = _isAndroid && widget.designMode;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onSecondaryTapDown: _isAndroid ? null : _showSizeMenu,
      onLongPressStart: (_) {
        if (_canDrag) {
          final rb = context.findRenderObject() as RenderBox?;
          _startBase = rb?.localToGlobal(Offset.zero) ?? Offset.zero;
          setState(() => _dragging = true);
        } else if (_isAndroid) {
          widget.onRequestEnterDesign();
        }
      },
      onLongPressMoveUpdate: (details) {
        if (!_dragging) return;
        // 手指总位移 = offsetFromOrigin。卡片网格在重排时自身也会移动到新格子
        // （base 位移）。漂浮位移必须扣掉这段 base 位移，否则卡片会“漂过头”。
        final rb = context.findRenderObject() as RenderBox?;
        final shift = rb == null
            ? Offset.zero
            : rb.localToGlobal(Offset.zero) - _startBase;
        setState(() => _dragDelta = details.offsetFromOrigin - shift);
        widget.onMove(details.globalPosition);
      },
      onLongPressEnd: (details) {
        if (!_dragging) return;
        setState(() {
          _dragging = false;
          _dragDelta = Offset.zero;
        });
        widget.onDrop(details.globalPosition);
      },
      child: Transform.translate(
        offset: _dragDelta,
        child: Transform.scale(
          scale: _dragging ? 1.03 : 1.0,
          child: Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(16),
            elevation: _dragging ? 10 : 0,
            shadowColor: AppColors.ink.withValues(alpha: 0.18),
            child: Stack(
              children: [
                Positioned.fill(
                  child: ClipRect(
                    child: AbsorbPointer(
                      // 设计模式下屏蔽卡片自身的点击（不得进入详情/二级页），
                      // 但外层的长按拖动、右下尺寸、右上删除仍可用。
                      absorbing: showDesignAffordances,
                      child: widget.child,
                    ),
                  ),
                ),
                // 设计态提示边框（可拖动暗示），随设计模式淡入淡出。
                Positioned.fill(
                  child: IgnorePointer(
                    child: AnimatedOpacity(
                      opacity: showDesignAffordances ? 1 : 0,
                      duration: const Duration(milliseconds: 200),
                      curve: Curves.easeOut,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: AppColors.campusBlue.withValues(alpha: 0.45),
                            width: 1.5,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                // 设计模式控件：用透明度 + 缩放平滑出现/消失，避免硬切。
                Positioned(
                  right: 2,
                  top: 2,
                  child: _DesignAffordance(
                    visible: showDesignAffordances,
                    child: _CornerButton(
                      icon: Icons.close_rounded,
                      color: AppColors.nowRed,
                      tooltip: '删除卡片',
                      onTap: () => widget.onDelete(widget.id),
                    ),
                  ),
                ),
                Positioned(
                  right: 2,
                  bottom: 2,
                  child: _DesignAffordance(
                    visible: showDesignAffordances,
                    child: _CornerButton(
                      icon: Icons.aspect_ratio_rounded,
                      color: AppColors.muted,
                      tooltip: '调整尺寸',
                      onTap: () => widget.onResize(
                        widget.id,
                        nextSizeOf(widget.size),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DesignAffordance extends StatelessWidget {
  const _DesignAffordance({required this.visible, required this.child});

  final bool visible;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      ignoring: !visible,
      child: AnimatedOpacity(
        opacity: visible ? 1 : 0,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        child: AnimatedScale(
          scale: visible ? 1 : 0.8,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          child: child,
        ),
      ),
    );
  }
}

class _CornerButton extends StatelessWidget {
  const _CornerButton({
    required this.icon,
    required this.color,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          margin: const EdgeInsets.all(4),
          width: 22,
          height: 22,
          decoration: BoxDecoration(
            color: AppColors.surface.withValues(alpha: 0.92),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: AppColors.line),
          ),
          child: Icon(icon, size: 14, color: color),
        ),
      ),
    );
  }
}

// ─────────────────────────── 卡片内容 ───────────────────────────

BoxDecoration _homeCardDecoration() => BoxDecoration(
  color: AppColors.surface,
  borderRadius: BorderRadius.circular(16),
  border: Border.all(color: AppColors.line),
);

String _formatKwh(double? value) {
  if (value == null) return '--';
  if (value == value.truncateToDouble()) return value.truncate().toString();
  return value.toStringAsFixed(1);
}

class _DormCard extends StatelessWidget {
  const _DormCard({required this.size, required this.prefs, required this.onOpen});

  final HomeCardSize size;
  final DormPrefs? prefs;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final reading = prefs?.lastReading;
    final low =
        reading != null &&
        prefs != null &&
        DormElectricityService.isLow(reading, prefs!.alertThreshold);
    final accent = low ? AppColors.nowRed : AppColors.campusBlue;
    final remain = _formatKwh(reading?.remainKwh);
    final roomText = (reading?.roomInfo.isNotEmpty ?? false)
        ? reading!.roomInfo
        : (prefs?.hasRoom == true ? '房间 ${prefs?.roomCode}' : '未设置房间码');

    Widget header({required double iconSize, required double titleSize}) => Row(
      children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: AppColors.campusBlue.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(9),
          ),
          child: Icon(
            Icons.account_balance_wallet_outlined,
            size: iconSize,
            color: AppColors.campusBlue,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            kBalanceFeatureName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: titleSize,
              fontWeight: FontWeight.w600,
              color: AppColors.ink,
            ),
          ),
        ),
        Icon(Icons.chevron_right_rounded, size: 16, color: AppColors.faint),
      ],
    );

    Widget body;
    switch (size) {
      case HomeCardSize.s1x1:
        body = FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.center,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.account_balance_wallet_outlined,
                  size: 18, color: AppColors.campusBlue),
              const SizedBox(height: 5),
              Text(
                kBalanceFeatureName,
                maxLines: 1,
                softWrap: false,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: AppColors.ink,
                ),
              ),
            ],
          ),
        );
        break;
      case HomeCardSize.s2x2:
        // 用 FittedBox 兜底：1×1→2×2 那一帧若高度还没铺满，内容等比缩放
        // 而不是溢出（否则会出现红/黄 overflow 行一闪）。
        body = FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 150,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                header(iconSize: 16, titleSize: 13),
                const SizedBox(height: 12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(
                      remain,
                      style: TextStyle(
                        fontSize: 30,
                        height: 1.05,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.5,
                        color: accent,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '度',
                      style: TextStyle(fontSize: 11, color: AppColors.muted),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  roomText,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 10, color: AppColors.muted),
                ),
              ],
            ),
          ),
        );
        break;
      case HomeCardSize.s2x4:
        body = LayoutBuilder(
          builder: (context, constraints) {
            // 卡片可用宽度大于设计宽度 320 时，直接用可用宽度，让右侧
            // 「查看详情」贴到右边缘；只有在更窄（手机）时才等比缩小。
            final designWidth = constraints.maxWidth > 320
                ? constraints.maxWidth
                : 320.0;
            return FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: designWidth,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    header(iconSize: 17, titleSize: 14),
                    const SizedBox(height: 10),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Text(
                          remain,
                          style: TextStyle(
                            fontSize: 44,
                            height: 1.0,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.8,
                            color: accent,
                            fontFeatures: const [
                              FontFeature.tabularFigures(),
                            ],
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '度',
                          style: TextStyle(
                            fontSize: 14,
                            color: AppColors.muted,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          '查看详情',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: AppColors.campusBlue,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      roomText,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 11, color: AppColors.muted),
                    ),
                    if (low) ...[
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.nowRed.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '电量偏低，建议尽快充值',
                          style: TextStyle(
                            fontSize: 11,
                            color: AppColors.nowRed,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            );
          },
        );
        break;
    }

    return GestureDetector(
      onTap: onOpen,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: EdgeInsets.all(size == HomeCardSize.s1x1 ? 8 : 16),
        decoration: _homeCardDecoration(),
        child: body,
      ),
    );
  }
}

class _MailCard extends StatelessWidget {
  const _MailCard({
    required this.size,
    required this.unread,
    required this.recent,
    this.onOpen,
  });

  final HomeCardSize size;
  final int unread;
  final List<MailSummary> recent;
  final VoidCallback? onOpen;

  String get _unreadText => unread > 0 ? '未读 $unread 封' : '无未读';

  @override
  Widget build(BuildContext context) {
    final compact = size == HomeCardSize.s1x1;
    final card = Container(
      padding: EdgeInsets.all(compact ? 8 : 16),
      decoration: _homeCardDecoration(),
      child: compact ? _buildCompact() : _buildDetailed(),
    );
    final onOpen = this.onOpen;
    if (onOpen == null) return card;
    return GestureDetector(
      onTap: onOpen,
      behavior: HitTestBehavior.opaque,
      child: card,
    );
  }

  Widget _buildCompact() {
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.mail_outline_rounded, size: 18, color: AppColors.muted),
          const SizedBox(height: 5),
          Text(
            '邮件',
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: AppColors.ink,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailed() {
    final wide = size == HomeCardSize.s2x4;
    final mails = recent.take(2).toList(growable: false);
    return LayoutBuilder(
      builder: (context, constraints) {
        // 2×2 与 2×4 共用同一套「主题 / 发件人·时间」两行版式。
        // 2×2 用 150×150 的固定设计方框 + BoxFit.contain：最终尺寸下等比铺满
        // 整张卡（上下自然铺开、不留大片空白），尺寸切换的中间帧（1×1→2×2）
        // 里自动缩小，避免 RenderFlex 溢出。
        // 2×4 设计框按实际内框等比放大 16% 留出文字放大（系统字号）余量，
        // contain 缩放后仍精确铺满整卡、右侧贴紧。
        final double designWidth;
        final double designHeight;
        if (wide && constraints.maxHeight > 0) {
          designHeight = constraints.maxHeight * 1.16;
          designWidth =
              constraints.maxWidth * (designHeight / constraints.maxHeight);
        } else {
          designWidth = wide ? constraints.maxWidth : 150.0;
          designHeight = wide ? 122.0 : 150.0;
        }
        return FittedBox(
          fit: BoxFit.contain,
          alignment: Alignment.center,
          child: SizedBox(
            width: designWidth,
            height: designHeight,
            child: _buildDetailedBody(wide, mails),
          ),
        );
      },
    );
  }

  Widget _buildDetailedBody(bool wide, List<MailSummary> mails) {
    final header = Row(
      children: [
        Icon(Icons.mail_outline_rounded, size: 18, color: AppColors.muted),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            '邮件',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: wide ? 14 : 13,
              fontWeight: FontWeight.w600,
              color: AppColors.ink,
            ),
          ),
        ),
        const SizedBox(width: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
          decoration: BoxDecoration(
            color: unread > 0
                ? AppColors.campusBlue.withValues(alpha: 0.12)
                : AppColors.line.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            _unreadText,
            style: TextStyle(
              fontSize: 9.5,
              fontWeight: FontWeight.w600,
              color: unread > 0 ? AppColors.campusBlue : AppColors.muted,
            ),
          ),
        ),
      ],
    );

    if (mails.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          header,
          Expanded(
            child: Center(
              child: Text(
                '暂无未读',
                style: TextStyle(fontSize: 12, color: AppColors.faint),
              ),
            ),
          ),
        ],
      );
    }

    if (wide) {
      // 2×4 高度充足：header 顶部、两封邮件在其中均匀铺开，避免下半大片空白。
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          header,
          for (final mail in mails) _mailBlock(mail, wide: true),
        ],
      );
    }

    // 2×2：header 顶部，邮件行在剩余高度内自然分布，避免下半大片空白。
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        header,
        for (final mail in mails) _mailBlock(mail, wide: false),
      ],
    );
  }

  Widget _mailBlock(MailSummary mail, {required bool wide}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          mail.subject.isEmpty ? '(无主题)' : mail.subject,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: wide ? 13 : 12.5,
            fontWeight: FontWeight.w600,
            color: AppColors.ink,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          _fromLine(mail),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: wide ? 10 : 9.5,
            color: AppColors.muted,
          ),
        ),
      ],
    );
  }

  String _fromLine(MailSummary mail) {
    final who = mail.from.isEmpty ? '未知发件人' : mail.from;
    final when = formatMailDate(mail.receivedDate);
    return when.isEmpty ? who : '$who · $when';
  }
}

class _PlaceholderCard extends StatelessWidget {
  const _PlaceholderCard({required this.id, required this.size});

  final String id;
  final HomeCardSize size;

  HomeCardInfo? get _info => homeCardInfo(id);

  @override
  Widget build(BuildContext context) {
    final info = _info;
    final name = info?.name ?? id;
    final icon = info?.icon ?? Icons.widgets_outlined;
    final compact = size == HomeCardSize.s1x1;
    const subtitle = '功能开发中，敬请期待';
    final card = Container(
      padding: EdgeInsets.all(compact ? 8 : 16),
      decoration: _homeCardDecoration(),
      child: compact
          ? FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.center,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 18, color: AppColors.muted),
                  const SizedBox(height: 5),
                  Text(
                    name,
                    maxLines: 1,
                    softWrap: false,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: AppColors.ink,
                    ),
                  ),
                ],
              ),
            )
          : FittedBox(
              // FittedBox 兜底：2×2/2×4 单元格在尺寸切换的中间帧里可能比内容
              // 小，等比缩放而不是让 Column 溢出（避免红/黄条闪烁）。
              fit: BoxFit.scaleDown,
              alignment: Alignment.topLeft,
              child: SizedBox(
                // 2×2 用 150 设计宽度（与余额中心一致），避免窄卡片里被整体
                // 缩小导致文字过小；2×4 用 320。
                width: size == HomeCardSize.s2x2 ? 150 : 320,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(icon, size: 22, color: AppColors.muted),
                    const SizedBox(height: 14),
                    Text(
                      name,
                      style: TextStyle(
                        fontSize: size == HomeCardSize.s2x2 ? 13 : 14,
                        fontWeight: FontWeight.w600,
                        color: AppColors.ink,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(fontSize: 10, color: AppColors.faint),
                    ),
                  ],
                ),
              ),
            ),
    );
    return card;
  }
}

// ─────────────────────────── 二级：余额中心 ───────────────────────────

class _HomeDormDetail extends StatelessWidget {
  const _HomeDormDetail({required this.onBack});

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 16, 0),
          child: Row(
            children: [
              IconButton(
                onPressed: onBack,
                icon: const Icon(Icons.arrow_back_rounded),
                color: AppColors.ink,
                tooltip: '返回首页',
              ),
              const SizedBox(width: 2),
              Text(
                kBalanceFeatureName,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: AppColors.ink,
                ),
              ),
            ],
          ),
        ),
        const Expanded(child: DormPowerPage(embedded: true)),
      ],
    );
  }
}

class _HomeEmpty extends StatelessWidget {
  const _HomeEmpty();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 16),
      decoration: _homeCardDecoration(),
      child: Column(
        children: [
          Icon(Icons.dashboard_customize_outlined, size: 30, color: AppColors.faint),
          const SizedBox(height: 8),
          Text(
            '首页卡片准备中',
            style: TextStyle(fontSize: 12, color: AppColors.muted),
          ),
        ],
      ),
    );
  }
}
