import 'package:flutter/material.dart';

import 'plugin_models.dart';

/// 把插件清单里的图标描述解析成 [IconData]（text 类型由调用方用文字徽标渲染）。
///
/// 放在 core 层，供首页卡片、插件库、通知设置等多处复用，避免 feature 间互相依赖。
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
  'router': Icons.router_rounded,
};
