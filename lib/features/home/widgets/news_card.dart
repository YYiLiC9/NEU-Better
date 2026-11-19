import 'package:flutter/material.dart';

import '../../../app/theme/app_theme.dart';
import '../../../core/models/news_models.dart';
import '../home_card_layout.dart';

/// 首页「新闻」内置插件卡：1×1 显示「闻」字徽标 + 名称；
/// 2×2 / 2×4 显示未读数量 + 最近两条标题（2×4 追加第二条摘要）。
class NewsCard extends StatelessWidget {
  const NewsCard({
    super.key,
    required this.size,
    required this.unread,
    required this.latest,
    this.onOpen,
  });

  final HomeCardSize size;
  final int unread;
  final List<NewsItem> latest;
  final VoidCallback? onOpen;

  String get _unreadText => unread > 0 ? '未读 $unread 条' : '暂无未读';

  @override
  Widget build(BuildContext context) {
    final compact = size == HomeCardSize.s1x1;
    final card = Container(
      padding: EdgeInsets.all(compact ? 8 : 16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.line),
      ),
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

  Widget _buildGlyph(double size) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppColors.campusBlue.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(size * 0.28),
      ),
      child: Text(
        '闻',
        style: TextStyle(
          fontSize: size * 0.62,
          height: 1,
          fontWeight: FontWeight.w700,
          color: AppColors.campusBlue,
        ),
      ),
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
          _buildGlyph(26),
          const SizedBox(height: 5),
          Text(
            '新闻',
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
    return LayoutBuilder(
      builder: (context, constraints) {
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
            child: _buildDetailedBody(wide),
          ),
        );
      },
    );
  }

  Widget _buildDetailedBody(bool wide) {
    final items = latest.take(2).toList(growable: false);
    final header = Row(
      children: [
        _buildGlyph(wide ? 20 : 18),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            '新闻',
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

    if (items.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          header,
          Expanded(
            child: Center(
              child: Text(
                '暂无新闻',
                style: TextStyle(fontSize: 12, color: AppColors.faint),
              ),
            ),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        header,
        for (final item in items) _newsBlock(item, wide: wide),
      ],
    );
  }

  Widget _newsBlock(NewsItem item, {required bool wide}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          item.title.isEmpty ? '(无标题)' : item.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: wide ? 13 : 12.5,
            fontWeight: FontWeight.w600,
            color: AppColors.ink,
          ),
        ),
        if (wide && item.desc.isNotEmpty) ...[
          const SizedBox(height: 2),
          Text(
            item.desc,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 10, color: AppColors.muted),
          ),
        ],
        const SizedBox(height: 2),
        Text(
          '${item.cname.isEmpty ? '新闻' : item.cname} · ${item.shortDate}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: wide ? 10 : 9.5, color: AppColors.muted),
        ),
      ],
    );
  }
}
