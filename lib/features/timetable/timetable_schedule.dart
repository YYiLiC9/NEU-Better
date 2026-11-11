import 'timetable_models.dart';

/// Pure, UI-free view over a [TimetableData] snapshot.
///
/// Keeps calendar/week calculations and ordering rules in one place so the
/// timetable page only renders state and forwards user intents.
class TimetableSchedule {
  const TimetableSchedule(this.data);

  final TimetableData data;

  int nowWeek([DateTime? now]) => data.weekFor(now ?? DateTime.now());

  /// Monday of [week], or null when the term start is unknown.
  ///
  /// Legacy caches may not contain `termStartDate`; derive it from the stored
  /// current week as a best-effort fallback.
  DateTime? weekStartFor(int week) {
    final start = data.termStartDate ?? _inferTermStartFromCurrentWeek();
    if (start == null) return null;
    return TimetableData.mondayOf(start).add(Duration(days: (week - 1) * 7));
  }

  DateTime? get weekStart => weekStartFor(data.currentWeek);

  bool isWeekToday(int week, {DateTime? now}) {
    final today = now ?? DateTime.now();
    final start = weekStartFor(week);
    if (start == null) return false;
    final end = start.add(const Duration(days: 6));
    return !today.isBefore(start) && !today.isAfter(end);
  }

  List<CourseSession> weekSessions(int week) => data.forWeek(week);

  List<ExamEntry> examsForWeek(int week) {
    final start = weekStartFor(week);
    if (start == null) return const [];
    final end = start.add(const Duration(days: 7));
    return data.exams
        .where((exam) => !exam.date.isBefore(start) && exam.date.isBefore(end))
        .toList()
      ..sort(examOrder);
  }

  List<ExamEntry> get allExams => [...data.exams]..sort(examOrder);

  List<CourseSession> daySessions(int day, int week) => data.forDay(day, week);

  List<ExamEntry> dayExams(int day, int week) {
    final start = weekStartFor(week);
    if (start == null) return const [];
    return (data.examsOn(start.add(Duration(days: day - 1))).toList()
      ..sort(examOrder));
  }

  /// The next class in [week]: still upcoming today, later this week, or the
  /// first class of the following week (prefixed with `下`).
  (CourseSession, String)? nextSession(int week, {DateTime? now}) {
    final clock = now ?? DateTime.now();
    final sessions = weekSessions(week);
    if (sessions.isEmpty) return null;
    final sorted = [...sessions]..sort(sessionOrder);
    if (week != nowWeek(clock)) return (sorted.first, '');

    final minutesNow = clock.hour * 60 + clock.minute;
    for (final session in sorted.where((s) => s.day == clock.weekday)) {
      if (PeriodTimes.startMinutes(session.startPeriod) > minutesNow) {
        return (session, '');
      }
    }
    for (final session in sorted) {
      if (session.day > clock.weekday) return (session, '');
    }
    final nextWeek = weekSessions(week + 1);
    if (nextWeek.isEmpty) return null;
    final sortedNext = [...nextWeek]..sort(sessionOrder);
    return (sortedNext.first, '下');
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
