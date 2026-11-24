import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../core/storage/account_scope.dart';
import '../../core/storage/account_snapshot_cache.dart';
import 'timetable_models.dart';
import 'timetable_widget_service.dart';

/// 课表快照更新通知：自动同步完成后，课表页可据此从缓存重新加载。
final ValueNotifier<int> timetableChanged = ValueNotifier<int>(0);

/// Persists the last successfully synced timetable locally so the app can
/// display it immediately on the next launch, without hitting the school
/// system again. Files are scoped per account (multi-account isolation) and
/// stored in a persistent dir on Android so they survive an overwrite install.
class TimetableStore {
  const TimetableStore();

  static const _fileName = 'timetable.json';

  static final _snapshots = AccountSnapshotCache<TimetableData>();

  Future<TimetableData?> read({String? account}) {
    final key = AccountScope.scopedName(_fileName, account: account);
    final primary = AccountScope.scopedFiles(_fileName, account: account);
    return _snapshots.load(key, () async {
      for (final file in primary) {
        final data = await _tryRead(file);
        if (data != null) return data;
      }
      for (final file in AccountScope.legacyFiles(_fileName)) {
        final data = await _tryRead(file);
        if (data != null) {
          await _write(data, primary);
          return data;
        }
      }
      return null;
    });
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

  Future<void> save(TimetableData data, {String? account}) async {
    final key = AccountScope.scopedName(_fileName, account: account);
    final primary = AccountScope.scopedFiles(_fileName, account: account);
    final saved = _snapshots.save(key, data, () => _write(data, primary));
    if (key == AccountScope.scopedName(_fileName)) {
      timetableChanged.value++;
      await TimetableWidgetService.syncOfficial(data, account: account);
    }
    await saved;
  }

  Future<void> _write(TimetableData data, List<File> primary) async {
    final payload = jsonEncode(data.toJson());
    Object? lastError;
    for (final file in primary) {
      try {
        await file.parent.create(recursive: true);
        await file.writeAsString(payload, flush: true);
        debugPrint('[timetable] saved to ${file.path}');
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
