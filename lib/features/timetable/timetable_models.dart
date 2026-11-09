import 'dart:collection';

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
  });

  final String termName;
  final int totalWeeks;
  final List<CourseSession> sessions;
  final bool isSample;
  final int currentWeek;

  Set<String> get courseIds => sessions.map((session) => session.id).toSet();

  int get courseCount => courseIds.length;

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
    'sessions': sessions.map((session) => session.toJson()).toList(),
  };

  factory TimetableData.fromJson(Map<String, dynamic> json) {
    return TimetableData(
      termName: json['termName'] as String? ?? '研究生课程表',
      totalWeeks: (json['totalWeeks'] as num?)?.toInt() ?? 18,
      currentWeek: (json['currentWeek'] as num?)?.toInt() ?? 8,
      isSample: json['isSample'] as bool? ?? false,
      sessions: ((json['sessions'] as List?) ?? const [])
          .whereType<Map>()
          .map((value) => CourseSession.fromJson(Map<String, dynamic>.from(value)))
          .toList(),
    );
  }
}

abstract final class SampleTimetable {
  static const data = TimetableData(
    termName: '2026–2027 秋季学期',
    totalWeeks: 16,
    isSample: true,
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
