import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'timetable_overlay.dart';

/// 课表覆盖层（本地修改）变化通知：设置里「一键清除」或别处改动后，
/// 课表页据此重新读取 course_overrides.json 并重算展示数据。
final ValueNotifier<int> courseOverridesChanged = ValueNotifier<int>(0);

/// 课表本地修改（新增 / 修改 / 删除）的独立持久化：存 `course_overrides.json`，
/// 与官方快照 `timetable.json` 分开，这样「同步课表」只会覆盖官方快照，
/// 用户的修改作为覆盖层始终保留。候选目录策略仿 [CourseNoteStore]。
class CourseOverrideStore {
  const CourseOverrideStore({this.candidates});

  /// 测试可注入临时文件；生产用默认候选目录。
  final List<File>? candidates;

  static const _fileName = 'course_overrides.json';

  List<File> get _files {
    final injected = candidates;
    if (injected != null) return injected;
    final separator = Platform.pathSeparator;
    final files = <File>[
      File(
        '${File(Platform.resolvedExecutable).parent.path}$separator'
        'data$separator$_fileName',
      ),
      File('${Directory.current.path}$separator' 'data$separator$_fileName'),
      File(
        '${Directory.systemTemp.path}$separator'
        'NEU Better$separator$_fileName',
      ),
    ];
    final local = Platform.environment['LOCALAPPDATA'];
    if (local != null && local.isNotEmpty) {
      files.add(
        File('$local$separator' 'NEU Better$separator$_fileName'),
      );
    }
    return files;
  }

  Future<TimetableOverlay> read() async {
    for (final file in _files) {
      try {
        if (!await file.exists()) continue;
        final decoded = jsonDecode(await file.readAsString());
        if (decoded is Map) {
          return TimetableOverlay.fromJson(
            Map<String, dynamic>.from(decoded),
          );
        }
      } catch (error) {
        debugPrint('[overrides] read failed at ${file.path}: $error');
      }
    }
    return TimetableOverlay.empty;
  }

  Future<void> save(TimetableOverlay overlay) async {
    final payload = jsonEncode(overlay.toJson());
    Object? lastError;
    for (final file in _files) {
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
