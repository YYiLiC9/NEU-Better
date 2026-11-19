import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:neu_better_pro/core/network/notification_models.dart';
import 'package:neu_better_pro/core/settings/app_settings.dart';
import 'package:neu_better_pro/features/notifications/notification_store.dart';

void main() {
  group('parseCounts', () {
    test('reads noReadCount and count', () {
      final counts = parseCounts({
        'e': 0,
        'd': {'noReadCount': 8, 'count': 10, 'readCount': 2},
      });
      expect(counts.noRead, 8);
      expect(counts.total, 10);
    });

    test('falls back safely on malformed payload', () {
      final counts = parseCounts(null);
      expect(counts.noRead, 0);
      expect(counts.total, 0);
    });
  });

  group('parseIndex', () {
    test('parses list items with fields', () {
      final items = parseIndex({
        'e': 0,
        'd': {
          'list': [
            {
              'log_id': 101,
              'has_read': false,
              'time': '2026-11-18 09:30:00',
              'source_name': '学生工作处',
              'ucs_type_name': '通知',
              'title': '关于选课的通知',
              'content': '请于本周内完成选课',
              'url': '',
            },
            {
              'log_id': 102,
              'has_read': 1,
              'time': '2026-11-17 08:00:00',
              'ucs_type_name': '公告',
              'title': '停水公告',
              'content': '   ',
            },
          ],
        },
      });
      expect(items, hasLength(2));
      expect(items.first.logId, 101);
      expect(items.first.read, isFalse);
      expect(items.first.sourceName, '学生工作处');
      expect(items.first.time, DateTime(2026, 11, 18, 9, 30));
      expect(items.first.preview, '请于本周内完成选课');
      expect(items[1].read, isTrue);
      expect(items[1].sourceName, '公告');
    });

    test('skips items without log_id and handles empty list', () {
      expect(
        parseIndex({
          'd': {
            'list': [
              {'title': 'no id'},
            ],
          },
        }),
        isEmpty,
      );
      expect(parseIndex(null), isEmpty);
    });
  });

  group('NotificationStore', () {
    late Directory dir;
    late File file;

    setUp(() {
      dir = Directory.systemTemp.createTempSync('notify_store_');
      file = File('${dir.path}/notification_state.json');
    });

    tearDown(() {
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    });

    test('round-trips baseline, notified ids and local reads', () async {
      final store = NotificationStore(candidates: [file]);
      await store.load();
      store.setBaseline(5);
      expect(store.takeNewUnnotified([1, 2]), [1, 2]);
      expect(store.takeNewUnnotified([1, 2]), isEmpty);
      await store.markLocalRead(2);
      await store.save();
      expect(store.isRead(2, serverRead: false), isTrue);

      final restored = NotificationStore(candidates: [file]);
      await restored.load();
      expect(restored.lastNoRead, 5);
      expect(restored.notifiedIds, {1, 2});
      expect(restored.isRead(2, serverRead: false), isTrue);
      expect(restored.takeNewUnnotified([1, 2, 3]), [3]);
    });

    test('corrupt state falls back to empty', () async {
      file.writeAsStringSync('{not json');
      final store = NotificationStore(candidates: [file]);
      await store.load();
      expect(store.lastNoRead, 0);
      expect(store.notifiedIds, isEmpty);
    });
  });

  group('AppSettings.notifySources', () {
    test('builtin sources default on, plugin sources default off', () {
      final controller = AppSettingsController(initial: const AppSettings());
      expect(controller.notifyEnabled('campus'), isTrue);
      expect(controller.notifyEnabled('dorm'), isTrue);
      expect(controller.notifyEnabled('mail'), isTrue);
      expect(controller.notifyEnabled('plugin:library'), isFalse);
    });

    test('explicit map overrides defaults', () {
      final controller = AppSettingsController(
        initial: const AppSettings(notifySources: {'campus': false, 'plugin:library': true}),
      );
      expect(controller.notifyEnabled('campus'), isFalse);
      expect(controller.notifyEnabled('plugin:library'), isTrue);
      expect(controller.notifySources['campus'], isFalse);
    });
  });
}
