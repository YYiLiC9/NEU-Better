import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:neu_better_pro/core/models/news_models.dart';
import 'package:neu_better_pro/features/news/news_store.dart';

void main() {
  late Directory dir;
  late File prefsFile;
  late File cacheFile;
  late NewsStore store;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('news_store_test');
    prefsFile = File('${dir.path}/news_prefs.json');
    cacheFile = File('${dir.path}/news_sections_cache.json');
    store = NewsStore(
      candidates: <File>[prefsFile],
      cacheCandidates: <File>[cacheFile],
    );
  });

  tearDown(() async {
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  test('缺失时返回默认偏好（仅校内通知）', () async {
    final prefs = await store.readPrefs();
    expect(prefs.selectedCids, <String>[NewsPrefs.internalNoticeId]);
  });

  test('prefs 保存与读取往返', () async {
    await store.savePrefs(
      const NewsPrefs(
        selectedCids: <String>[NewsPrefs.internalNoticeId, 'cid-x'],
      ),
    );
    expect(await prefsFile.exists(), isTrue);
    final loaded = await store.readPrefs();
    expect(
      loaded.selectedCids,
      <String>[NewsPrefs.internalNoticeId, 'cid-x'],
    );
  });

  test('损坏 prefs 回退默认', () async {
    await prefsFile.writeAsString('{not json');
    final loaded = await store.readPrefs();
    expect(loaded.selectedCids, <String>[NewsPrefs.internalNoticeId]);
  });

  test('栏目缓存往返并标记新鲜', () async {
    const sections = <NewsSection>[
      NewsSection(id: 'c1', name: '东大要闻', group: '新闻资讯'),
      NewsSection(id: 'c2', name: '通知公告', group: '通知公告'),
    ];
    await store.saveSectionsCache(sections);
    final cache = await store.readSectionsCache();
    expect(cache, isNotNull);
    expect(cache!.sections, hasLength(2));
    expect(cache.sections.first.id, 'c1');
    expect(cache.sections.first.name, '东大要闻');
    expect(cache.isFresh, isTrue);
    final raw = jsonDecode(await cacheFile.readAsString()) as Map;
    expect((raw['sections'] as List), hasLength(2));
  });
}
