import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'timetable_models.dart';

/// 课表快照更新通知：自动同步完成后，课表页可据此从缓存重新加载。
final ValueNotifier<int> timetableChanged = ValueNotifier<int>(0);

/// Persists the last successfully synced timetable locally so the app can
/// display it immediately on the next launch, without hitting the school
/// system again.
class TimetableStore {
  const TimetableStore();

  static const _fileName = 'timetable.json';

  List<File> get _candidates {
    final separator = Platform.pathSeparator;
    final files = <File>[
      File(
        '${File(Platform.resolvedExecutable).parent.path}$separator'
        'data$separator$_fileName',
      ),
      File(
        '${Directory.current.path}$separator'
        'data$separator$_fileName',
      ),
      File(
        '${Directory.systemTemp.path}$separator'
        'NEU Better$separator$_fileName',
      ),
    ];
    final local = Platform.environment['LOCALAPPDATA'];
    if (local != null && local.isNotEmpty) {
      files.add(
        File(
          '$local$separator'
          'NEU Better$separator$_fileName',
        ),
      );
    }
    return files;
  }

  Future<TimetableData?> read() async {
    for (final file in _candidates) {
      try {
        if (!await file.exists()) continue;
        final decoded = jsonDecode(await file.readAsString());
        if (decoded is Map) {
          final data = TimetableData.fromJson(
            Map<String, dynamic>.from(decoded),
          );
          if (data.sessions.isNotEmpty) return data;
        }
      } catch (error) {
        debugPrint('[timetable] cache read failed at ${file.path}: $error');
      }
    }
    return null;
  }

  Future<void> save(TimetableData data) async {
    final payload = jsonEncode(data.toJson());
    Object? lastError;
    for (final file in _candidates) {
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
