import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../core/storage/account_scope.dart';

/// 课程备注的独立持久化：与课表快照分开存 `course_notes.json`，
/// 这样同步课表/考试时不会覆盖用户手写的备注。文件按账号隔离。
///
/// 键 = `CourseSession.id`（课程 id），同一门课多次上课共享一条备注。
class CourseNoteStore {
  const CourseNoteStore({this.candidates});

  /// 测试可注入临时文件；生产用默认候选目录。
  final List<File>? candidates;

  static const _fileName = 'course_notes.json';

  List<File> get _primary =>
      candidates ?? AccountScope.scopedFiles(_fileName);

  List<File> get _legacy =>
      candidates != null ? const <File>[] : AccountScope.legacyFiles(_fileName);

  Future<Map<String, String>> read() async {
    for (final file in _primary) {
      final notes = await _tryRead(file);
      if (notes != null) return notes;
    }
    for (final file in _legacy) {
      final notes = await _tryRead(file);
      if (notes != null) {
        await save(notes);
        return notes;
      }
    }
    return <String, String>{};
  }

  Future<Map<String, String>?> _tryRead(File file) async {
    try {
      if (!await file.exists()) return null;
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
        if (notes.isNotEmpty) return notes;
      }
    } catch (error) {
      debugPrint('[notes] read failed at ${file.path}: $error');
    }
    return null;
  }

  Future<void> save(Map<String, String> notes) async {
    final cleaned = <String, String>{};
    notes.forEach((key, value) {
      if (key.trim().isNotEmpty && value.trim().isNotEmpty) {
        cleaned[key] = value;
      }
    });
    final payload = jsonEncode(cleaned);
    for (final file in _primary) {
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
