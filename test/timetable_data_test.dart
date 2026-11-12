import 'package:flutter_test/flutter_test.dart';
import 'package:neu_better_pro/features/timetable/timetable_import.dart';
import 'package:neu_better_pro/features/timetable/timetable_models.dart';
import 'package:neu_better_pro/features/timetable/timetable_schedule.dart';

void main() {
  group('PeriodTimes', () {
    test('matches the real graduate timetable clock', () {
      expect(PeriodTimes.startMinutes(1), 8 * 60 + 30);
      expect(PeriodTimes.startMinutes(2), 9 * 60 + 25);
      expect(PeriodTimes.startMinutes(3), 10 * 60 + 30);
      expect(PeriodTimes.startMinutes(4), 11 * 60 + 25);
      expect(PeriodTimes.startMinutes(5), 14 * 60);
      expect(PeriodTimes.startMinutes(6), 14 * 60 + 55);
      expect(PeriodTimes.startMinutes(7), 16 * 60);
      expect(PeriodTimes.startMinutes(8), 16 * 60 + 55);
      expect(PeriodTimes.startMinutes(9), 18 * 60 + 30);
      expect(PeriodTimes.startMinutes(10), 19 * 60 + 25);
      expect(PeriodTimes.startMinutes(11), 20 * 60 + 20);
      expect(PeriodTimes.startMinutes(12), 21 * 60 + 15);

      expect(PeriodTimes.startLabel(1), '08:30');
      expect(PeriodTimes.endLabel(1), '09:15');
      expect(PeriodTimes.startLabel(3), '10:30');
      expect(PeriodTimes.startLabel(7), '16:00');
      expect(PeriodTimes.startLabel(11), '20:20');
      expect(PeriodTimes.endLabel(12), '22:00');
    });

    test('matches the real break pattern', () {
      // 09:15 -> 09:25 (10 min), 10:10 -> 10:30 (20 min)
      expect(PeriodTimes.endMinutes(1), PeriodTimes.startMinutes(2) - 10);
      expect(PeriodTimes.endMinutes(2), PeriodTimes.startMinutes(3) - 20);
      expect(PeriodTimes.endMinutes(3), PeriodTimes.startMinutes(4) - 10);
      expect(PeriodTimes.endMinutes(5), PeriodTimes.startMinutes(6) - 10);
      expect(PeriodTimes.endMinutes(6), PeriodTimes.startMinutes(7) - 20);
      expect(PeriodTimes.endMinutes(7), PeriodTimes.startMinutes(8) - 10);
      // Dinner break before the 18:30 evening start.
      expect(PeriodTimes.endMinutes(8), 17 * 60 + 40);
    });

    test('slotOffset aligns exam starts with the period grid', () {
      expect(PeriodTimes.slotOffset(8 * 60 + 30), 0);
      expect(PeriodTimes.slotOffset(10 * 60 + 30), 2);
      expect(PeriodTimes.slotOffset(14 * 60), 4);
      expect(PeriodTimes.slotOffset(16 * 60), 6);
      expect(PeriodTimes.slotOffset(18 * 60 + 30), 8);
      expect(PeriodTimes.slotOffset(19 * 60 + 25), 9);
      expect(PeriodTimes.slotOffset(20 * 60 + 20), 10);
      expect(PeriodTimes.slotOffset(21 * 60 + 15), 11);
      // Break time collapses to the boundary of the next slot.
      expect(PeriodTimes.slotOffset(10 * 60 + 10), 2);
      expect(PeriodTimes.slotOffset(10 * 60 + 20), 2);
    });
  });

  group('parseExams', () {
    const response = '''
{
  "code": "0",
  "datas": {
    "queryMyExamArrangeMent": {
      "stuInfo": {"XH": "2672281", "XM": "测试同学"},
      "arranged": [
        {
          "WID": "exam-1",
          "KCM": "工程伦理",
          "KSRQ": "2026-10-25",
          "KSSJ": "13:50",
          "JSSJ": "15:50",
          "KSSJMS": "2026年10月25日 13:50-15:50(星期日第3场)",
          "JASMC": "1号A307",
          "ZWH": 49,
          "KSLXDM_DISPLAY": "01"
        },
        {
          "WID": "exam-2",
          "KCM": "中国式现代化的理论与实践",
          "KSRQ": "2026-11-11",
          "KSSJ": "13:50",
          "JSSJ": "15:50",
          "JASMC": "信息A113",
          "ZWH": 42
        }
      ],
      "showkeys": ["KCM", "KCH", "KSSJMS", "JASMC", "ZWH"],
      "notArranged": [
        {"KCM": "马克思主义与当代科技", "KSRQ": "2026-12-01"}
      ]
    }
  }
}
''';

    test('parses real arranged fields and skips notArranged', () {
      final exams = YjsTimetableParser.parseExams(response);
      expect(exams, hasLength(2));

      final first = exams.first;
      expect(first.name, '工程伦理');
      expect(first.date, DateTime(2026, 10, 25));
      expect(first.startTime, '13:50');
      expect(first.endTime, '15:50');
      expect(first.room, '1号A307');
      expect(first.seat, '49');
      expect(first.type, '01');

      final second = exams[1];
      expect(second.name, '中国式现代化的理论与实践');
      expect(second.date, DateTime(2026, 11, 11));
      expect(second.room, '信息A113');
      expect(second.seat, '42');
    });

    test('falls back to KSSJMS when KSRQ/KSSJ are absent', () {
      const body = '''
{"datas":{"queryMyExamArrangeMent":{"arranged":[
  {"KCM":"工程管理","KSSJMS":"2026年11月15日 10:20-12:20","JASMC":"1号B101","ZWH":8}
]}}}
''';
      final exams = YjsTimetableParser.parseExams(body);
      expect(exams, hasLength(1));
      expect(exams.single.date, DateTime(2026, 11, 15));
      expect(exams.single.startTime, '10:20');
      expect(exams.single.endTime, '12:20');
      expect(exams.single.room, '1号B101');
      expect(exams.single.seat, '8');
    });

    test('tolerates empty optional values and empty arranged list', () {
      const body = '''
{"datas":{"queryMyExamArrangeMent":{"arranged":[
  {"KCM":"仅课程","KSRQ":"2026-12-01"}
],"notArranged":[{"KCM":"不排考","KSRQ":"2026-12-02"}]}}}
''';
      final exams = YjsTimetableParser.parseExams(body);
      expect(exams, hasLength(1));
      expect(exams.single.name, '仅课程');
      expect(exams.single.startTime, isNull);
      expect(exams.single.endTime, isNull);
      expect(exams.single.room, isEmpty);
      expect(exams.single.seat, isEmpty);

      const empty = '''
{"datas":{"queryMyExamArrangeMent":{"arranged":[],"notArranged":[{"KCM":"不排考"}]}}}
''';
      expect(YjsTimetableParser.parseExams(empty), isEmpty);
    });

    test('shows notArranged exams (with date) when arranged is empty', () {
      const body = '''
{"datas":{"queryMyExamArrangeMent":{"arranged":[],"notArranged":[
  {"KCM":"待排考","KSRQ":"2026-12-02"}
]}}}
''';
      final exams = YjsTimetableParser.parseExams(body);
      expect(exams, hasLength(1));
      expect(exams.single.name, '待排考');
      expect(exams.single.date, DateTime(2026, 12, 2));
      expect(exams.single.startTime, isNull);
    });

    test('returns empty for malformed JSON', () {
      expect(YjsTimetableParser.parseExams('<html>403</html>'), isEmpty);
    });
  });

  group('TimetableData.examsForWeek', () {
    test('includes both Monday and Sunday boundaries of the week', () {
      final data = TimetableData(
        termName: '2026-2027秋季学期',
        totalWeeks: 16,
        termStartDate: DateTime(2026, 8, 31),
        sessions: const [],
        exams: [
          ExamEntry(id: 'a', name: '周一考试', date: DateTime(2026, 8, 31)),
          ExamEntry(id: 'b', name: '周日考试', date: DateTime(2026, 9, 6)),
          ExamEntry(id: 'c', name: '第二周考试', date: DateTime(2026, 9, 7)),
          ExamEntry(id: 'd', name: '第三周考试', date: DateTime(2026, 9, 14)),
        ],
      );

      expect(data.examsForWeek(1).map((exam) => exam.id), ['a', 'b']);
      expect(data.examsForWeek(2).map((exam) => exam.id), ['c']);
      expect(data.examsForWeek(3).map((exam) => exam.id), ['d']);
    });

    test('returns empty when term start is unknown', () {
      final data = TimetableData(
        termName: '未知',
        totalWeeks: 16,
        sessions: const [],
        exams: [ExamEntry(id: 'a', name: '考试', date: DateTime(2026, 9, 1))],
      );
      expect(data.examsForWeek(1), isEmpty);
    });
  });

  group('TimetableSchedule', () {
    final data = TimetableData(
      termName: '2026-2027秋季学期',
      totalWeeks: 16,
      currentWeek: 11,
      termStartDate: DateTime(2026, 8, 31),
      sessions: [
        CourseSession(
          id: 'a',
          name: '测试课程',
          teacher: '老师',
          room: 'A101',
          className: '测试班',
          day: 3,
          startPeriod: 5,
          endPeriod: 6,
          weeks: {11},
        ),
      ],
      exams: [
        ExamEntry(
          id: 'e1',
          name: '本周考试',
          date: DateTime(2026, 11, 11),
          startTime: '13:50',
          endTime: '15:50',
        ),
        ExamEntry(id: 'e2', name: '下周考试', date: DateTime(2026, 11, 18)),
      ],
    );

    test('computes week starts and current week from the calendar', () {
      final schedule = TimetableSchedule(data);
      expect(schedule.weekStartFor(1), DateTime(2026, 8, 31));
      expect(schedule.weekStartFor(11), DateTime(2026, 11, 9));
      expect(schedule.nowWeek(DateTime(2026, 11, 11)), 11);
      expect(schedule.isWeekToday(11, now: DateTime(2026, 11, 11)), isTrue);
      expect(schedule.isWeekToday(10, now: DateTime(2026, 11, 11)), isFalse);
    });

    test('filters weekly exams with a fallback-free term start', () {
      final schedule = TimetableSchedule(data);
      expect(schedule.examsForWeek(11).map((e) => e.id), ['e1']);
      expect(schedule.examsForWeek(12).map((e) => e.id), ['e2']);
      expect(schedule.allExams.map((e) => e.id), ['e1', 'e2']);
    });

    test('selects the next session for the displayed week', () {
      final schedule = TimetableSchedule(data);
      final next = schedule.nextSession(11, now: DateTime(2026, 11, 11, 9));
      expect(next?.$1.name, '测试课程');
      expect(next?.$2, '');
      expect(schedule.nextSession(11, now: DateTime(2026, 11, 12)), isNull);
    });
  });
}
