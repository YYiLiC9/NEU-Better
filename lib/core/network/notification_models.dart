import 'dart:convert';

import 'package:flutter/foundation.dart';

/// 一条校园通知（来自 personal.neu.edu.cn 消息中心）。
@immutable
class AppNotification {
  const AppNotification({
    required this.logId,
    required this.read,
    this.time,
    required this.title,
    required this.content,
    required this.sourceName,
    this.url = '',
    this.typeName = '',
  });

  final int logId;
  final bool read;
  final DateTime? time;
  final String title;
  final String content;
  final String sourceName;
  final String url;
  final String typeName;

  String get preview => content.replaceAll(RegExp(r'\s+'), ' ').trim();
}

/// 未读 / 总数统计。
@immutable
class NotificationCounts {
  const NotificationCounts({required this.noRead, required this.total});

  final int noRead;
  final int total;

  static const empty = NotificationCounts(noRead: 0, total: 0);
}

/// 解析 `/portal/ucs/frontend/msg/countData`。
NotificationCounts parseCounts(Object? payload) {
  final root = _asMap(payload);
  final data = _asMap(root['d']);
  final noRead = _asInt(data['noReadCount']);
  final total = _asInt(data['count']) ?? _asInt(data['total']);
  return NotificationCounts(
    noRead: noRead ?? 0,
    total: total ?? noRead ?? 0,
  );
}

/// 解析 `/portal/ucs/frontend/msg/index` 的返回。
List<AppNotification> parseIndex(Object? payload) {
  final root = _asMap(payload);
  final data = _asMap(root['d']);
  final rawList = data['list'];
  if (rawList is! List) return const <AppNotification>[];
  final result = <AppNotification>[];
  for (final item in rawList) {
    final map = _asMap(item);
    final logId = _asInt(map['log_id']);
    if (logId == null) continue;
    final sourceName = (map['source_name'] ?? map['ucs_type_name'] ?? '')
        .toString()
        .trim();
    result.add(
      AppNotification(
        logId: logId,
        read: map['has_read'] == true || _asInt(map['has_read']) == 1,
        time: _parseDate(map['time']),
        title: (map['title'] ?? '').toString().trim(),
        content: (map['content'] ?? '').toString(),
        sourceName: sourceName,
        url: (map['url'] ?? '').toString().trim(),
        typeName: (map['ucs_type_name'] ?? '').toString().trim(),
      ),
    );
  }
  return result;
}

DateTime? _parseDate(Object? value) {
  if (value == null) return null;
  final text = value.toString().trim();
  if (text.isEmpty) return null;
  return DateTime.tryParse(text.replaceFirst(' ', 'T'));
}

Map<String, dynamic> _asMap(Object? value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) return Map<String, dynamic>.from(value);
  return const <String, dynamic>{};
}

int? _asInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value.trim());
  return null;
}

/// 便于测试/调试：把动态 payload 归一化为 JSON 文本。
String debugJson(Object? payload) {
  try {
    return jsonEncode(payload);
  } catch (_) {
    return '$payload';
  }
}
