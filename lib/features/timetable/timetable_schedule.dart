import '../../core/settings/app_settings.dart';
import 'timetable_models.dart';

/// Pure, UI-free view over a [TimetableData] snapshot.
///
/// Keeps calendar/week calculations and ordering rules in one place so the
/// timetable page only renders state and forwards user intents.
class TimetableSchedule {
  TimetableSchedule(this.data, {this.weekStartSetting = WeekStart.monday});

  final TimetableData data;
  final _weekSessions = <int, List<CourseSession>>{};
  final _daySessions = <(int, int), List<CourseSession>>{};
  final _weekExams = <DateTime, List<ExamEntry>>{};
  final _dayExams = <DateTime, List<ExamEntry>>{};
  late final List<ExamEntry> allExams = List<ExamEntry>.unmodifiable(
    data.exams.toList()..sort(examOrder),
  );

  /// 每周起始日（周一 / 周日）。它只改变“周的日期边界与列日期”，
  /// 数据里 [CourseSession.day] 恒为 1=周一 … 7=周日，语义不变。
  final WeekStart weekStartSetting;

  /// [date] 所在教学周的起始日（按 [weekStartSetting] 对齐到周一或周日）。
  DateTime _startOfWeek(DateTime date) {
    final weekday = date.weekday; // 1=周一 … 7=周日
    final back = weekStartSetting == WeekStart.sunday
        ? weekday % 7
        : weekday - 1;
    return DateTime(
      date.year,
      date.month,
      date.day,
    ).subtract(Duration(days: back));
  }

  int nowWeek([DateTime? now]) {
    final clock = now ?? DateTime.now();
    final termStart = data.termStartDate;
    if (termStart == null) return data.weekFor(clock);
    final base = _startOfWeek(termStart);
    final diff = _startOfWeek(clock).difference(base).inDays ~/ 7;
    final week = diff + 1;
    if (week < 1) return 1;
    if (week > data.totalWeeks) return data.totalWeeks;
    return week;
  }

  /// [week] 教学周的起始日（周日或周一，取决于 [weekStartSetting]），
  /// 或 null（term start 未知）。
  ///
  /// Legacy caches may not contain `termStartDate`; derive it from the stored
  /// current week as a best-effort fallback.
  DateTime? weekStartFor(int week) {
    final start = data.termStartDate ?? _inferTermStartFromCurrentWeek();
    if (start == null) return null;
    return _startOfWeek(start).add(Duration(days: (week - 1) * 7));
  }

  DateTime? get weekStart => weekStartFor(data.currentWeek);

  bool isWeekToday(int week, {DateTime? now}) {
    final today = now ?? DateTime.now();
    final start = weekStartFor(week);
    if (start == null) return false;
    final end = start.add(const Duration(days: 6));
    return !today.isBefore(start) && !today.isAfter(end);
  }

  List<CourseSession> weekSessions(int week) =>
      _weekSessions.putIfAbsent(week, () => data.forWeek(week));

  List<ExamEntry> examsForWeek(int week) {
    final start = weekStartFor(week);
    if (start == null) return const [];
    return _weekExams.putIfAbsent(start, () {
      final end = start.add(const Duration(days: 7));
      return List.unmodifiable(
        allExams.where(
          (exam) => !exam.date.isBefore(start) && exam.date.isBefore(end),
        ),
      );
    });
  }

  List<CourseSession> daySessions(int day, int week) =>
      _daySessions.putIfAbsent((week, day), () => data.forDay(day, week));

  List<ExamEntry> dayExams(int day, int week) {
    final start = weekStartFor(week);
    if (start == null) return const [];
    // 列内偏移：周一开头时 day-1；周日开头时 周日=0、周一..周六=1..6。
    final offset = weekStartSetting == WeekStart.sunday ? day % 7 : day - 1;
    final date = start.add(Duration(days: offset));
    return _dayExams.putIfAbsent(
      date,
      () => List.unmodifiable(data.examsOn(date).toList()..sort(examOrder)),
    );
  }

  /// The next class in [week]: still upcoming today, later this week, or the
  /// first class of the following week (prefixed with `下`).
  (CourseSession, String)? nextSession(int week, {DateTime? now}) {
    final clock = now ?? DateTime.now();
    final sessions = weekSessions(week);
    if (sessions.isEmpty) return null;
    if (week != nowWeek(clock)) return (sessions.first, '');

    final minutesNow = clock.hour * 60 + clock.minute;
    for (final session in daySessions(clock.weekday, week)) {
      if (PeriodTimes.startMinutes(session.startPeriod) > minutesNow) {
        return (session, '');
      }
    }
    for (final session in sessions) {
      if (session.day > clock.weekday) return (session, '');
    }
    final nextWeek = weekSessions(week + 1);
    if (nextWeek.isEmpty) return null;
    return (nextWeek.first, '下');
  }

  static int sessionOrder(CourseSession a, CourseSession b) {
    final byDay = a.day.compareTo(b.day);
    if (byDay != 0) return byDay;
    return a.startPeriod.compareTo(b.startPeriod);
  }

  static int examOrder(ExamEntry a, ExamEntry b) {
    final byDate = a.date.compareTo(b.date);
    if (byDate != 0) return byDate;
    final aStart = PeriodTimes.parseTime(a.startTime) ?? 0;
    final bStart = PeriodTimes.parseTime(b.startTime) ?? 0;
    return aStart.compareTo(bStart);
  }

  DateTime? _inferTermStartFromCurrentWeek() {
    final week = data.currentWeek;
    if (week <= 0 || week > 40) return null;
    return TimetableData.mondayOf(DateTime.now())
        .subtract(Duration(days: (week - 1) * 7));
  }
}
