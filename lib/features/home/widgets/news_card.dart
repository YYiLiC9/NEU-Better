import 'package:flutter/material.dart';

import '../../../app/theme/app_theme.dart';
import '../../../core/models/news_models.dart';
import '../home_card_layout.dart';

/// 首页「新闻」内置插件卡：1×1 显示「闻」字徽标 + 名称；
/// 2×2 / 2×4 只展示最近的一条新闻（标题多行 + 摘要 + 来源日期），
/// 有未读时仅在右上角显示一个小红点。
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

  @override
  Widget build(BuildContext context) {
    final compact = size == HomeCardSize.s1x1;
    final card = Container(
      padding: EdgeInsets.all(compact ? 8 : 14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.line),
      ),
      child: compact ? _buildCompact() : _buildDetailedBody(size == HomeCardSize.s2x4),
    );
    final wrapped = Stack(
      children: [
        Positioned.fill(child: card),
        if (!compact && unread > 0)
          Positioned(
            top: 8,
            right: 8,
            child: Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                color: AppColors.nowRed,
                shape: BoxShape.circle,
              ),
            ),
          ),
      ],
    );
    final onOpen = this.onOpen;
    if (onOpen == null) return wrapped;
    return GestureDetector(
      onTap: onOpen,
      behavior: HitTestBehavior.opaque,
      child: wrapped,
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

  Widget _buildDetailedBody(bool wide) {
    final header = Row(
      children: [
        _buildGlyph(wide ? 20 : 18),
        const SizedBox(width: 7),
        Text(
          '新闻',
          style: TextStyle(
            fontSize: wide ? 14 : 13,
            fontWeight: FontWeight.w600,
            color: AppColors.ink,
          ),
        ),
      ],
    );

    final items = latest.take(1).toList(growable: false);
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

    final item = items.first;
    final meta =
        '${item.cname.isEmpty ? '新闻' : item.cname} · ${item.shortDate}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        header,
        SizedBox(height: wide ? 10 : 8),
        Text(
          item.title.isEmpty ? '(无标题)' : item.title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: wide ? 15 : 13.5,
            height: 1.32,
            fontWeight: FontWeight.w600,
            color: AppColors.ink,
          ),
        ),
        if (item.desc.isNotEmpty) ...[
          const SizedBox(height: 5),
          Text(
            item.desc,
            maxLines: wide ? 3 : 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: wide ? 10.5 : 9.8,
              height: 1.45,
              color: AppColors.muted,
            ),
          ),
        ],
        const SizedBox(height: 6),
        Text(
          meta,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: wide ? 10 : 9.5,
            color: AppColors.faint,
          ),
        ),
      ],
    );
  }
}
