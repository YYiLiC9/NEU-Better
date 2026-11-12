import 'dart:convert';

import 'timetable_models.dart';

/// Converts the payload returned by the graduate course-selection system's
/// `loadKbxx.do` endpoint into the shared timetable model.
///
/// The source endpoint returns `skjcList` as a JSON string, while the course
/// rows live in `results`. Keeping this parser pure makes it testable without
/// a WebView or a real student account.
/// Converts the payload of the new graduate platform's
/// `wdkbapp/xskcb/xspkjgcx.do` endpoint into the shared timetable model.
abstract final class YjsTimetableParser {
  static TimetableData parse(
    String payload, {
    String? fallbackTermName,
    int? currentWeek,
    String? examBody,
    DateTime? termStartDate,
  }) {
    final decoded = jsonDecode(payload);
    if (decoded is! Map) {
      throw const FormatException('课表返回格式不正确');
    }
    final root = Map<String, dynamic>.from(decoded);
    final datas = YjsxkTimetableParser._asMap(root['datas']);
    final schedule = YjsxkTimetableParser._asMap(datas['xspkjgcx']);
    final rows = YjsxkTimetableParser._asList(schedule['rows']);
    if (rows.isEmpty) {
      final message = YjsxkTimetableParser._firstNonEmpty([
        YjsxkTimetableParser._string(root['msg']),
        YjsxkTimetableParser._string(root['message']),
      ]);
      throw FormatException(message ?? '教务系统没有返回课程安排');
    }

    final sessions = <CourseSession>[];
    var maxWeek = 0;
    for (var index = 0; index < rows.length; index++) {
      final row = YjsxkTimetableParser._asMap(rows[index]);
      if (row.isEmpty) continue;
      final name = _value(row, const ['KCMC', 'KCM', 'COURSE_NAME']);
      if (name.isEmpty) continue;
      final day = _intValue(row, const ['XQJ', 'XQ', 'WEEKDAY']);
      final start = _intValue(row, const [
        'KSJC',
        'KSJCDM',
        'KJC',
        'START_PERIOD',
      ]);
      final end = _intValue(row, const ['JSJC', 'JSJCDM', 'EJC', 'END_PERIOD']);
      if (day < 1 || day > 7 || start < 1) continue;
      final weeks = YjsxkTimetableParser.parseWeeks(
        _value(row, const ['ZCMC', 'SKZC', 'ZCM', 'WEEKS']),
      );
      if (weeks.isEmpty) continue;
      maxWeek = [maxWeek, ...weeks].reduce((a, b) => a > b ? a : b);
      sessions.add(
        CourseSession(
          id:
              YjsxkTimetableParser._firstNonEmpty([
                _value(row, const ['WID', 'ID', 'KCDM']),
                '${_value(row, const ['BJDM', 'CLASS_ID'])}-$index',
              ]) ??
              '$index',
          name: name,
          teacher: _value(row, const ['SKJS', 'JSXM', 'RKJS', 'TEACHER']),
          room: _value(row, const ['SKDD', 'JASMC', 'JAS', 'ROOM']),
          className: _value(row, const ['BJMC', 'CLASS_NAME']),
          day: day,
          startPeriod: start,
          endPeriod: end < start ? start : end,
          weeks: weeks,
        ),
      );
    }

    final unique =
        <String, CourseSession>{
          for (final session in sessions) session.id: session,
        }.values.toList()..sort((a, b) {
          if (a.day != b.day) return a.day.compareTo(b.day);
          return a.startPeriod.compareTo(b.startPeriod);
        });
    if (unique.isEmpty) {
      throw const FormatException('教务系统没有返回可显示的课程');
    }
    final rawTerm = _value(rows.first, const ['XNXQMC', 'XNXQ', 'XNXQDM']);
    final termName = rawTerm == '20261'
        ? '2026–2027 秋季学期'
        : (YjsxkTimetableParser._firstNonEmpty([
                rawTerm,
                fallbackTermName,
                '研究生课程表',
              ]) ??
              '研究生课程表');
    return TimetableData(
      termName: termName,
      totalWeeks: maxWeek < 16 ? 16 : maxWeek,
      currentWeek: currentWeek ?? 8,
      sessions: unique,
      isSample: false,
      termStartDate: termStartDate,
      exams: examBody == null || examBody.trim().isEmpty
          ? const []
          : parseExams(examBody),
    );
  }

  /// Extracts exam entries from an exam-list endpoint response.
  ///
  /// Real shape (2026-11-10, `wdkwapp/api/wdks/queryMyExamArrangeMent.do`):
  /// `datas.queryMyExamArrangeMent.arranged` is a list of scheduled exams with
  /// fields `KCM` (name), `KSRQ` (yyyy-MM-dd), `KSSJ`/`JSSJ` (HH:mm),
  /// `KSSJMS` (display text), `JASMC` (room), `ZWH` (seat), `SKJS` (teacher),
  /// `KSLXDM_DISPLAY` (type). `notArranged` uses the same course keys without a
  /// time/room/seat. The tree walk below also tolerates older deployments.
  static List<ExamEntry> parseExams(String body) {
    final List<Map<String, dynamic>> rows;
    try {
      final decoded = jsonDecode(body);
      // 优先取已排考 `arranged`（有具体时间/地点，排成卡片）。当本次响应
      // `arranged` 为空（例如考试改期待排）时回退到深度搜索，把 `notArranged`
      // 里有日期、暂无时间的考试也显示出来，保证「读到课表就能读到考试信息」，
      // 不让考试凭空消失。
      final arranged = _arrangedExamRows(decoded);
      rows = (arranged == null || arranged.isEmpty)
          ? _findExamRows(decoded)
          : arranged;
    } catch (_) {
      return const [];
    }
    final exams = <ExamEntry>[];
    for (var index = 0; index < rows.length; index++) {
      final row = rows[index];
      final name = _value(row, const [
        'KCM',
        'KSMC',
        'KCMC',
        'SKCMC',
        'KCMS',
        'EXAM_NAME',
      ]);
      if (name.isEmpty) continue;
      final summary = _value(row, const ['KSSJMS', 'EXAM_TIME_DISPLAY']);
      var rawDate = _value(row, const ['KSRQ', 'KSRQJC', 'KAYY', 'EXAM_DATE']);
      if (rawDate.isEmpty) rawDate = summary;
      final date = ExamEntry.parseDate(rawDate.replaceAll('.', '-'));
      if (date == null) continue;
      final (startTime, endTime) = _examTimes(row, summary);
      final id = _value(row, const ['WID', 'ID', 'KSDM', 'EXAM_ID']);
      exams.add(
        ExamEntry(
          id: id.isEmpty ? 'exam-$index' : id,
          name: name,
          date: date,
          startTime: startTime,
          endTime: endTime,
          room: _value(row, const [
            'JASMC',
            'JXDD',
            'KSCD',
            'KSDD',
            'SKDD',
            'JSDD',
            'ROOM',
          ]),
          seat: _value(row, const ['ZWH', 'ZKZH', 'SEAT']),
          type: _value(row, const [
            'KSLXDM_DISPLAY',
            'KSLXMC',
            'KSLX',
            'LXMC',
            'TYPE',
          ]),
        ),
      );
    }
    exams.sort((a, b) => a.date.compareTo(b.date));
    return exams;
  }

  /// Resolves start/end times from explicit `KSSJ`/`JSSJ` fields first, then
  /// falls back to the Chinese display text (`2026年10月25日 13:50-15:50`).
  static (String?, String?) _examTimes(
    Map<String, dynamic> row,
    String summary,
  ) {
    final startRaw = _value(row, const [
      'KSSJ',
      'KSSJD',
      'KSSKSSJ',
      'KASJ',
      'EXAM_TIME',
    ]);
    final endRaw = _value(row, const ['JSSJ', 'KSSJJSSJ', 'JASJ', 'END_TIME']);
    final summaryTimes = _examTime(summary);
    final startTimes = _examTime(startRaw);
    final endTimes = _examTime(endRaw);
    final start = startTimes.$1 ?? summaryTimes.$1;
    final end = endTimes.$1 ?? startTimes.$2 ?? summaryTimes.$2;
    return (start, end);
  }

  /// Exact `datas.queryMyExamArrangeMent.arranged` branch of the real API.
  /// Returns an empty list (not null) when the branch exists but is empty, so
  /// `notArranged` never leaks into the scheduled-exam cards.
  static List<Map<String, dynamic>>? _arrangedExamRows(Object? root) {
    if (root is! Map) return null;
    final datas = root['datas'];
    if (datas is! Map) return null;
    final entry = datas['queryMyExamArrangeMent'];
    if (entry is! Map) return null;
    final arranged = entry['arranged'];
    if (arranged is List) {
      return arranged
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList();
    }
    if (arranged is String && arranged.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(arranged);
        if (decoded is List) {
          return decoded
              .whereType<Map>()
              .map((item) => Map<String, dynamic>.from(item))
              .toList();
        }
      } catch (_) {
        // Fall through to the generic walk below.
      }
    }
    // No usable `arranged` branch: return null so the caller falls back to the
    // generic tree walk (which can surface `notArranged` exams that still have
    // a date) instead of silently reporting zero exams.
    return null;
  }

  /// Depth-first search for the first list whose entries look like exam rows.
  static List<Map<String, dynamic>> _findExamRows(Object? node) {
    if (node is List) {
      final maps = node
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList();
      if (maps.isNotEmpty &&
          maps.length == node.length &&
          _looksLikeExam(maps.first)) {
        return maps;
      }
      for (final item in node) {
        final found = _findExamRows(item);
        if (found.isNotEmpty) return found;
      }
    } else if (node is Map) {
      for (final value in node.values) {
        final found = _findExamRows(value);
        if (found.isNotEmpty) return found;
      }
    }
    return const [];
  }

  static bool _looksLikeExam(Map<String, dynamic> row) {
    return row.keys.any((key) {
      final upper = key.toString().toUpperCase();
      return const {
        'KCM',
        'KSMC',
        'KSRQ',
        'KSSJ',
        'KSSJMS',
        'JXDD',
        'JASMC',
        'KSCD',
      }.contains(upper);
    });
  }

  /// Splits an exam time field into start/end. Tolerates `14:00-16:00`,
  /// `14:00—15:30`, `1400-1520` and a lone `14:00`. Date text such as
  /// `2026年10月25日 13:50-15:50` is ignored by matching colon times first.
  static (String?, String?) _examTime(String raw) {
    if (raw.trim().isEmpty) return (null, null);
    final colonTokens = RegExp(r'\d{1,2}:\d{2}')
        .allMatches(raw)
        .map((m) => m.group(0)!)
        .toList();
    final tokens = <String>[];
    if (colonTokens.isNotEmpty) {
      tokens.addAll(colonTokens);
    } else {
      for (final match in RegExp(r'\d{3,4}').allMatches(raw)) {
        final before = match.start > 0 ? raw[match.start - 1] : '';
        final after = match.end < raw.length ? raw[match.end] : '';
        if (before == '年' || after == '年' || after == '月' || after == '日') {
          continue;
        }
        tokens.add(match.group(0)!);
      }
    }
    if (tokens.isEmpty) return (null, null);
    String normalize(String token) {
      if (token.contains(':')) return token;
      final padded = token.padLeft(4, '0');
      return '${padded.substring(0, 2)}:${padded.substring(2)}';
    }

    return (
      normalize(tokens.first),
      tokens.length > 1 ? normalize(tokens.last) : null,
    );
  }

  static String _value(Map<String, dynamic> row, List<String> keys) {
    for (final key in keys) {
      final value = row[key];
      if (value != null && value.toString().trim().isNotEmpty) {
        return value.toString().trim();
      }
    }
    return '';
  }

  static int _intValue(Map<String, dynamic> row, List<String> keys) {
    final raw = _value(row, keys);
    return int.tryParse(raw) ?? 0;
  }
}

abstract final class YjsxkTimetableParser {
  static TimetableData parse(String payload, {String? fallbackTermName}) {
    final decoded = jsonDecode(payload);
    if (decoded is! Map) {
      throw const FormatException('课表返回格式不正确');
    }

    final root = Map<String, dynamic>.from(decoded);
    final results = _asList(root['results']);
    final selected = _asList(root['xkjgList']);
    final termName =
        _firstNonEmpty([
          for (final item in selected) _string(item['XNXQMC']),
          fallbackTermName,
          '2026–2027 秋季学期',
        ]) ??
        '2026–2027 秋季学期';

    final sessions = <CourseSession>[];
    var maxWeek = 0;

    for (var index = 0; index < results.length; index++) {
      final row = _asMap(results[index]);
      if (row.isEmpty) continue;
      final name = _string(row['KCMC']);
      if (name.isEmpty) continue;
      final day = int.tryParse(_string(row['XQ'])) ?? 0;
      final start = int.tryParse(_string(row['KSJCDM'])) ?? 0;
      final end = int.tryParse(_string(row['JSJCDM'])) ?? start;
      if (day < 1 || day > 7 || start < 1) continue;

      final weeks = parseWeeks(_string(row['ZCMC']));
      if (weeks.isEmpty) continue;
      maxWeek = [maxWeek, ...weeks].reduce((a, b) => a > b ? a : b);

      sessions.add(
        CourseSession(
          id: _string(row['WID']).isEmpty
              ? '${_string(row['BJDM'])}-$index'
              : _string(row['WID']),
          name: name,
          teacher: _string(row['JSXM']),
          room: _string(row['JASMC']),
          className: _string(row['BJMC']),
          day: day,
          startPeriod: start,
          endPeriod: end < start ? start : end,
          weeks: weeks,
        ),
      );
    }

    // Keep the newest row for a duplicate arrangement id. This mirrors the
    // source page, which renders one card per WID.
    final unique =
        <String, CourseSession>{
          for (final session in sessions) session.id: session,
        }.values.toList()..sort((a, b) {
          if (a.day != b.day) return a.day.compareTo(b.day);
          return a.startPeriod.compareTo(b.startPeriod);
        });

    return TimetableData(
      termName: termName,
      totalWeeks: maxWeek < 16 ? 16 : maxWeek,
      sessions: unique,
      isSample: false,
    );
  }

  /// Parses forms such as `1-16周`, `1-8,10-16周`, `第1-16周`, `3周`.
  static Set<int> parseWeeks(String raw) {
    final value = raw.replaceAll(' ', '').replaceAll('第', '');
    final result = <int>{};
    final ranges = RegExp(r'(\d{1,2})(?:-(\d{1,2}))?').allMatches(value);
    for (final match in ranges) {
      final start = int.tryParse(match.group(1) ?? '');
      if (start == null) continue;
      final end = int.tryParse(match.group(2) ?? '') ?? start;
      if (start < 1 || end < start || end > 30) continue;
      for (var week = start; week <= end; week++) {
        result.add(week);
      }
    }
    return result;
  }

  static List<dynamic> _asList(Object? value) {
    if (value is List) return value;
    if (value is String && value.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(value);
        if (decoded is List) return decoded;
      } catch (_) {
        // Fall through to an empty list.
      }
    }
    return const [];
  }

  static Map<String, dynamic> _asMap(Object? value) {
    if (value is Map) return Map<String, dynamic>.from(value);
    return const {};
  }

  static String _string(Object? value) => value?.toString().trim() ?? '';

  static String? _firstNonEmpty(Iterable<String?> values) {
    for (final value in values) {
      if (value != null && value.trim().isNotEmpty) return value.trim();
    }
    return null;
  }
}
