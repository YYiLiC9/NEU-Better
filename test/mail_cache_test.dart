import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:neu_better_pro/core/network/mail_client.dart';
import 'package:neu_better_pro/features/mail/mail_cache.dart';

MailSummary _mail(String id, {bool read = false}) => MailSummary(
      id: id,
      subject: '主题$id',
      from: '发件人$id',
      to: '我',
      receivedDate: DateTime(2026, 1, 2, 3, 4, 5),
      read: read,
      hasAttachment: false,
    );

void main() {
  group('MailSummary JSON 往返', () {
    test('字段完整往返', () {
      final original = MailSummary(
        id: '42',
        subject: '欢迎使用',
        from: 'admin@neu.edu.cn',
        to: 'student@neu.edu.cn',
        receivedDate: DateTime(2026, 11, 24, 9, 30),
        read: true,
        hasAttachment: true,
      );
      final restored = mailSummaryFromJson(mailSummaryToJson(original))!;
      expect(restored.id, original.id);
      expect(restored.subject, original.subject);
      expect(restored.from, original.from);
      expect(restored.to, original.to);
      expect(restored.receivedDate, original.receivedDate);
      expect(restored.read, isTrue);
      expect(restored.hasAttachment, isTrue);
    });

    test('id 为空视为无效项', () {
      expect(mailSummaryFromJson(<String, dynamic>{'subject': 'x'}), isNull);
      expect(mailSummaryFromJson(<String, dynamic>{'id': '   '}), isNull);
    });
  });

  group('MailCacheStore 文件读写', () {
    late Directory dir;
    late File file;

    setUp(() {
      dir = Directory.systemTemp.createTempSync('mail_cache_');
      file = File('${dir.path}/mail_cache.json');
    });

    tearDown(() {
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    });

    test('写入后读出，内容一致', () async {
      final store = MailCacheStore(candidates: [file]);
      await store.write(
        MailCacheData(
          studentId: '20260001',
          updatedAt: DateTime(2026, 11, 24),
          items: [_mail('1'), _mail('2', read: true)],
        ),
      );
      final data = await store.read();
      expect(data, isNotNull);
      expect(data!.studentId, '20260001');
      expect(data.items, hasLength(2));
      expect(data.items[1].id, '2');
      expect(data.items[1].read, isTrue);
    });

    test('文件缺失返回 null', () async {
      final store = MailCacheStore(candidates: [file]);
      expect(await store.read(), isNull);
    });

    test('损坏 JSON 返回 null 且不抛出', () async {
      file.parent.createSync(recursive: true);
      file.writeAsStringSync('{ 这不是合法 json');
      final store = MailCacheStore(candidates: [file]);
      expect(await store.read(), isNull);
    });
  });

  group('MailCache 账号隔离与上限', () {
    late Directory dir;
    late File file;
    late MailCache cache;

    setUp(() {
      dir = Directory.systemTemp.createTempSync('mail_cache_single_');
      file = File('${dir.path}/mail_cache.json');
      cache = MailCache(store: MailCacheStore(candidates: [file]));
    });

    tearDown(() async {
      await cache.clear();
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    });

    test('save 后 itemsFor 命中，其他账号为空', () async {
      await cache.save('A', [_mail('1')]);
      expect(cache.itemsFor('A'), hasLength(1));
      expect(cache.itemsFor('B'), isEmpty);
    });

    test('loadFor 其他账号返回空（不读旧数据）', () async {
      await cache.save('A', [_mail('1'), _mail('2')]);
      final other = await cache.loadFor('B');
      expect(other, isEmpty);
      expect(cache.itemsFor('B'), isEmpty);
    });

    test('save 截断到 maxItems（40）', () async {
      await cache.save(
        'A',
        [for (var i = 0; i < 80; i++) _mail('$i')],
      );
      expect(cache.itemsFor('A'), hasLength(MailCacheStore.maxItems));
      final data = await MailCacheStore(candidates: [file]).read();
      expect(data!.items, hasLength(MailCacheStore.maxItems));
    });

    test('clear 清空内存与磁盘', () async {
      await cache.save('A', [_mail('1')]);
      await cache.clear();
      expect(cache.itemsFor('A'), isEmpty);
      expect(await MailCacheStore(candidates: [file]).read(), isNull);
    });
  });
}
