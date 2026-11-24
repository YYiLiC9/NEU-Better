import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../core/storage/account_scope.dart';
import 'notification_models.dart';

/// 通知的本地状态（按账号持久化）：
/// - `lastNoRead`：上次已知未读数，用于判断“新增未读”。
/// - `notifiedIds`：已经发过系统通知的 log_id，避免重复提醒。
/// - `localReadIds`：服务端标记已读失败时，本地兜底记录。
class NotificationStore {
  NotificationStore({List<File>? candidates, String? studentId})
    : _candidates =
          candidates ?? AccountScope.scopedFiles(_fileName, account: studentId);

  static const _fileName = 'notification_state.json';

  final List<File> _candidates;

  int _lastNoRead = 0;
  final Set<int> _notifiedIds = <int>{};
  final Set<int> _localReadIds = <int>{};

  int get lastNoRead => _lastNoRead;
  Set<int> get notifiedIds => Set<int>.unmodifiable(_notifiedIds);
  Set<int> get localReadIds => Set<int>.unmodifiable(_localReadIds);

  Future<void> load() async {
    for (final file in _candidates) {
      try {
        if (!await file.exists()) continue;
        final decoded = jsonDecode(await file.readAsString());
        if (decoded is! Map) continue;
        _lastNoRead = _asInt(decoded['lastNoRead']) ?? 0;
        _notifiedIds
          ..clear()
          ..addAll(_asIntSet(decoded['notifiedIds']));
        _localReadIds
          ..clear()
          ..addAll(_asIntSet(decoded['localReadIds']));
        return;
      } catch (error) {
        debugPrint('[notify] state read failed at ${file.path}: $error');
      }
    }
  }

  Future<void> _pendingSave = Future.value();

  Future<void> save() => _pendingSave = _pendingSave.then((_) => _save());

  Future<void> _save() async {
    final payload = jsonEncode(<String, dynamic>{
      'lastNoRead': _lastNoRead,
      'notifiedIds': _notifiedIds.toList(growable: false),
      'localReadIds': _localReadIds.toList(growable: false),
    });
    Object? lastError;
    for (final file in _candidates) {
      try {
        await file.parent.create(recursive: true);
        await file.writeAsString(payload, flush: true);
        return;
      } catch (error) {
        lastError = error;
        debugPrint('[notify] state save failed at ${file.path}: $error');
      }
    }
    if (lastError != null) {
      debugPrint('[notify] state no writable path: $lastError');
    }
  }

  bool isRead(int logId, {required bool serverRead}) {
    return serverRead || _localReadIds.contains(logId);
  }

  Future<void> markLocalRead(int logId) => markLocallyRead([logId]);

  Future<void> markLocallyRead(Iterable<int> logIds) async {
    final before = _localReadIds.length;
    _localReadIds.addAll(logIds);
    if (_localReadIds.length != before) await save();
  }

  void setBaseline(int noRead) {
    _lastNoRead = noRead < 0 ? 0 : noRead;
  }

  /// 是否应该弹系统通知：未读变多，且这些 id 之前没提醒过。
  /// 返回新出现且未提醒过的通知 id 列表。
  List<int> takeNewUnnotified(Iterable<int> unreadIds) {
    final fresh = <int>[];
    for (final id in unreadIds) {
      if (_notifiedIds.add(id)) fresh.add(id);
    }
    return fresh;
  }

  bool get hasNewUnread => _lastNoRead >= 0;
}

Set<int> _asIntSet(Object? value) {
  if (value is! List) return <int>{};
  final result = <int>{};
  for (final item in value) {
    final parsed = _asInt(item);
    if (parsed != null) result.add(parsed);
  }
  return result;
}

int? _asInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value.trim());
  return null;
}

AppNotification applyLocalNotificationRead(
  AppNotification item,
  NotificationStore? store,
) {
  if (item.read || store?.isRead(item.logId, serverRead: false) != true) {
    return item;
  }
  return AppNotification(
    logId: item.logId,
    read: true,
    time: item.time,
    title: item.title,
    content: item.content,
    sourceName: item.sourceName,
    url: item.url,
    typeName: item.typeName,
  );
}
