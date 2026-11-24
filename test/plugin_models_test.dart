import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:neu_better_pro/core/plugins/plugin_models.dart';

const String _indexJson = '''
{
  "version": 1,
  "plugins": [
    {
      "id": "library",
      "name": "图书馆",
      "description": "馆藏检索与借阅",
      "version": "1.0.0",
      "minAppVersion": "0.3.1",
      "rendererVersion": 1,
      "icon": {"type": "material", "value": "menu_book"},
      "card": {"title": "图书馆", "subtitle": "馆藏 / 借阅"},
      "startPage": "home",
      "pages": {
        "home": {"title": "图书馆", "body": [
          {"type": "text", "style": "title", "value": "热门馆藏"}
        ]},
        "detail": {"title": "详情", "body": [
          {"type": "text", "value": "{{title}}"}
        ]}
      }
    }
  ]
}
''';

void main() {
  test('parses valid catalog and manifest', () {
    final catalog = PluginCatalog.fromJson(jsonDecode(_indexJson));
    expect(catalog.version, 1);
    expect(catalog.plugins, hasLength(1));
    final manifest = catalog.plugins.single;
    expect(manifest.id, 'library');
    expect(manifest.name, '图书馆');
    expect(manifest.version, '1.0.0');
    expect(manifest.rendererVersion, 1);
    expect(manifest.rendererSupported, isTrue);
    expect(manifest.startPage, 'home');
    expect(manifest.pages.keys, containsAll(['home', 'detail']));
    expect(manifest.pages['home']!.body.single.type, 'text');
    expect(manifest.cardTitle, '图书馆');
    expect(manifest.icon!.value, 'menu_book');
    expect(manifest.enabled, 1);
    expect(manifest.isEnabled, isTrue);
  });

  test('enabled=0 parses as disabled and keeps manifest', () {
    final json = jsonDecode(_indexJson) as Map<String, dynamic>;
    (json['plugins'] as List)[0]['enabled'] = 0;
    final manifest = PluginCatalog.fromJson(json).plugins.single;
    expect(manifest.enabled, 0);
    expect(manifest.isEnabled, isFalse);
  });

  test('rejects illegal id', () {
    final bad = jsonDecode(_indexJson) as Map<String, dynamic>;
    (bad['plugins'] as List)[0]['id'] = 'Bad ID';
    expect(PluginCatalog.fromJson(bad).plugins, isEmpty);
  });

  test('rejects manifest with startPage missing from pages', () {
    final bad = jsonDecode(_indexJson) as Map<String, dynamic>;
    (bad['plugins'] as List)[0]['startPage'] = 'nope';
    expect(PluginCatalog.fromJson(bad).plugins, isEmpty);
  });

  test('rendererVersion too high is parsed but unsupported', () {
    final high = jsonDecode(_indexJson) as Map<String, dynamic>;
    (high['plugins'] as List)[0]['rendererVersion'] = 99;
    final manifest = PluginCatalog.fromJson(high).plugins.single;
    expect(manifest.rendererSupported, isFalse);
  });

  test('duplicate ids are skipped', () {
    final dup = jsonDecode(_indexJson) as Map<String, dynamic>;
    final plugin = (dup['plugins'] as List).first;
    (dup['plugins'] as List).add(plugin);
    expect(PluginCatalog.fromJson(dup).plugins, hasLength(1));
  });

  test('interpolateTemplate substitutes fields and nested keys', () {
    expect(
      interpolateTemplate('{{title}} / {{book.author}} / {{missing}}', {
        'title': '三体',
        'book.author': '刘慈欣',
      }),
      '三体 / 刘慈欣 / ',
    );
  });

  test('toJson round-trips through PluginManifest', () {
    final manifest = PluginCatalog.fromJson(jsonDecode(_indexJson)).plugins.single;
    final again = PluginManifest.fromJson(manifest.toJson());
    expect(again, isNotNull);
    expect(again!.id, manifest.id);
    expect(again.pages.length, manifest.pages.length);
  });

  test('repository plugins/index.json parses into a valid catalog', () {
    final file = File('plugins/index.json');
    expect(file.existsSync(), isTrue, reason: '示例插件目录应存在');
    final catalog = PluginCatalog.fromJson(jsonDecode(file.readAsStringSync()));
    expect(catalog.plugins, isNotEmpty);
    final library = catalog.byId('library');
    expect(library, isNotNull);
    expect(library!.rendererSupported, isTrue);
    expect(library.pages.containsKey(library.startPage), isTrue);
    expect(library.isEnabled, isFalse);
    expect(catalog.byId('news')!.isEnabled, isTrue);
  });
}
