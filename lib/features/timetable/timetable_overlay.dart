import 'timetable_models.dart';

/// 官方课表与「本地覆盖层」的合并/冲突计算，全部为纯逻辑，便于单元测试。
///
/// 设计要点（详见 .tmp/plan_course_overlay.md）：
/// - 官方快照（timetable.json）只存同步结果，永不写入用户修改；
/// - 用户的新增 / 修改 / 删除存 [TimetableOverlay]（course_overrides.json）；
/// - 展示时用 [applyOverlay] 把覆盖层叠加到官方快照上。
/// - 官方课程用「指纹」[courseKey] 匹配（name|day|startPeriod|endPeriod）。

/// 一门官方课程的身份指纹：名称 + 星期 + 起止节次。
String courseKey(CourseSession session) =>
    '${session.name}|${session.day}|${session.startPeriod}|${session.endPeriod}';

/// 覆盖层：对官方课表的本地修改。
class TimetableOverlay {
  const TimetableOverlay({
    this.added = const [],
    this.modified = const [],
    this.deleted = const [],
  });

  /// 用户新增的课程（id 以 `user-` 开头）。
  final List<CourseSession> added;

  /// 对官方课程的替换（scope = all / week）。
  final List<CourseModification> modified;

  /// 对官方课程的删除（scope = all / week）。
  final List<CourseDeletion> deleted;

  static const empty = TimetableOverlay();

  bool get isEmpty =>
      added.isEmpty && modified.isEmpty && deleted.isEmpty;

  int get count => added.length + modified.length + deleted.length;

  TimetableOverlay _copy({
    List<CourseSession>? added,
    List<CourseModification>? modified,
    List<CourseDeletion>? deleted,
  }) {
    return TimetableOverlay(
      added: added ?? this.added,
      modified: modified ?? this.modified,
      deleted: deleted ?? this.deleted,
    );
  }

  // ---- 新增课程（用户自建） ----

  TimetableOverlay addCourse(CourseSession session) =>
      _copy(added: [...added, session]);

  TimetableOverlay replaceAdded(CourseSession session) => _copy(
    added: [for (final item in added) item.id == session.id ? session : item],
  );

  TimetableOverlay removeAdded(String id) =>
      _copy(added: [for (final a in added) if (a.id != id) a]);

  /// 删除用户自建课程的某一周：若删除后没有剩余周，则整条移除。
  TimetableOverlay removeAddedWeek(String id, int week) {
    final next = <CourseSession>[];
    for (final a in added) {
      if (a.id != id) {
        next.add(a);
        continue;
      }
      final weeks = a.weeks.where((w) => w != week).toSet();
      if (weeks.isNotEmpty) next.add(a.copyWith(weeks: weeks));
    }
    return _copy(added: next);
  }

  // ---- 修改官方课程 ----

  TimetableOverlay modify({
    required String targetKey,
    required String scope,
    int? week,
    required CourseSession replacement,
  }) {
    final mods = modified.where((m) {
      if (m.targetKey != targetKey) return true;
      if (m.scope != scope) return true;
      if (scope == 'week') return m.week != week;
      return false; // 同键的 all 修改只保留最新一条
    }).toList();
    mods.add(
      CourseModification(
        targetKey: targetKey,
        scope: scope,
        week: week,
        replacement: replacement,
      ),
    );
    // 修改会覆盖同键的删除：all 修改清掉该键全部删除，week 修改只清本周删除。
    final dels = deleted.where((d) {
      if (d.targetKey != targetKey) return true;
      if (scope == 'all') return false;
      return !(d.scope == 'week' && d.week == week);
    }).toList();
    return TimetableOverlay(added: added, modified: mods, deleted: dels);
  }

  // ---- 删除官方课程 ----

  TimetableOverlay delete({
    required String targetKey,
    required String scope,
    int? week,
  }) {
    if (scope == 'all') {
      final mods = modified
          .where((m) => m.targetKey != targetKey)
          .toList();
      final dels = deleted.where((d) => d.targetKey != targetKey).toList()
        ..add(CourseDeletion(targetKey: targetKey, scope: 'all'));
      return TimetableOverlay(added: added, modified: mods, deleted: dels);
    }

    // 仅本周：若已有「所有周」修改，则直接从其替换内容里减去该周，
    // 其余周保持不变；否则移除本周修改并追加本周删除。
    final weekNum = week;
    final allIndex = modified.indexWhere(
      (m) => m.targetKey == targetKey && m.scope == 'all',
    );
    if (allIndex >= 0) {
      final mods = [...modified];
      final target = mods[allIndex];
      final weeks = target.replacement.weeks
          .where((w) => w != weekNum)
          .toSet();
      if (weeks.isEmpty) {
        mods.removeAt(allIndex);
      } else {
        mods[allIndex] = CourseModification(
          targetKey: target.targetKey,
          scope: 'all',
          replacement: target.replacement.copyWith(weeks: weeks),
        );
      }
      return TimetableOverlay(
        added: added,
        modified: mods,
        deleted: deleted
            .where((d) => !(d.targetKey == targetKey && d.week == weekNum))
            .toList(),
      );
    }

    final mods = modified
        .where(
          (m) =>
              !(m.targetKey == targetKey &&
                  m.scope == 'week' &&
                  m.week == weekNum),
        )
        .toList();
    final dels = deleted
        .where(
          (d) =>
              !(d.targetKey == targetKey &&
                  d.scope == 'week' &&
                  d.week == weekNum),
        )
        .toList()
      ..add(
        CourseDeletion(targetKey: targetKey, scope: 'week', week: weekNum),
      );
    return TimetableOverlay(added: added, modified: mods, deleted: dels);
  }

  Map<String, dynamic> toJson() => {
    'added': added.map((s) => s.toJson()).toList(),
    'modified': modified.map((m) => m.toJson()).toList(),
    'deleted': deleted.map((d) => d.toJson()).toList(),
  };

  factory TimetableOverlay.fromJson(Map<String, dynamic> json) {
    List<T> parse<T>(String key, T Function(Map<String, dynamic>) build) {
      final raw = json[key];
      if (raw is! List) return <T>[];
      return raw
          .whereType<Map>()
          .map((value) => build(Map<String, dynamic>.from(value)))
          .toList();
    }

    return TimetableOverlay(
      added: parse('added', CourseSession.fromJson),
      modified: parse('modified', CourseModification.fromJson),
      deleted: parse('deleted', CourseDeletion.fromJson),
    );
  }
}

/// 一条「修改官方课程」记录。
class CourseModification {
  const CourseModification({
    required this.targetKey,
    required this.scope,
    this.week,
    required this.replacement,
  });

  final String targetKey;

  /// `all`（该课程所有已存在周）或 `week`（仅 [week]）。
  final String scope;
  final int? week;
  final CourseSession replacement;

  Map<String, dynamic> toJson() => {
    'targetKey': targetKey,
    'scope': scope,
    if (week != null) 'week': week,
    'replacement': replacement.toJson(),
  };

  factory CourseModification.fromJson(Map<String, dynamic> json) {
    return CourseModification(
      targetKey: json['targetKey'] as String? ?? '',
      scope: (json['scope'] as String?) == 'week' ? 'week' : 'all',
      week: (json['week'] as num?)?.toInt(),
      replacement: CourseSession.fromJson(
        Map<String, dynamic>.from(
          (json['replacement'] as Map?) ?? const <String, dynamic>{},
        ),
      ),
    );
  }
}

/// 一条「删除官方课程」记录。
class CourseDeletion {
  const CourseDeletion({
    required this.targetKey,
    required this.scope,
    this.week,
  });

  final String targetKey;
  final String scope;
  final int? week;

  Map<String, dynamic> toJson() => {
    'targetKey': targetKey,
    'scope': scope,
    if (week != null) 'week': week,
  };

  factory CourseDeletion.fromJson(Map<String, dynamic> json) {
    return CourseDeletion(
      targetKey: json['targetKey'] as String? ?? '',
      scope: (json['scope'] as String?) == 'week' ? 'week' : 'all',
      week: (json['week'] as num?)?.toInt(),
    );
  }
}

/// 把覆盖层叠加到官方快照上，返回用于展示/同步的课表数据。
///
/// 处理顺序：先删除 → 再修改 → 最后追加新增；考试原样保留。
TimetableData applyOverlay(
  TimetableData official,
  TimetableOverlay overlay,
) {
  var sessions = <CourseSession>[...official.sessions];

  // 1) 应用删除
  for (final del in overlay.deleted) {
    final next = <CourseSession>[];
    for (final session in sessions) {
      if (courseKey(session) != del.targetKey) {
        next.add(session);
        continue;
      }
      if (del.scope == 'all') continue; // 整条移除
      final week = del.week;
      if (week == null) {
        next.add(session);
        continue;
      }
      final weeks = session.weeks.where((w) => w != week).toSet();
      if (weeks.isNotEmpty) next.add(session.copyWith(weeks: weeks));
    }
    sessions = next;
  }

  // 2) 应用修改
  for (final mod in overlay.modified) {
    final next = <CourseSession>[];
    var placed = false;
    for (final session in sessions) {
      if (courseKey(session) != mod.targetKey) {
        next.add(session);
        continue;
      }
      if (mod.scope == 'all') {
        if (!placed) {
          next.add(mod.replacement);
          placed = true;
        }
        continue; // 丢弃原始课程
      }
      final week = mod.week;
      if (week == null || !session.weeks.contains(week)) {
        next.add(session);
        continue;
      }
      final remaining = session.weeks.where((w) => w != week).toSet();
      if (remaining.isNotEmpty) next.add(session.copyWith(weeks: remaining));
      next.add(mod.replacement.copyWith(weeks: {week}));
    }
    sessions = next;
  }

  // 3) 追加新增
  sessions = [...sessions, ...overlay.added];

  return TimetableData(
    termName: official.termName,
    totalWeeks: official.totalWeeks,
    sessions: sessions,
    isSample: official.isSample,
    currentWeek: official.currentWeek,
    termStartDate: official.termStartDate,
    exams: official.exams,
  );
}

const _cnWeekdays = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];

/// 把周次集合压成可读文本，如 {1..16} → 「第1-16周」。
String _weeksText(Set<int> weeks) {
  if (weeks.isEmpty) return '';
  final sorted = weeks.toList()..sort();
  final parts = <String>[];
  var rangeStart = sorted.first;
  var previous = sorted.first;
  for (var i = 1; i < sorted.length; i++) {
    final current = sorted[i];
    if (current == previous + 1) {
      previous = current;
      continue;
    }
    parts.add(rangeStart == previous ? '$rangeStart' : '$rangeStart-$previous');
    rangeStart = current;
    previous = current;
  }
  parts.add(rangeStart == previous ? '$rangeStart' : '$rangeStart-$previous');
  return '第${parts.join('、')}周';
}

/// 一条冲突明细（课程 × 课程 / 课程 × 考试）。
class CourseConflict {
  const CourseConflict({
    required this.weeks,
    required this.day,
    required this.startPeriod,
    required this.endPeriod,
    required this.otherName,
    required this.isExam,
  });

  final Set<int> weeks;
  final int day;
  final int startPeriod;
  final int endPeriod;
  final String otherName;
  final bool isExam;

  String describe() {
    final dayLabel = _cnWeekdays[(day - 1).clamp(0, 6)];
    final periodLabel = startPeriod == endPeriod
        ? '第$startPeriod节'
        : '第$startPeriod-$endPeriod节';
    final kind = isExam ? '考试' : '课程';
    return '${_weeksText(weeks)} $dayLabel $periodLabel 与$kind「$otherName」冲突';
  }
}

/// 找出候选课程与 [sessions]/[exams] 的冲突。
///
/// 调用方应先把「正在编辑的课程」从 [sessions] 中排除，避免自我冲突。
/// [termStartDate] 缺失时跳过考试维度（无法把考试日期换算成教学周）。
List<CourseConflict> findConflicts({
  required List<CourseSession> sessions,
  required List<ExamEntry> exams,
  required CourseSession candidate,
  required int totalWeeks,
  DateTime? termStartDate,
}) {
  final conflicts = <CourseConflict>[];

  for (final other in sessions) {
    if (other.day != candidate.day) continue;
    final overlaps =
        candidate.startPeriod <= other.endPeriod &&
        other.startPeriod <= candidate.endPeriod;
    if (!overlaps) continue;
    final sharedWeeks = candidate.weeks.intersection(other.weeks);
    if (sharedWeeks.isEmpty) continue;
    conflicts.add(
      CourseConflict(
        weeks: sharedWeeks,
        day: candidate.day,
        startPeriod: candidate.startPeriod > other.startPeriod
            ? candidate.startPeriod
            : other.startPeriod,
        endPeriod: candidate.endPeriod < other.endPeriod
            ? candidate.endPeriod
            : other.endPeriod,
        otherName: other.name,
        isExam: false,
      ),
    );
  }

  if (termStartDate != null) {
    final base = TimetableData.mondayOf(termStartDate);
    for (final exam in exams) {
      final week =
          TimetableData.mondayOf(exam.date).difference(base).inDays ~/ 7 + 1;
      if (week < 1 || week > totalWeeks) continue;
      if (!candidate.weeks.contains(week)) continue;
      if (exam.date.weekday != candidate.day) continue;
      final examStart = PeriodTimes.parseTime(exam.startTime);
      final examEnd = PeriodTimes.parseTime(exam.endTime);
      var timeOverlap = true;
      if (examStart != null && examEnd != null) {
        final candStart = PeriodTimes.startMinutes(candidate.startPeriod);
        final candEnd = PeriodTimes.endMinutes(candidate.endPeriod);
        timeOverlap = candStart < examEnd && examStart < candEnd;
      }
      if (!timeOverlap) continue;
      conflicts.add(
        CourseConflict(
          weeks: {week},
          day: candidate.day,
          startPeriod: candidate.startPeriod,
          endPeriod: candidate.endPeriod,
          otherName: exam.name,
          isExam: true,
        ),
      );
    }
  }

  conflicts.sort((a, b) {
    final byDay = a.day.compareTo(b.day);
    if (byDay != 0) return byDay;
    return a.startPeriod.compareTo(b.startPeriod);
  });
  return conflicts;
}
