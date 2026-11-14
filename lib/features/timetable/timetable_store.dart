import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../core/storage/account_scope.dart';
import 'timetable_models.dart';

/// 课表快照更新通知：自动同步完成后，课表页可据此从缓存重新加载。
final ValueNotifier<int> timetableChanged = ValueNotifier<int>(0);

/// Persists the last successfully synced timetable locally so the app can
/// display it immediately on the next launch, without hitting the school
/// system again. Files are scoped per account (multi-account isolation) and
/// stored in a persistent dir on Android so they survive an overwrite install.
class TimetableStore {
  const TimetableStore();

  static const _fileName = 'timetable.json';

  List<File> get _primary => AccountScope.scopedFiles(_fileName);

  List<File> get _legacy => AccountScope.legacyFiles(_fileName);

  Future<TimetableData?> read() async {
    for (final file in _primary) {
      final data = await _tryRead(file);
      if (data != null) return data;
    }
    // 兼容旧版本未加账号后缀的缓存：读到后迁移到当前账号文件。
    for (final file in _legacy) {
      final data = await _tryRead(file);
      if (data != null) {
        await save(data);
        return data;
      }
    }
    return null;
  }

  Future<TimetableData?> _tryRead(File file) async {
    try {
      if (!await file.exists()) return null;
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is Map) {
        final data = TimetableData.fromJson(Map<String, dynamic>.from(decoded));
        if (data.sessions.isNotEmpty) return data;
      }
    } catch (error) {
      debugPrint('[timetable] cache read failed at ${file.path}: $error');
    }
    return null;
  }

  Future<void> save(TimetableData data) async {
    final payload = jsonEncode(data.toJson());
    Object? lastError;
    for (final file in _primary) {
      try {
        await file.parent.create(recursive: true);
        await file.writeAsString(payload, flush: true);
        debugPrint('[timetable] saved to ${file.path}');
        timetableChanged.value++;
        return;
      } catch (error) {
        lastError = error;
        debugPrint('[timetable] cache save failed at ${file.path}: $error');
      }
    }
    if (lastError != null) {
      debugPrint('[timetable] no writable cache path: $lastError');
    }
  }
}
