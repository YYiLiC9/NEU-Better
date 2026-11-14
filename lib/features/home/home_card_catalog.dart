import 'package:flutter/material.dart';

/// 一张可添加到首页的卡片的静态信息（名称 / 简述 / 图标）。
@immutable
class HomeCardInfo {
  const HomeCardInfo({
    required this.id,
    required this.name,
    required this.description,
    required this.icon,
  });

  final String id;
  final String name;
  final String description;
  final IconData icon;
}

/// 全部可用卡片（首页可从「卡片库」按此清单添加）。
const List<HomeCardInfo> homeCardCatalog = <HomeCardInfo>[
  HomeCardInfo(
    id: 'dorm',
    name: '余额中心',
    description: '电费余额、网费余额与校园卡余额（逐步接入）',
    icon: Icons.account_balance_wallet_outlined,
  ),
  HomeCardInfo(
    id: 'notify',
    name: '通知',
    description: '校园通知与公告（即将上线）',
    icon: Icons.notifications_none_rounded,
  ),
  HomeCardInfo(
    id: 'mail',
    name: '邮件',
    description: '校园邮箱（即将上线）',
    icon: Icons.mail_outline_rounded,
  ),
];

/// 按 id 取卡片信息；未知 id 返回 null。
HomeCardInfo? homeCardInfo(String id) {
  for (final info in homeCardCatalog) {
    if (info.id == id) return info;
  }
  return null;
}

/// 允许出现在首页的卡片 id，由 [homeCardCatalog] 派生。
final List<String> knownHomeCardIds = <String>[
  for (final info in homeCardCatalog) info.id,
];
