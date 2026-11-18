import 'package:flutter/material.dart';

import '../../../app/theme/app_theme.dart';
import '../../../core/plugins/plugin_models.dart';
import '../home_card_layout.dart';

/// 首页上的「可选插件」卡片（原生渲染，无 WebView）。
/// 1×1 显示图标和名称；2×2/2×4 可显示详情，默认呈现简述。
class PluginCard extends StatelessWidget {
  const PluginCard({
    super.key,
    required this.size,
    required this.manifest,
    this.expandedContent,
    this.onTap,
  });

  final HomeCardSize size;
  final PluginManifest manifest;
  final Widget? expandedContent;
  final VoidCallback? onTap;

  IconData get _icon => resolvePluginIcon(manifest.icon);

  String? get _badge =>
      manifest.icon?.type == 'text' ? manifest.icon!.value : null;

  Widget _iconWidget(double size) {
    final badge = _badge;
    if (badge != null) {
      return Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: AppColors.campusBlue.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(size * 0.28),
        ),
        child: Text(
          badge,
          style: TextStyle(
            fontSize: size * 0.6,
            height: 1,
            fontWeight: FontWeight.w700,
            color: AppColors.campusBlue,
          ),
        ),
      );
    }
    return Icon(_icon, size: size, color: AppColors.campusBlue);
  }

  @override
  Widget build(BuildContext context) {
    final compact = size == HomeCardSize.s1x1;
    final title = manifest.cardTitle?.trim().isNotEmpty == true
        ? manifest.cardTitle!.trim()
        : manifest.name;
    final subtitle = manifest.cardSubtitle?.trim().isNotEmpty == true
        ? manifest.cardSubtitle!.trim()
        : manifest.description;
    final body = Container(
      padding: EdgeInsets.all(compact ? 8 : 16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.line),
      ),
      child: compact
          ? FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.center,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  _iconWidget(20),
                  const SizedBox(height: 5),
                  Text(
                    title,
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
              fit: BoxFit.scaleDown,
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: size == HomeCardSize.s2x2 ? 150 : 320,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _iconWidget(24),
                    const SizedBox(height: 12),
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: size == HomeCardSize.s2x2 ? 13 : 14,
                        fontWeight: FontWeight.w600,
                        color: AppColors.ink,
                      ),
                    ),
                    if (expandedContent != null) ...[
                      const SizedBox(height: 4),
                      expandedContent!,
                    ] else if (subtitle.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        subtitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 10, color: AppColors.muted),
                      ),
                    ],
                  ],
                ),
              ),
            ),
    );
    if (onTap == null) return body;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: body,
    );
  }
}

/// 把 manifest 里的 material 图标名映射为 [IconData]；未知走占位图标。
IconData resolvePluginIcon(PluginIcon? icon) {
  if (icon == null) return Icons.extension_outlined;
  switch (icon.type) {
    case 'material':
      return _materialIcons[icon.value] ?? Icons.extension_outlined;
    default:
      return Icons.extension_outlined;
  }
}

const Map<String, IconData> _materialIcons = <String, IconData>{
  'menu_book': Icons.menu_book_outlined,
  'book': Icons.book_outlined,
  'library_books': Icons.library_books_outlined,
  'notifications': Icons.notifications_none_rounded,
  'mail': Icons.mail_outline_rounded,
  'newspaper': Icons.newspaper_outlined,
  'feed': Icons.feed_outlined,
  'account_balance_wallet': Icons.account_balance_wallet_outlined,
  'search': Icons.search_rounded,
  'calendar_month': Icons.calendar_month_outlined,
  'map': Icons.map_outlined,
  'restaurant': Icons.restaurant_outlined,
  'sports_basketball': Icons.sports_basketball_outlined,
};
