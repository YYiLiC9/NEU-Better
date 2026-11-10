import 'dart:collection';

/// Teaching period clock matching the real graduate timetable grid.
///
/// Periods last 45 minutes. The morning has a 20-minute break after period 2
/// and the afternoon after period 6. Lunch sits between periods 4–5 and dinner
/// between 8–9; all other gaps are 10 minutes.
abstract final class PeriodTimes {
  static const firstStartMinutes = 8 * 60 + 30;
  static const periodMinutes = 45;
  static const periodsPerDay = 12;

  /// Wall-clock start of every period, in minutes since midnight:
  /// 08:30, 09:25, 10:30, 11:25, 14:00, 14:55, 16:00, 16:55, 18:30,
  /// 19:25, 20:20, 21:15.
  static const List<int> _starts = [
    8 * 60 + 30,
    9 * 60 + 25,
    10 * 60 + 30,
    11 * 60 + 25,
    14 * 60,
    14 * 60 + 55,
    16 * 60,
    16 * 60 + 55,
    18 * 60 + 30,
    19 * 60 + 25,
    20 * 60 + 20,
    21 * 60 + 15,
  ];

  static int startMinutes(int period) =>
      _starts[(period - 1).clamp(0, periodsPerDay - 1)];

  static int endMinutes(int period) => startMinutes(period) + periodMinutes;

  static String format(int minutes) {
    final normalized = ((minutes % 1440) + 1440) % 1440;
    final h = normalized ~/ 60;
    final m = normalized % 60;
    return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
  }

  static String startLabel(int period) => format(startMinutes(period));

  static String endLabel(int period) => format(endMinutes(period));

  static String rangeLabel(int startPeriod, int endPeriod) =>
      '${startLabel(startPeriod)}–${endLabel(endPeriod)}';

  /// Parses `HH:MM` (or `HHMM`) into minutes since midnight.
  static int? parseTime(String? raw) {
    if (raw == null) return null;
    final match = RegExp(r'^\s*(\d{1,2})\s*[:：]?\s*(\d{2})?\s*$')
        .firstMatch(raw);
    if (match == null) return null;
    final h = int.tryParse(match.group(1)!);
    final m = int.tryParse(match.group(2) ?? '0') ?? 0;
    if (h == null || h > 24 || m > 59) return null;
    return h * 60 + m;
  }

  /// Vertical offset (in slot units) for a wall-clock minute. Each period is
  /// one slot tall; breaks collapse to the boundary between two slots, so
  /// 10:10 (end of period 2) and 10:30 (start of period 3) both land on 2.0.
  /// This keeps exam cards aligned with the real period grid even though the
  /// breaks are not proportional.
  static double slotOffset(int minutes) {
    if (minutes <= _starts.first) {
      return (minutes - _starts.first) / periodMinutes;
    }
    for (var index = periodsPerDay - 1; index >= 0; index--) {
      final start = _starts[index];
      if (minutes < start) continue;
      final elapsed = minutes - start;
      if (elapsed >= periodMinutes) return (index + 1).toDouble();
      return index + elapsed / periodMinutes;
    }
    return 0;
  }
}

/// One scheduled exam. Exams differ from course sessions: they happen on a
/// concrete date with a wall-clock time, so they are stored separately and
/// rendered with a distinct card style.
class ExamEntry {
  const ExamEntry({
    required this.id,
    required this.name,
    required this.date,
    this.startTime,
    this.endTime,
    this.room = '',
    this.seat = '',
    this.type = '',
  });

  final String id;
  final String name;

  /// The exam date at 00:00 local time.
  final DateTime date;
  final String? startTime;
  final String? endTime;
  final String room;
  final String seat;
  final String type;

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'date': _dateKey(date),
    if (startTime != null) 'startTime': startTime,
    if (endTime != null) 'endTime': endTime,
    'room': room,
    'seat': seat,
    'type': type,
  };

  factory ExamEntry.fromJson(Map<String, dynamic> json) {
    return ExamEntry(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '未命名考试',
      date: parseDate(json['date'] as String?) ?? DateTime(1970, 1, 1),
      startTime: json['startTime'] as String?,
      endTime: json['endTime'] as String?,
      room: json['room'] as String? ?? '',
      seat: json['seat'] as String? ?? '',
      type: json['type'] as String? ?? '',
    );
  }

  static String _dateKey(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';

  /// Parses `yyyy-MM-dd` (with optional trailing time) and anything
  /// [DateTime.tryParse] understands. Public because the import parser uses it.
  static DateTime? parseDate(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    final value = raw.trim();
    final match = RegExp(r'^(\d{4})-(\d{1,2})-(\d{1,2})').firstMatch(value);
    if (match != null) {
      return DateTime(
        int.parse(match.group(1)!),
        int.parse(match.group(2)!),
        int.parse(match.group(3)!),
      );
    }
    // The exam list uses display text such as `2026年10月25日 13:50-15:50`.
    final chinese = RegExp(r'^(\d{4})年(\d{1,2})月(\d{1,2})日').firstMatch(value);
    if (chinese != null) {
      return DateTime(
        int.parse(chinese.group(1)!),
        int.parse(chinese.group(2)!),
        int.parse(chinese.group(3)!),
      );
    }
    return DateTime.tryParse(value);
  }
}

/// One scheduled meeting of a course. The source system exposes course
/// arrangements as rows, so a single course may appear in several sessions.
class CourseSession {
  const CourseSession({
    required this.id,
    required this.name,
    required this.teacher,
    required this.room,
    required this.className,
    required this.day,
    required this.startPeriod,
    required this.endPeriod,
    required this.weeks,
  });

  final String id;
  final String name;
  final String teacher;
  final String room;
  final String className;

  /// ISO weekday: 1 = Monday, 7 = Sunday.
  final int day;
  final int startPeriod;
  final int endPeriod;
  final Set<int> weeks;

  bool isActive(int week) => weeks.contains(week);
  int get span => endPeriod - startPeriod + 1;

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'teacher': teacher,
    'room': room,
    'className': className,
    'day': day,
    'startPeriod': startPeriod,
    'endPeriod': endPeriod,
    'weeks': weeks.toList()..sort(),
  };

  factory CourseSession.fromJson(Map<String, dynamic> json) {
    return CourseSession(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '未命名课程',
      teacher: json['teacher'] as String? ?? '',
      room: json['room'] as String? ?? '',
      className: json['className'] as String? ?? '',
      day: (json['day'] as num?)?.toInt() ?? 1,
      startPeriod: (json['startPeriod'] as num?)?.toInt() ?? 1,
      endPeriod: (json['endPeriod'] as num?)?.toInt() ?? 1,
      weeks: ((json['weeks'] as List?) ?? const [])
          .map((value) => (value as num).toInt())
          .toSet(),
    );
  }
}

class TimetableData {
  const TimetableData({
    required this.termName,
    required this.totalWeeks,
    required this.sessions,
    this.isSample = false,
    this.currentWeek = 8,
    this.termStartDate,
    this.exams = const [],
  });

  final String termName;
  final int totalWeeks;
  final List<CourseSession> sessions;
  final bool isSample;
  final int currentWeek;

  /// Monday of teaching week 1. Used to derive the current week from the
  /// calendar; null keeps the stored [currentWeek] fallback.
  final DateTime? termStartDate;

  final List<ExamEntry> exams;

  Set<String> get courseIds => sessions.map((session) => session.id).toSet();

  int get courseCount => courseIds.length;

  /// Monday of the week containing [date].
  static DateTime mondayOf(DateTime date) {
    final day = DateTime(date.year, date.month, date.day);
    return day.subtract(Duration(days: date.weekday - 1));
  }

  /// The teaching week [date] falls into, clamped to 1..totalWeeks.
  int weekFor(DateTime date) {
    final start = termStartDate;
    if (start == null) return currentWeek.clamp(1, totalWeeks);
    final diff = mondayOf(date).difference(mondayOf(start)).inDays;
    final week = diff ~/ 7 + 1;
    return week.clamp(1, totalWeeks);
  }

  List<ExamEntry> examsForWeek(int week) {
    final start = termStartDate;
    if (start == null) return const [];
    final first = mondayOf(start).add(Duration(days: (week - 1) * 7));
    final last = first.add(const Duration(days: 6));
    return UnmodifiableListView(
      exams
          .where(
            (exam) => !exam.date.isBefore(first) && !exam.date.isAfter(last),
          )
          .toList()
        ..sort((a, b) => a.date.compareTo(b.date)),
    );
  }

  List<ExamEntry> examsOn(DateTime date) {
    final key = DateTime(date.year, date.month, date.day);
    return UnmodifiableListView(
      exams.where((exam) {
        final d = exam.date;
        return d.year == key.year && d.month == key.month && d.day == key.day;
      }).toList(),
    );
  }

  List<CourseSession> forWeek(int week) {
    return UnmodifiableListView(
      sessions.where((session) => session.isActive(week)).toList()
        ..sort((a, b) {
          if (a.day != b.day) return a.day.compareTo(b.day);
          return a.startPeriod.compareTo(b.startPeriod);
        }),
    );
  }

  List<CourseSession> forDay(int day, int week) {
    return UnmodifiableListView(
      sessions
          .where((session) => session.day == day && session.isActive(week))
          .toList()
        ..sort((a, b) => a.startPeriod.compareTo(b.startPeriod)),
    );
  }

  Map<String, dynamic> toJson() => {
    'termName': termName,
    'totalWeeks': totalWeeks,
    'currentWeek': currentWeek,
    'isSample': isSample,
    if (termStartDate != null) 'termStartDate': _dateKey(termStartDate!),
    'sessions': sessions.map((session) => session.toJson()).toList(),
    'exams': exams.map((exam) => exam.toJson()).toList(),
  };

  factory TimetableData.fromJson(Map<String, dynamic> json) {
    return TimetableData(
      termName: json['termName'] as String? ?? '研究生课程表',
      totalWeeks: (json['totalWeeks'] as num?)?.toInt() ?? 18,
      currentWeek: (json['currentWeek'] as num?)?.toInt() ?? 8,
      isSample: json['isSample'] as bool? ?? false,
      termStartDate: ExamEntry.parseDate(json['termStartDate'] as String?),
      sessions: ((json['sessions'] as List?) ?? const [])
          .whereType<Map>()
          .map(
            (value) => CourseSession.fromJson(Map<String, dynamic>.from(value)),
          )
          .toList(),
      exams: ((json['exams'] as List?) ?? const [])
          .whereType<Map>()
          .map((value) => ExamEntry.fromJson(Map<String, dynamic>.from(value)))
          .toList(),
    );
  }

  static String _dateKey(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';
}

abstract final class SampleTimetable {
  /// Week 1 Monday of the 2026–2027 fall term. The sample mirrors the real
  /// graduate term so the current-week indicator matches the platform.
  static final DateTime sampleTermStart = DateTime(2026, 8, 31);

  static final data = TimetableData(
    termName: '2026–2027 秋季学期',
    totalWeeks: 16,
    isSample: true,
    termStartDate: sampleTermStart,
    sessions: [
      CourseSession(
        id: 'algorithms',
        name: '高级算法',
        teacher: '王老师',
        room: '浑南 1-101',
        className: '计算机 2026 级',
        day: 1,
        startPeriod: 1,
        endPeriod: 2,
        weeks: {1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16},
      ),
      CourseSession(
        id: 'ml',
        name: '机器学习',
        teacher: '李老师',
        room: '浑南 2-305',
        className: '计算机 2026 级',
        day: 1,
        startPeriod: 5,
        endPeriod: 6,
        weeks: {1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16},
      ),
      CourseSession(
        id: 'english',
        name: '学术英语',
        teacher: '刘老师',
        room: '浑南 4-211',
        className: '研究生公共课',
        day: 2,
        startPeriod: 3,
        endPeriod: 4,
        weeks: {1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16},
      ),
      CourseSession(
        id: 'matrix',
        name: '矩阵论',
        teacher: '周老师',
        room: '浑南 3-108',
        className: '研究生公共课',
        day: 2,
        startPeriod: 7,
        endPeriod: 8,
        weeks: {1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16},
      ),
      CourseSession(
        id: 'vision',
        name: '计算机视觉',
        teacher: '赵老师',
        room: '浑南 2-402',
        className: '计算机 2026 级',
        day: 3,
        startPeriod: 1,
        endPeriod: 2,
        weeks: {1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16},
      ),
      CourseSession(
        id: 'stochastic',
        name: '随机过程',
        teacher: '孙老师',
        room: '浑南 3-205',
        className: '研究生公共课',
        day: 4,
        startPeriod: 3,
        endPeriod: 4,
        weeks: {1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16},
      ),
      CourseSession(
        id: 'seminar',
        name: '学术前沿讲座',
        teacher: '学院',
        room: '浑南 学术报告厅',
        className: '计算机 2026 级',
        day: 4,
        startPeriod: 9,
        endPeriod: 10,
        weeks: {2, 4, 6, 8, 10, 12, 14, 16},
      ),
      CourseSession(
        id: 'sports',
        name: '研究生体育',
        teacher: '陈老师',
        room: '浑南 体育馆',
        className: '研究生公共课',
        day: 5,
        startPeriod: 7,
        endPeriod: 8,
        weeks: {1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12},
      ),
    ],
  );
}
