import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neu_better_pro/features/timetable/course_override_store.dart';
import 'package:neu_better_pro/features/timetable/timetable_models.dart';
import 'package:neu_better_pro/features/timetable/timetable_overlay.dart';
import 'package:neu_better_pro/features/timetable/timetable_page.dart'
    show showCourseEditor;

CourseSession _session({
  required String id,
  required String name,
  int day = 1,
  int start = 1,
  int end = 2,
  Set<int>? weeks,
}) {
  return CourseSession(
    id: id,
    name: name,
    teacher: '老师',
    room: 'A101',
    className: '班级',
    day: day,
    startPeriod: start,
    endPeriod: end,
    weeks: weeks ?? {1, 2, 3},
  );
}

TimetableData _data(List<CourseSession> sessions) {
  return TimetableData(
    termName: '测试学期',
    totalWeeks: 16,
    sessions: sessions,
    isSample: false,
    currentWeek: 1,
  );
}

void main() {
  group('applyOverlay', () {
    final official = _data([
      _session(id: 's1', name: '高级算法', day: 1, start: 1, end: 2),
      _session(id: 's2', name: '随机过程', day: 2, start: 3, end: 4),
    ]);

    test('删除全部周会整条移除', () {
      final overlay = TimetableOverlay.empty.delete(
        targetKey: '随机过程|2|3|4',
        scope: 'all',
      );
      final merged = applyOverlay(official, overlay);
      expect(merged.sessions.map((s) => s.name), ['高级算法']);
    });

    test('仅删除某一周会减少周次但不整条移除', () {
      final overlay = TimetableOverlay.empty.delete(
        targetKey: '随机过程|2|3|4',
        scope: 'week',
        week: 1,
      );
      final merged = applyOverlay(official, overlay);
      final s2 = merged.sessions.firstWhere((s) => s.name == '随机过程');
      expect(s2.weeks, {2, 3});
    });

    test('新增课程被追加到结果', () {
      final overlay = TimetableOverlay.empty.addCourse(
        _session(id: 'user-1', name: '自建课', day: 5, start: 9, end: 10),
      );
      final merged = applyOverlay(official, overlay);
      expect(merged.sessions.map((s) => s.name), contains('自建课'));
      expect(merged.sessions.length, 3);
    });

    test('仅本周修改只替换该周，剩余周保留原课程', () {
      final overlay = TimetableOverlay.empty.modify(
        targetKey: '高级算法|1|1|2',
        scope: 'week',
        week: 2,
        replacement: _session(
          id: 's1',
          name: '高级算法（改）',
          day: 1,
          start: 1,
          end: 2,
          weeks: {2},
        ),
      );
      final merged = applyOverlay(official, overlay);
      final originals = merged.sessions.where((s) => s.name == '高级算法');
      final replacements = merged.sessions.where(
        (s) => s.name == '高级算法（改）',
      );
      expect(originals.single.weeks, {1, 3});
      expect(replacements.single.weeks, {2});
    });

    test('所有周修改整条替换', () {      final overlay = TimetableOverlay.empty.modify(
        targetKey: '高级算法|1|1|2',
        scope: 'all',
        replacement: _session(
          id: 's1',
          name: '高级算法（全改）',
          day: 1,
          start: 1,
          end: 2,
          weeks: {1, 2, 3},
        ),
      );
      final merged = applyOverlay(official, overlay);
      expect(merged.sessions.where((s) => s.name == '高级算法'), isEmpty);
      expect(merged.sessions.where((s) => s.name == '高级算法（全改）').length, 1);
    });

    test('孤立修改（targetKey 不在官方）被保留但不影响结果', () {
      final overlay = TimetableOverlay.empty.delete(
        targetKey: '不存在的课|3|1|2',
        scope: 'all',
      );
      final merged = applyOverlay(official, overlay);
      expect(merged.sessions.length, official.sessions.length);
      expect(overlay.deleted.length, 1);
    });
  });

  group('TimetableOverlay JSON 往返', () {
    test('新增/修改/删除均可恢复', () {
      final overlay = TimetableOverlay.empty
          .addCourse(_session(id: 'user-9', name: '新增课', day: 6, start: 5, end: 6))
          .modify(
            targetKey: '高级算法|1|1|2',
            scope: 'week',
            week: 3,
            replacement: _session(id: 's1', name: '高级算法B'),
          )
          .delete(targetKey: '随机过程|2|3|4', scope: 'all');
      final restored = TimetableOverlay.fromJson(overlay.toJson());
      expect(restored.added.single.name, '新增课');
      expect(restored.modified.single.targetKey, '高级算法|1|1|2');
      expect(restored.modified.single.week, 3);
      expect(restored.deleted.single.targetKey, '随机过程|2|3|4');
      expect(restored.count, 3);
    });

    test('空 JSON 得到空覆盖层', () {
      final restored = TimetableOverlay.fromJson(const {});
      expect(restored.isEmpty, isTrue);
    });
  });

  group('findConflicts', () {
    test('同一天节次重叠且周次相交 → 冲突', () {
      final candidate = _session(
        id: 'c',
        name: '候选',
        day: 1,
        start: 3,
        end: 4,
        weeks: {2, 3},
      );
      final conflicts = findConflicts(
        sessions: [
          _session(id: 'o', name: '已有', day: 1, start: 2, end: 3, weeks: {1, 2}),
        ],
        exams: const [],
        candidate: candidate,
        totalWeeks: 16,
      );
      expect(conflicts.length, 1);
      expect(conflicts.single.otherName, '已有');
      expect(conflicts.single.weeks, {2});
      expect(conflicts.single.startPeriod, 3);
      expect(conflicts.single.endPeriod, 3);
    });

    test('周次不相交 → 无冲突', () {
      final candidate = _session(
        id: 'c',
        name: '候选',
        day: 1,
        start: 3,
        end: 4,
        weeks: {3},
      );
      final conflicts = findConflicts(
        sessions: [
          _session(id: 'o', name: '已有', day: 1, start: 2, end: 3, weeks: {1}),
        ],
        exams: const [],
        candidate: candidate,
        totalWeeks: 16,
      );
      expect(conflicts, isEmpty);
    });

    test('与考试冲突（按日期换算周与墙钟）', () {
      final termStart = DateTime(2026, 9, 7); // 周一
      final candidate = _session(
        id: 'c',
        name: '候选',
        day: 2,
        start: 1,
        end: 2,
        weeks: {1},
      );
      final exam = ExamEntry(
        id: 'e1',
        name: '期末考试',
        date: DateTime(2026, 9, 8), // 第 1 周周二
        startTime: '08:30',
        endTime: '10:00',
      );
      final conflicts = findConflicts(
        sessions: const [],
        exams: [exam],
        candidate: candidate,
        totalWeeks: 16,
        termStartDate: termStart,
      );
      expect(conflicts.length, 1);
      expect(conflicts.single.isExam, isTrue);
      expect(conflicts.single.otherName, '期末考试');
    });

    test('缺少学期起点时跳过考试维度', () {
      final candidate = _session(
        id: 'c',
        name: '候选',
        day: 2,
        start: 1,
        end: 2,
        weeks: {1},
      );
      final exam = ExamEntry(
        id: 'e1',
        name: '期末考试',
        date: DateTime(2026, 9, 8),
        startTime: '08:30',
        endTime: '10:00',
      );
      final conflicts = findConflicts(
        sessions: const [],
        exams: [exam],
        candidate: candidate,
        totalWeeks: 16,
      );
      expect(conflicts, isEmpty);
    });
  });

  test('CourseOverrideStore 往返与清空', () async {
    final dir = await Directory.systemTemp.createTemp('neu_overlay_test');
    final file = File('${dir.path}${Platform.pathSeparator}course_overrides.json');
    final store = CourseOverrideStore(candidates: [file]);

    final overlay = TimetableOverlay.empty
        .addCourse(_session(id: 'user-1', name: '自建课'))
        .delete(targetKey: '随机过程|2|3|4', scope: 'week', week: 1);
    await store.save(overlay);
    final read = await store.read();
    expect(read.added.single.name, '自建课');
    expect(read.deleted.single.week, 1);

    await store.clear();
    final cleared = await store.read();
    expect(cleared.isEmpty, isTrue);
    await dir.delete(recursive: true);
  });

  testWidgets('课程编辑表单：名称必填，填写后可保存', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => showCourseEditor(
              context,
              presetDay: 2,
              presetPeriod: 3,
              presetWeek: 1,
              allWeeks: {1, 2, 3},
              validate: (draft, scope, week) async => const [],
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('新增课程'), findsOneWidget);
    FilledButton saveButton() =>
        tester.widget<FilledButton>(find.widgetWithText(FilledButton, '保存'));
    expect(saveButton().onPressed, isNull);

    await tester.enterText(find.byType(TextField).first, '高等数学');
    await tester.pumpAndSettle();
    expect(saveButton().onPressed, isNotNull);
  });

  testWidgets('存在冲突时保存按钮保持禁用', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => showCourseEditor(
              context,
              presetDay: 2,
              presetPeriod: 3,
              presetWeek: 1,
              allWeeks: {1, 2, 3},
              validate: (draft, scope, week) async => [
                const CourseConflict(
                  weeks: {1},
                  day: 2,
                  startPeriod: 3,
                  endPeriod: 3,
                  otherName: '已有课程',
                  isExam: false,
                ),
              ],
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, '高等数学');
    await tester.pumpAndSettle();

    expect(find.textContaining('存在冲突'), findsOneWidget);
    final save = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, '保存'),
    );
    expect(save.onPressed, isNull);
  });
}
