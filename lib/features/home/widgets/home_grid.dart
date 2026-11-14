part of '../home_page.dart';

// ─────────────────────────── 首页问候条 ───────────────────────────

class _HomeMasthead extends StatelessWidget {
  const _HomeMasthead({required this.accountLabel, required this.week});

  final String accountLabel;
  final int? week;

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
    return Column(
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
    );
  }
}

// ─────────────────────────── 卡片网格 ───────────────────────────

class _HomeGrid extends StatefulWidget {
  const _HomeGrid({
    required this.cards,
    required this.buildCard,
    required this.onReorder,
    required this.onResize,
    required this.onResetLayout,
  });

  final List<HomeCardLayout> cards;
  final Widget Function(String id) buildCard;
  final void Function(List<String> newOrder) onReorder;
  final void Function(String id, HomeCardSize size) onResize;
  final VoidCallback onResetLayout;

  @override
  State<_HomeGrid> createState() => _HomeGridState();
}

class _HomeGridState extends State<_HomeGrid> {
  final _gridKey = GlobalKey();

  void _handleDrop(String id, Offset globalPosition) {
    final box = _gridKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return;
    final local = box.globalToLocal(globalPosition);
    final pack = packHomeCards(widget.cards, box.size.width);
    int? targetIndex;
    for (final placed in pack.cards) {
      if (placed.id == id) continue;
      if (placed.rect.contains(local)) {
        targetIndex = placed.index;
        break;
      }
    }
    final ids = <String>[for (final card in widget.cards) card.id];
    final from = ids.indexOf(id);
    if (from < 0) return;
    ids.removeAt(from);
    var to = targetIndex ?? ids.length;
    if (to < 0) to = 0;
    if (to > ids.length) to = ids.length;
    ids.insert(to, id);
    widget.onReorder(ids);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.cards.isEmpty) return const _HomeEmpty();

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : 1120.0;
        final pack = packHomeCards(widget.cards, width);
        return SizedBox(
          height: pack.totalHeight,
          child: Stack(
            key: _gridKey,
            children: [
              for (final placed in pack.cards)
                AnimatedPositioned(
                  key: ValueKey<String>(placed.id),
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeOutCubic,
                  left: placed.left,
                  top: placed.top,
                  width: placed.width,
                  height: placed.height,
                  child: _DraggableCard(
                    id: placed.id,
                    size: widget.cards
                        .firstWhere((card) => card.id == placed.id)
                        .size,
                    onDrop: (global) => _handleDrop(placed.id, global),
                    onResize: widget.onResize,
                    onResetLayout: widget.onResetLayout,
                    child: widget.buildCard(placed.id),
                  ),
                ),
            ],
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
    required this.child,
    required this.onDrop,
    required this.onResize,
    required this.onResetLayout,
  });

  final String id;
  final HomeCardSize size;
  final Widget child;
  final ValueChanged<Offset> onDrop;
  final void Function(String id, HomeCardSize size) onResize;
  final VoidCallback onResetLayout;

  @override
  State<_DraggableCard> createState() => _DraggableCardState();
}

class _DraggableCardState extends State<_DraggableCard> {
  Offset _dragDelta = Offset.zero;
  bool _dragging = false;

  HomeCardSize get _nextSize {
    switch (widget.size) {
      case HomeCardSize.s1x1:
        return HomeCardSize.s2x2;
      case HomeCardSize.s2x2:
        return HomeCardSize.s2x4;
      case HomeCardSize.s2x4:
        return HomeCardSize.s1x1;
    }
  }

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
        PopupMenuItem<String>(value: 'reset', child: Text('重置布局')),
      ],
    );
    if (result == null) return;
    if (result == 'reset') {
      widget.onResetLayout();
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
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onSecondaryTapDown: _showSizeMenu,
      onLongPressStart: (_) => setState(() => _dragging = true),
      onLongPressMoveUpdate: (details) =>
          setState(() => _dragDelta = details.offsetFromOrigin),
      onLongPressEnd: (details) {
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
                Positioned.fill(child: widget.child),
                Positioned(
                  right: 4,
                  bottom: 4,
                  child: Tooltip(
                    message: '调整尺寸',
                    child: GestureDetector(
                      onTap: () => widget.onResize(widget.id, _nextSize),
                      behavior: HitTestBehavior.opaque,
                      child: Container(
                        width: 18,
                        height: 18,
                        decoration: BoxDecoration(
                          color: AppColors.surface.withValues(alpha: 0.9),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: AppColors.line),
                        ),
                        child: Icon(
                          Icons.open_in_full_rounded,
                          size: 10,
                          color: AppColors.muted,
                        ),
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
            Icons.electric_bolt_rounded,
            size: iconSize,
            color: AppColors.campusBlue,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            '寝室用电',
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
          alignment: Alignment.topLeft,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.electric_bolt_rounded, size: 18, color: accent),
              const SizedBox(height: 4),
              Text(
                remain == '--' ? '寝室用电' : '$remain 度',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.ink,
                ),
              ),
            ],
          ),
        );
        break;
      case HomeCardSize.s2x2:
        body = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            header(iconSize: 16, titleSize: 13),
            const Spacer(),
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
                Text('度', style: TextStyle(fontSize: 11, color: AppColors.muted)),
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
        );
        break;
      case HomeCardSize.s2x4:
        body = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            header(iconSize: 17, titleSize: 14),
            const Spacer(),
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
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                const SizedBox(width: 6),
                Text('度', style: TextStyle(fontSize: 14, color: AppColors.muted)),
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
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.nowRed.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '电量偏低，建议尽快充值',
                  style: TextStyle(fontSize: 11, color: AppColors.nowRed),
                ),
              ),
            ],
          ],
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

class _PlaceholderCard extends StatelessWidget {
  const _PlaceholderCard({required this.id, required this.size});

  final String id;
  final HomeCardSize size;

  String get _name => id == 'mail' ? '邮件' : '通知';
  IconData get _icon => id == 'mail'
      ? Icons.mail_outline_rounded
      : Icons.notifications_none_rounded;

  @override
  Widget build(BuildContext context) {
    final compact = size == HomeCardSize.s1x1;
    return Container(
      padding: EdgeInsets.all(compact ? 8 : 16),
      decoration: _homeCardDecoration(),
      child: compact
          ? FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.topLeft,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(_icon, size: 18, color: AppColors.muted),
                  const SizedBox(height: 4),
                  Text(
                    _name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppColors.ink,
                    ),
                  ),
                ],
              ),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(_icon, size: 22, color: AppColors.muted),
                const Spacer(),
                Text(
                  _name,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.ink,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '功能开发中，敬请期待',
                  style: TextStyle(fontSize: 10, color: AppColors.faint),
                ),
              ],
            ),
    );
  }
}

// ─────────────────────────── 二级：寝室用电 ───────────────────────────

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
                '寝室用电',
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
