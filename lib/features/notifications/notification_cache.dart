import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../core/network/notification_models.dart';
import '../../core/storage/account_scope.dart';
import '../../core/storage/account_snapshot_cache.dart';

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
      fetchedAt:
          _parseDate(json['fetchedAt']) ??
          DateTime.fromMillisecondsSinceEpoch(0),
      total: _asInt(json['total']) ?? items.length,
      noRead: _asInt(json['noRead']) ?? 0,
      items: items,
    );
  }
}

/// 通知列表缓存的文件读写（默认按账号目录隔离）。
class NotificationCacheStore {
  NotificationCacheStore({List<File>? candidates, String? studentId})
    : _candidates =
          candidates ?? AccountScope.scopedFiles(_fileName, account: studentId);

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

/// Latest notification snapshots, with an explicit account for each disk operation.
class NotificationCache {
  NotificationCache({NotificationCacheStore? store}) : _testStore = store;

  static final NotificationCache instance = NotificationCache();

  final NotificationCacheStore? _testStore;
  final _snapshots = AccountSnapshotCache<NotificationCacheData>();
  String? _lastSavedAccount;

  NotificationCacheStore _store(String studentId) =>
      _testStore ?? NotificationCacheStore(studentId: studentId);

  NotificationCacheData? dataFor(String studentId) =>
      _snapshots.dataFor(studentId);

  List<AppNotification> itemsFor(String studentId) =>
      dataFor(studentId)?.items ?? const [];

  Future<NotificationCacheData?> loadFor(String studentId) =>
      _snapshots.load(studentId, () async {
        final data = await _store(studentId).read();
        return data?.studentId == studentId ? data : null;
      });

  Future<void> save(
    String studentId,
    List<AppNotification> items,
    int total,
    int noRead,
  ) {
    _lastSavedAccount = studentId;
    final data = NotificationCacheData(
      studentId: studentId,
      fetchedAt: DateTime.now(),
      total: total,
      noRead: noRead,
      items: List.unmodifiable(items.take(NotificationCacheStore.maxItems)),
    );
    return _snapshots.save(
      studentId,
      data,
      () => _store(studentId).write(data),
    );
  }

  Future<void> clear([String? studentId]) async {
    final account = studentId ?? _lastSavedAccount;
    if (account == null) {
      await _testStore?.clear();
      return;
    }
    await _snapshots.clear(account, () => _store(account).clear());
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
