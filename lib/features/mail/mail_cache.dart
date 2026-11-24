import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../core/network/mail_client.dart';
import '../../core/storage/account_scope.dart';
import '../../core/storage/account_snapshot_cache.dart';

/// 邮件列表本地缓存（按账号隔离）。
///
/// 邮件页进入时先用上次缓存「秒开」列表，再在后台刷新；缓存文件
/// `mail_cache.json` 位于 [AccountScope] 数据目录，文件名带当前学号，
/// 不同账号互不可见（其他账号读取不到旧数据）。
class MailCacheStore {
  MailCacheStore({List<File>? candidates, String? studentId})
    : _candidates =
          candidates ?? AccountScope.scopedFiles(_fileName, account: studentId);

  static const _fileName = 'mail_cache.json';

  /// 缓存最多保留的邮件条数。
  static const maxItems = 40;

  final List<File> _candidates;

  /// 读取缓存；文件缺失或损坏返回 null（绝不抛出）。
  Future<MailCacheData?> read() async {
    for (final file in _candidates) {
      try {
        if (!await file.exists()) continue;
        final decoded = jsonDecode(await file.readAsString());
        if (decoded is! Map) continue;
        return MailCacheData.fromJson(Map<String, dynamic>.from(decoded));
      } catch (error) {
        debugPrint('[mail] cache read failed at ${file.path}: $error');
      }
    }
    return null;
  }

  /// 写入缓存：按候选目录顺序逐个尝试，成功即返回。
  Future<void> write(MailCacheData data) async {
    final payload = jsonEncode(data.toJson());
    Object? lastError;
    for (final file in _candidates) {
      try {
        await file.parent.create(recursive: true);
        await file.writeAsString(payload, flush: true);
        return;
      } catch (error) {
        lastError = error;
        debugPrint('[mail] cache save failed at ${file.path}: $error');
      }
    }
    if (lastError != null) {
      debugPrint('[mail] cache no writable path: $lastError');
    }
  }

  /// 删除所有候选目录下的缓存文件（退出登录时清理）。
  Future<void> clear() async {
    for (final file in _candidates) {
      try {
        if (await file.exists()) await file.delete();
      } catch (error) {
        debugPrint('[mail] cache delete failed at ${file.path}: $error');
      }
    }
  }
}

/// 缓存数据：学生 id + 更新时间 + 邮件项（≤ [MailCacheStore.maxItems]）。
@immutable
class MailCacheData {
  const MailCacheData({
    required this.studentId,
    required this.updatedAt,
    required this.items,
  });

  final String studentId;
  final DateTime updatedAt;
  final List<MailSummary> items;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'studentId': studentId,
    'updatedAt': updatedAt.toIso8601String(),
    'items': [for (final item in items) mailSummaryToJson(item)],
  };

  factory MailCacheData.fromJson(Map<String, dynamic> json) {
    final studentId = '${json['studentId'] ?? ''}'.trim();
    final updatedAt =
        DateTime.tryParse('${json['updatedAt'] ?? ''}') ?? DateTime.now();
    final rawItems = json['items'];
    final items = <MailSummary>[];
    if (rawItems is List) {
      for (final entry in rawItems) {
        if (entry is! Map) continue;
        final item = mailSummaryFromJson(Map<String, dynamic>.from(entry));
        if (item != null) items.add(item);
      }
    }
    return MailCacheData(
      studentId: studentId,
      updatedAt: updatedAt,
      items: items,
    );
  }
}

/// [MailSummary] 序列化为 JSON（收到的日期用 ISO8601 字符串）。
Map<String, dynamic> mailSummaryToJson(MailSummary item) => <String, dynamic>{
  'id': item.id,
  'subject': item.subject,
  'from': item.from,
  'to': item.to,
  'receivedDate': item.receivedDate?.toIso8601String(),
  'read': item.read,
  'hasAttachment': item.hasAttachment,
};

/// 反序列化 [MailSummary]；id 为空视为无效项，返回 null。
MailSummary? mailSummaryFromJson(Map<String, dynamic> json) {
  final id = '${json['id'] ?? ''}'.trim();
  if (id.isEmpty) return null;
  final dateText = '${json['receivedDate'] ?? ''}';
  return MailSummary(
    id: id,
    subject: '${json['subject'] ?? ''}',
    from: '${json['from'] ?? ''}',
    to: '${json['to'] ?? ''}',
    receivedDate: dateText.isEmpty ? null : DateTime.tryParse(dateText),
    read: json['read'] == true,
    hasAttachment: json['hasAttachment'] == true,
  );
}

/// In-memory and disk snapshots of the most recent messages for each account.
class MailCache {
  MailCache({MailCacheStore? store}) : _testStore = store;

  static final MailCache instance = MailCache();

  final MailCacheStore? _testStore;
  final _snapshots = AccountSnapshotCache<MailCacheData>();
  String? _lastSavedAccount;

  MailCacheStore _store(String studentId) =>
      _testStore ?? MailCacheStore(studentId: studentId);

  Future<List<MailSummary>> loadFor(String studentId) async {
    final result = await _snapshots.load(studentId, () async {
      final data = await _store(studentId).read();
      return data?.studentId == studentId ? data : null;
    });
    return result?.items ?? const [];
  }

  List<MailSummary> itemsFor(String studentId) =>
      _snapshots.dataFor(studentId)?.items ?? const [];

  Future<void> save(String studentId, List<MailSummary> items) {
    _lastSavedAccount = studentId;
    final data = MailCacheData(
      studentId: studentId,
      updatedAt: DateTime.now(),
      items: List.unmodifiable(items.take(MailCacheStore.maxItems)),
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
