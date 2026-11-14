import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../core/storage/account_scope.dart';
import 'timetable_overlay.dart';

/// 课表覆盖层（本地修改）变化通知：设置里「一键清除」或别处改动后，
/// 课表页据此重新读取 course_overrides.json 并重算展示数据。
final ValueNotifier<int> courseOverridesChanged = ValueNotifier<int>(0);

/// 课表本地修改（新增 / 修改 / 删除）的独立持久化：存 `course_overrides.json`，
/// 与官方快照 `timetable.json` 分开，这样「同步课表」只会覆盖官方快照，
/// 用户的修改作为覆盖层始终保留。文件按账号隔离。
class CourseOverrideStore {
  const CourseOverrideStore({this.candidates});

  /// 测试可注入临时文件；生产用默认候选目录。
  final List<File>? candidates;

  static const _fileName = 'course_overrides.json';

  List<File> get _primary =>
      candidates ?? AccountScope.scopedFiles(_fileName);

  List<File> get _legacy =>
      candidates != null ? const <File>[] : AccountScope.legacyFiles(_fileName);

  Future<TimetableOverlay> read() async {
    for (final file in _primary) {
      final overlay = await _tryRead(file);
      if (overlay != null) return overlay;
    }
    for (final file in _legacy) {
      final overlay = await _tryRead(file);
      if (overlay != null) {
        await save(overlay);
        return overlay;
      }
    }
    return TimetableOverlay.empty;
  }

  Future<TimetableOverlay?> _tryRead(File file) async {
    try {
      if (!await file.exists()) return null;
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is Map) {
        final overlay = TimetableOverlay.fromJson(
          Map<String, dynamic>.from(decoded),
        );
        if (!overlay.isEmpty) return overlay;
      }
    } catch (error) {
      debugPrint('[overrides] read failed at ${file.path}: $error');
    }
    return null;
  }

  Future<void> save(TimetableOverlay overlay) async {
    final payload = jsonEncode(overlay.toJson());
    Object? lastError;
    for (final file in _primary) {
      try {
        await file.parent.create(recursive: true);
        await file.writeAsString(payload, flush: true);
        courseOverridesChanged.value++;
        return;
      } catch (error) {
        lastError = error;
        debugPrint('[overrides] save failed at ${file.path}: $error');
      }
    }
    if (lastError != null) {
      debugPrint('[overrides] no writable path: $lastError');
    }
  }

  /// 清空全部课表修改（保留课程备注，备注在 course_notes.json）。
  Future<void> clear() => save(TimetableOverlay.empty);
}
