import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../core/network/notification_models.dart';
import '../../core/storage/account_scope.dart';

/// 把 [AppNotification] 序列化为可持久化的 JSON。
Map<String, dynamic> appNotificationToJson(AppNotification item) {
  return <String, dynamic>{
    'logId': item.logId,
    'read': item.read,
    'time': item.time?.toIso8601String(),
    'title': item.title,
    'content': item.content,
    'sourceName': item.sourceName,
    'url': item.url,
    'typeName': item.typeName,
  };
}

/// 从 JSON 还原一条通知；缺少有效 `logId` 时返回 null。
AppNotification? appNotificationFromJson(Map<String, dynamic> json) {
  final logId = _asInt(json['logId']);
  if (logId == null) return null;
  return AppNotification(
    logId: logId,
    read: json['read'] == true,
    time: _parseDate(json['time']),
    title: (json['title'] ?? '').toString(),
    content: (json['content'] ?? '').toString(),
    sourceName: (json['sourceName'] ?? '').toString(),
    url: (json['url'] ?? '').toString(),
    typeName: (json['typeName'] ?? '').toString(),
  );
}

/// 通知列表本地缓存内容（按账号隔离）。
@immutable
class NotificationCacheData {
  const NotificationCacheData({
    required this.studentId,
    required this.fetchedAt,
    required this.total,
    required this.noRead,
    required this.items,
  });

  final String studentId;
  final DateTime fetchedAt;
  final int total;
  final int noRead;
  final List<AppNotification> items;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'studentId': studentId,
        'fetchedAt': fetchedAt.toIso8601String(),
        'total': total,
        'noRead': noRead,
        'items': [for (final item in items) appNotificationToJson(item)],
      };

  static NotificationCacheData? fromJson(Map<String, dynamic> json) {
    final studentId = (json['studentId'] ?? '').toString();
    if (studentId.isEmpty) return null;
    final rawItems = json['items'];
    final items = <AppNotification>[];
    if (rawItems is List) {
      for (final raw in rawItems) {
        if (raw is Map) {
          final item = appNotificationFromJson(Map<String, dynamic>.from(raw));
          if (item != null) items.add(item);
        }
      }
    }
    return NotificationCacheData(
      studentId: studentId,
      fetchedAt: _parseDate(json['fetchedAt']) ?? DateTime.fromMillisecondsSinceEpoch(0),
      total: _asInt(json['total']) ?? items.length,
      noRead: _asInt(json['noRead']) ?? 0,
      items: items,
    );
  }
}

/// 通知列表缓存的文件读写（默认按账号目录隔离）。
class NotificationCacheStore {
  NotificationCacheStore({List<File>? candidates})
      : _candidates = candidates ?? AccountScope.scopedFiles(_fileName);

  static const _fileName = 'notification_cache.json';

  /// 最多缓存 30 条，避免文件无限增长。
  static const maxItems = 30;

  final List<File> _candidates;

  Future<NotificationCacheData?> read() async {
    for (final file in _candidates) {
      try {
        if (!await file.exists()) continue;
        final decoded = jsonDecode(await file.readAsString());
        if (decoded is! Map) continue;
        final data = NotificationCacheData.fromJson(
          Map<String, dynamic>.from(decoded),
        );
        if (data != null) return data;
      } catch (error) {
        debugPrint('[notify] cache read failed at ${file.path}: $error');
      }
    }
    return null;
  }

  Future<void> write(NotificationCacheData data) async {
    final payload = jsonEncode(data.toJson());
    Object? lastError;
    for (final file in _candidates) {
      try {
        await file.parent.create(recursive: true);
        await file.writeAsString(payload, flush: true);
        return;
      } catch (error) {
        lastError = error;
        debugPrint('[notify] cache save failed at ${file.path}: $error');
      }
    }
    if (lastError != null) {
      debugPrint('[notify] cache no writable path: $lastError');
    }
  }

  Future<void> clear() async {
    for (final file in _candidates) {
      try {
        if (await file.exists()) await file.delete();
      } catch (error) {
        debugPrint('[notify] cache clear failed at ${file.path}: $error');
      }
    }
  }
}

/// 通知列表缓存单例：进程内缓存一份，磁盘按账号隔离保存。
///
/// 供通知页首帧秒开与 `home_page` 摘要顺带写入。
class NotificationCache {
  NotificationCache({NotificationCacheStore? store})
      : _store = store ?? NotificationCacheStore();

  static final NotificationCache instance = NotificationCache();

  final NotificationCacheStore _store;

  NotificationCacheData? _data;

  /// 同步返回内存中属于该账号的缓存（可能为 null）。
  NotificationCacheData? dataFor(String studentId) {
    final data = _data;
    if (data == null || data.studentId != studentId) return null;
    return data;
  }

  /// 同步返回内存中属于该账号的缓存条目。
  List<AppNotification> itemsFor(String studentId) {
    return dataFor(studentId)?.items ?? const <AppNotification>[];
  }

  /// 从磁盘加载；账号不匹配时视为没有缓存。
  Future<NotificationCacheData?> loadFor(String studentId) async {
    final data = await _store.read();
    if (data == null || data.studentId != studentId) {
      _data = null;
      return null;
    }
    _data = data;
    return data;
  }

  /// 保存列表（最多 [NotificationCacheStore.maxItems] 条）。
  Future<void> save(
    String studentId,
    List<AppNotification> items,
    int total,
    int noRead,
  ) async {
    final data = NotificationCacheData(
      studentId: studentId,
      fetchedAt: DateTime.now(),
      total: total,
      noRead: noRead,
      items: items
          .take(NotificationCacheStore.maxItems)
          .toList(growable: false),
    );
    _data = data;
    await _store.write(data);
  }

  Future<void> clear() async {
    _data = null;
    await _store.clear();
  }
}

DateTime? _parseDate(Object? value) {
  if (value == null) return null;
  final text = value.toString().trim();
  if (text.isEmpty) return null;
  return DateTime.tryParse(text.replaceFirst(' ', 'T'));
}

int? _asInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value.trim());
  return null;
}
