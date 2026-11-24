import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../core/storage/account_scope.dart';

/// 邮件轮询状态（按账号持久化到 `mail_poll_state.json`）：
/// - `knownIds`：已见过的邮件 id（用于「同一封只通知一次」，≤ [maxKnownIds]）；
/// - `initialized`：是否已建立基线（首次运行/首次开启时先记录基线，不通知旧邮件）；
/// - `lastCheckAt`：上次成功检查时间（界面回到前台时用于节流）。
class MailPollState {
  MailPollState({List<File>? candidates})
      : _candidates = candidates ?? AccountScope.scopedFiles(_fileName);

  static const _fileName = 'mail_poll_state.json';

  /// knownIds 最多保留的条数（保留最近的，避免文件无限增大）。
  static const maxKnownIds = 200;

  final List<File> _candidates;

  final List<String> _knownIds = <String>[];
  bool _initialized = false;
  DateTime? _lastCheckAt;

  List<String> get knownIds => List<String>.unmodifiable(_knownIds);
  bool get initialized => _initialized;
  DateTime? get lastCheckAt => _lastCheckAt;

  Future<void> load() async {
    for (final file in _candidates) {
      try {
        if (!await file.exists()) continue;
        final decoded = jsonDecode(await file.readAsString());
        if (decoded is! Map) continue;
        final rawIds = decoded['knownIds'];
        _knownIds.clear();
        if (rawIds is List) {
          for (final entry in rawIds) {
            if (entry is String && entry.isNotEmpty) _knownIds.add(entry);
          }
        }
        _trim();
        _initialized = decoded['initialized'] == true;
        _lastCheckAt = DateTime.tryParse('${decoded['lastCheckAt'] ?? ''}');
        return;
      } catch (error) {
        debugPrint('[mail] poll state read failed at ${file.path}: $error');
      }
    }
  }

  Future<void> save() async {
    final payload = jsonEncode(<String, dynamic>{
      'knownIds': _knownIds,
      'initialized': _initialized,
      'lastCheckAt': _lastCheckAt?.toIso8601String(),
    });
    Object? lastError;
    for (final file in _candidates) {
      try {
        await file.parent.create(recursive: true);
        await file.writeAsString(payload, flush: true);
        return;
      } catch (error) {
        lastError = error;
        debugPrint('[mail] poll state save failed at ${file.path}: $error');
      }
    }
    if (lastError != null) {
      debugPrint('[mail] poll state no writable path: $lastError');
    }
  }

  /// 建立基线：记录当前全部 id，标记已初始化（不通知）。
  void setBaseline(Iterable<String> ids) {
    _knownIds.clear();
    for (final id in ids) {
      if (id.isNotEmpty) _knownIds.add(id);
    }
    _trim();
    _initialized = true;
  }

  /// 返回本次新出现、此前未记录过的 id（并加入 knownIds）。
  List<String> takeNew(Iterable<String> ids) {
    final fresh = <String>[];
    for (final id in ids) {
      if (id.isEmpty) continue;
      if (!_knownIds.contains(id)) {
        _knownIds.add(id);
        fresh.add(id);
      }
    }
    _trim();
    return fresh;
  }

  void setLastCheckAt(DateTime time) {
    _lastCheckAt = time;
  }

  /// 只保留最近的 [maxKnownIds] 条。
  void _trim() {
    if (_knownIds.length > maxKnownIds) {
      _knownIds.removeRange(0, _knownIds.length - maxKnownIds);
    }
  }
}
