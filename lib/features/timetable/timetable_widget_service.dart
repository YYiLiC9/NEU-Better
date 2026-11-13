import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'timetable_models.dart';
import 'timetable_schedule.dart';

/// 把课表数据导出到 Android 桌面小部件（原生侧计算并渲染今日课程）。
class TimetableWidgetService {
  static const MethodChannel _channel = MethodChannel('neu_better/widget');

  static String _date(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  static Future<void> sync(TimetableData data) async {
    if (!Platform.isAndroid) return;
    try {
      final schedule = TimetableSchedule(data);
      final week = schedule.nowWeek();
      final monday = schedule.weekStartFor(week) ?? _mondayOf(DateTime.now());
      final courses = data.sessions
          .map(
            (s) => <String, dynamic>{
              'name': s.name,
              'room': s.room,
              'teacher': s.teacher,
              'day': s.day,
              'startTime': PeriodTimes.startLabel(s.startPeriod),
              'endTime': PeriodTimes.endLabel(s.endPeriod),
              'weeks': (s.weeks.toList()..sort()),
            },
          )
          .toList();
      final exams = data.exams
          .map(
            (e) => <String, dynamic>{
              'name': e.name,
              'room': e.room,
              'teacher': '',
              'date': _date(e.date),
              'startTime': e.startTime ?? '',
              'endTime': e.endTime ?? '',
            },
          )
          .toList();
      final payload = jsonEncode(<String, dynamic>{
        'anchorDate': _date(monday),
        'anchorWeek': week,
        'courses': courses,
        'exams': exams,
      });
      await _channel.invokeMethod<void>('update', {'payload': payload});
    } catch (error) {
      debugPrint('[widget] sync failed: $error');
    }
  }

  static DateTime _mondayOf(DateTime d) {
    final day = DateTime(d.year, d.month, d.day);
    return day.subtract(Duration(days: day.weekday - 1));
  }
}
