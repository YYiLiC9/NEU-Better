import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:neu_better_pro/core/network/notification_models.dart';
import 'package:neu_better_pro/features/notifications/notification_cache.dart';

AppNotification _item(int id, {bool read = false}) => AppNotification(
      logId: id,
      read: read,
      time: DateTime(2026, 3, 4, 5, 6),
      title: '标题$id',
      content: '内容$id',
      sourceName: '学工系统',
      url: 'https://example.com/$id',
      typeName: '校内通知',
    );

void main() {
  group('AppNotification JSON 往返', () {
    test('字段完整往返', () {
      final original = _item(101, read: true);
      final restored = appNotificationFromJson(
        appNotificationToJson(original),
      )!;
      expect(restored.logId, 101);
      expect(restored.read, isTrue);
      expect(restored.time, original.time);
      expect(restored.title, original.title);
      expect(restored.content, original.content);
      expect(restored.sourceName, original.sourceName);
      expect(restored.url, original.url);
      expect(restored.typeName, original.typeName);
    });

    test('缺少 logId 视为无效', () {
      expect(appNotificationFromJson(<String, dynamic>{'title': 'x'}), isNull);
    });
  });

  group('NotificationCacheStore 文件读写', () {
    late Directory dir;
    late File file;

    setUp(() {
      dir = Directory.systemTemp.createTempSync('notify_cache_');
      file = File('${dir.path}/notification_cache.json');
    });

    tearDown(() {
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    });

    test('写入后读出，total/noRead/items 一致', () async {
      final store = NotificationCacheStore(candidates: [file]);
      await store.write(
        NotificationCacheData(
          studentId: '20260001',
          fetchedAt: DateTime(2026, 3, 4, 5, 6),
          total: 12,
          noRead: 3,
          items: [_item(1), _item(2, read: true)],
        ),
      );
      final data = await store.read();
      expect(data, isNotNull);
      expect(data!.studentId, '20260001');
      expect(data.total, 12);
      expect(data.noRead, 3);
      expect(data.items, hasLength(2));
      expect(data.items[1].read, isTrue);
    });

    test('文件缺失返回 null', () async {
      final store = NotificationCacheStore(candidates: [file]);
      expect(await store.read(), isNull);
    });

    test('损坏 JSON 返回 null 且不抛出', () async {
      file.parent.createSync(recursive: true);
      file.writeAsStringSync('{ 不是合法 json');
      final store = NotificationCacheStore(candidates: [file]);
      expect(await store.read(), isNull);
    });
  });

  group('NotificationCache 账号隔离与上限', () {
    late Directory dir;
    late File file;
    late NotificationCache cache;

    setUp(() {
      dir = Directory.systemTemp.createTempSync('notify_cache_single_');
      file = File('${dir.path}/notification_cache.json');
      cache = NotificationCache(store: NotificationCacheStore(candidates: [file]));
    });

    tearDown(() async {
      await cache.clear();
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    });

    test('save 后 itemsFor/dataFor 命中，其他账号为空', () async {
      await cache.save('A', [_item(1), _item(2)], 2, 1);
      expect(cache.itemsFor('A'), hasLength(2));
      expect(cache.dataFor('A')!.total, 2);
      expect(cache.itemsFor('B'), isEmpty);
      expect(cache.dataFor('B'), isNull);
    });

    test('loadFor 其他账号返回空（不读旧数据）', () async {
      await cache.save('A', [_item(1)], 1, 0);
      final other = await cache.loadFor('B');
      expect(other, isNull);
      expect(cache.itemsFor('B'), isEmpty);
    });

    test('save 截断到 maxItems（30）', () async {
      await cache.save(
        'A',
        [for (var i = 0; i < 60; i++) _item(i)],
        60,
        60,
      );
      expect(cache.itemsFor('A'), hasLength(NotificationCacheStore.maxItems));
      final data = await NotificationCacheStore(candidates: [file]).read();
      expect(data!.items, hasLength(NotificationCacheStore.maxItems));
    });

    test('clear 清空内存与磁盘', () async {
      await cache.save('A', [_item(1)], 1, 0);
      await cache.clear();
      expect(cache.itemsFor('A'), isEmpty);
      expect(await NotificationCacheStore(candidates: [file]).read(), isNull);
    });
  });
}
