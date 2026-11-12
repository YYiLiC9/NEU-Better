import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neu_better_pro/features/timetable/course_note_store.dart';
import 'package:neu_better_pro/features/timetable/timetable_models.dart';
import 'package:neu_better_pro/features/timetable/timetable_page.dart'
    show formatWeeks, showCourseDetail;

void main() {
  test('formatWeeks compresses consecutive weeks', () {
    expect(formatWeeks(<int>{}), '');
    expect(formatWeeks({for (var i = 1; i <= 16; i++) i}), '第1-16周');
    expect(formatWeeks({1, 3, 5}), '第1、3、5周');
    expect(formatWeeks({2, 4, 6, 8}), '第2、4、6、8周');
    expect(formatWeeks({1, 2, 3, 7, 8}), '第1-3、7-8周');
  });

  test('CourseNoteStore round-trips and drops blank notes', () async {
    final dir = await Directory.systemTemp.createTemp('neu_notes_test');
    final file = File('${dir.path}${Platform.pathSeparator}course_notes.json');
    final store = CourseNoteStore(candidates: [file]);
    await store.save({'a': '   ', 'b': '复习第3章'});
    final read = await store.read();
    expect(read, {'b': '复习第3章'});
    await dir.delete(recursive: true);
  });

  testWidgets('course detail dialog shows fields and a note box', (
    tester,
  ) async {
    const session = CourseSession(
      id: 'algorithms',
      name: '高级算法',
      teacher: '王老师',
      room: '浑南 1-101',
      className: '计算机 2026 级',
      day: 1,
      startPeriod: 1,
      endPeriod: 2,
      weeks: {1},
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => showCourseDetail(context, session: session),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('高级算法'), findsOneWidget);
    expect(find.text('王老师'), findsOneWidget);
    expect(find.text('浑南 1-101'), findsOneWidget);
    expect(find.text('备注'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
  });
}
