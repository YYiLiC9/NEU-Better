import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../core/network/mail_client.dart';
import '../../core/storage/account_scope.dart';

/// 邮件列表本地缓存（按账号隔离）。
///
/// 邮件页进入时先用上次缓存「秒开」列表，再在后台刷新；缓存文件
/// `mail_cache.json` 位于 [AccountScope] 数据目录，文件名带当前学号，
/// 不同账号互不可见（其他账号读取不到旧数据）。
class MailCacheStore {
  MailCacheStore({List<File>? candidates})
      : _candidates = candidates ?? AccountScope.scopedFiles(_fileName);

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

/// 全局邮件缓存单例：按 studentId 复用客户端并缓存列表。
///
/// 用途：
/// - 邮件页进入时先取 [itemsFor] 立即渲染，再后台刷新；
/// - 首页 / 轮询复用同一个 [MailClient]，避免重复换票；
/// - [save] 同步写盘，失败不影响界面（内部已吞掉异常）。
class MailCache {
  MailCache({MailCacheStore? store}) : _store = store ?? MailCacheStore();

  static final MailCache instance = MailCache();

  final MailCacheStore _store;

  String? _studentId;
  List<MailSummary> _items = const <MailSummary>[];
  MailClient? _client;

  /// 读取某账号的磁盘缓存并填充内存；其他账号不返回旧数据。
  Future<List<MailSummary>> loadFor(String studentId) async {
    if (_studentId != studentId) {
      _studentId = studentId;
      _items = const <MailSummary>[];
      _client = null;
    }
    final data = await _store.read();
    if (data == null || data.studentId != studentId) {
      _items = const <MailSummary>[];
      return _items;
    }
    _items = data.items.take(MailCacheStore.maxItems).toList(growable: false);
    return _items;
  }

  /// 同步取内存缓存；账号不匹配时返回空。
  List<MailSummary> itemsFor(String studentId) {
    if (_studentId != studentId) return const <MailSummary>[];
    return _items;
  }

  /// 保存列表到内存与磁盘（截断到 [MailCacheStore.maxItems]）。
  Future<void> save(String studentId, List<MailSummary> items) async {
    _studentId = studentId;
    _items = items.take(MailCacheStore.maxItems).toList(growable: false);
    await _store.write(
      MailCacheData(
        studentId: studentId,
        updatedAt: DateTime.now(),
        items: _items,
      ),
    );
  }

  /// 按 studentId 复用客户端；账号不匹配返回 null。
  MailClient? clientFor(String studentId) {
    if (_studentId == studentId) return _client;
    return null;
  }

  /// 记住当前账号的客户端，后续 [clientFor] 复用。
  void rememberClient(String studentId, MailClient client) {
    _studentId = studentId;
    _client = client;
  }

  /// 丢弃缓存的客户端（会话过期时调用，下次重新换票）。
  void forgetClient() {
    _client = null;
  }

  /// 退出登录：清空内存与磁盘缓存。
  Future<void> clear() async {
    _studentId = null;
    _items = const <MailSummary>[];
    _client = null;
    await _store.clear();
  }
}
