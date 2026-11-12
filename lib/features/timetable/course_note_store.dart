import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// 课程备注的独立持久化：与课表快照分开存 `course_notes.json`，
/// 这样同步课表/考试时不会覆盖用户手写的备注。
///
/// 键 = `CourseSession.id`（课程 id），同一门课多次上课共享一条备注。
class CourseNoteStore {
  const CourseNoteStore({this.candidates});

  /// 测试可注入临时文件；生产用默认候选目录。
  final List<File>? candidates;

  static const _fileName = 'course_notes.json';

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

  Future<Map<String, String>> read() async {
    for (final file in _files) {
      try {
        if (!await file.exists()) continue;
        final decoded = jsonDecode(await file.readAsString());
        if (decoded is Map) {
          final notes = <String, String>{};
          decoded.forEach((key, value) {
            final id = key?.toString() ?? '';
            final note = value?.toString() ?? '';
            if (id.trim().isNotEmpty && note.trim().isNotEmpty) {
              notes[id] = note;
            }
          });
          return notes;
        }
      } catch (error) {
        debugPrint('[notes] read failed at ${file.path}: $error');
      }
    }
    return <String, String>{};
  }

  Future<void> save(Map<String, String> notes) async {
    final cleaned = <String, String>{};
    notes.forEach((key, value) {
      if (key.trim().isNotEmpty && value.trim().isNotEmpty) {
        cleaned[key] = value;
      }
    });
    final payload = jsonEncode(cleaned);
    for (final file in _files) {
      try {
        await file.parent.create(recursive: true);
        await file.writeAsString(payload, flush: true);
        return;
      } catch (error) {
        debugPrint('[notes] save failed at ${file.path}: $error');
      }
    }
  }
}
