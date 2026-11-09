import 'dart:convert';

import 'timetable_models.dart';

/// Converts the payload returned by the graduate course-selection system's
/// `loadKbxx.do` endpoint into the shared timetable model.
///
/// The source endpoint returns `skjcList` as a JSON string, while the course
/// rows live in `results`. Keeping this parser pure makes it testable without
/// a WebView or a real student account.
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
    final unique = <String, CourseSession>{
      for (final session in sessions) session.id: session,
    }.values.toList()
      ..sort((a, b) {
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
