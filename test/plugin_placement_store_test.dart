import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neu_better_pro/core/plugins/plugin_models.dart';
import 'package:neu_better_pro/core/plugins/plugin_placement_store.dart';
import 'package:neu_better_pro/features/home/home_card_catalog.dart';
import 'package:neu_better_pro/features/home/home_page.dart' show HomeCardGallery;

PluginManifest _manifest(String id) => PluginManifest(
  id: id,
  name: '演示插件',
  description: '演示',
  version: '1.0.0',
  minAppVersion: '1.0.0',
  rendererVersion: 1,
  startPage: 'home',
  pages: const <String, PluginPageSpec>{
    'home': PluginPageSpec(title: '首页', body: <PluginComponentSpec>[]),
  },
  raw: const <String, Object?>{},
);

void main() {
  test('empty store reports none and no sidebar ids', () async {
    final dir = await Directory.systemTemp.createTemp('placement_empty_');
    final store = PluginPlacementStore(
      candidates: <File>[File('${dir.path}/plugin_placements.json')],
    );
    await store.load();
    expect(store.appearanceOf('demo'), const PluginAppearance());
    expect(store.sidebarIds, isEmpty);
    expect(store.appearances, isEmpty);
  });

  test('builtin ids default to home, remote ids default to none', () {
    expect(defaultPluginAppearance('dorm').home, isTrue);
    expect(defaultPluginAppearance('notify').home, isTrue);
    expect(defaultPluginAppearance('mail').home, isTrue);
    expect(defaultPluginAppearance('demo').none, isTrue);
  });

  test('setAppearance round-trips both flags and sidebar order', () async {
    final dir = await Directory.systemTemp.createTemp('placement_round_');
    final file = File('${dir.path}/plugin_placements.json');
    final store = PluginPlacementStore(candidates: <File>[file]);
    await store.load();

    await store.setAppearance('a', const PluginAppearance(home: true));
    await store.setAppearance('b', const PluginAppearance(sidebar: true));
    await store.setAppearance('c', const PluginAppearance(sidebar: true));
    await store.setAppearance(
      'both',
      const PluginAppearance(home: true, sidebar: true),
    );
    expect(store.sidebarIds, <String>['b', 'c', 'both']);

    final reloaded = PluginPlacementStore(candidates: <File>[file]);
    await reloaded.load();
    expect(reloaded.appearanceOf('a').home, isTrue);
    expect(reloaded.appearanceOf('a').sidebar, isFalse);
    expect(reloaded.appearanceOf('b').sidebar, isTrue);
    expect(reloaded.appearanceOf('both').home, isTrue);
    expect(reloaded.appearanceOf('both').sidebar, isTrue);
    expect(reloaded.sidebarIds, <String>['b', 'c', 'both']);
  });

  test('clearing both flags removes sidebar membership', () async {
    final dir = await Directory.systemTemp.createTemp('placement_none_');
    final file = File('${dir.path}/plugin_placements.json');
    final store = PluginPlacementStore(candidates: <File>[file]);
    await store.load();

    await store.setAppearance('a', const PluginAppearance(sidebar: true));
    expect(store.sidebarIds, <String>['a']);
    await store.setAppearance('a', const PluginAppearance());
    expect(store.appearanceOf('a').none, isTrue);
    expect(store.sidebarIds, isEmpty);

    await store.setAppearance('b', const PluginAppearance(sidebar: true));
    await store.remove('b');
    expect(store.appearanceOf('b').none, isTrue);
    expect(store.sidebarIds, isEmpty);
  });

  test('removing sidebar keeps home flag and drops sidebar order', () async {
    final dir = await Directory.systemTemp.createTemp('placement_toggle_');
    final file = File('${dir.path}/plugin_placements.json');
    final store = PluginPlacementStore(candidates: <File>[file]);
    await store.load();

    await store.setAppearance(
      'a',
      const PluginAppearance(home: true, sidebar: true),
    );
    expect(store.sidebarIds, <String>['a']);
    await store.setAppearance('a', const PluginAppearance(home: true));
    expect(store.appearanceOf('a').home, isTrue);
    expect(store.appearanceOf('a').sidebar, isFalse);
    expect(store.sidebarIds, isEmpty);
  });

  test('legacy string placements migrate to PluginAppearance', () async {
    final dir = await Directory.systemTemp.createTemp('placement_legacy_');
    final file = File('${dir.path}/plugin_placements.json');
    await file.writeAsString(
      '{"placements":{"a":"home","b":"sidebar","c":"none"},'
      '"sidebarOrder":["b"]}',
    );
    final store = PluginPlacementStore(candidates: <File>[file]);
    await store.load();
    expect(store.appearanceOf('a').home, isTrue);
    expect(store.appearanceOf('a').sidebar, isFalse);
    expect(store.appearanceOf('b').sidebar, isTrue);
    expect(store.appearanceOf('c').none, isTrue);
    expect(store.sidebarIds, <String>['b']);
  });

  test('reorderSidebar persists a custom order', () async {
    final dir = await Directory.systemTemp.createTemp('placement_order_');
    final file = File('${dir.path}/plugin_placements.json');
    final store = PluginPlacementStore(candidates: <File>[file]);
    await store.load();

    await store.setAppearance('b', const PluginAppearance(sidebar: true));
    await store.setAppearance('c', const PluginAppearance(sidebar: true));
    expect(store.sidebarCustomOrder, isFalse);
    await store.reorderSidebar(<String>['c', 'b']);
    expect(store.sidebarCustomOrder, isTrue);
    expect(store.sidebarIds, <String>['c', 'b']);

    final reloaded = PluginPlacementStore(candidates: <File>[file]);
    await reloaded.load();
    expect(reloaded.sidebarCustomOrder, isTrue);
    expect(reloaded.sidebarIds, <String>['c', 'b']);
  });

  test('corrupt file falls back to empty without throwing', () async {
    final dir = await Directory.systemTemp.createTemp('placement_bad_');
    final file = File('${dir.path}/plugin_placements.json');
    await file.writeAsString('{not valid json');
    final store = PluginPlacementStore(candidates: <File>[file]);
    await store.load();
    expect(store.appearanceOf('demo').none, isTrue);
    expect(store.sidebarIds, isEmpty);
  });

  testWidgets('gallery shows home/sidebar chips and toggles independently', (
    tester,
  ) async {
    var appearances = <String, PluginAppearance>{};
    String? lastId;
    PluginAppearance? lastAppearance;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => HomeCardGallery(
              cards: const [],
              builtins: <HomeCardInfo>[homeCardInfo('dorm')!],
              plugins: <PluginManifest>[_manifest('demo')],
              installedVersions: const <String, String>{'demo': '1.0.0'},
              appearances: appearances,
              allowPlacementOptions: true,
              onBack: () {},
              onAdd: (_) {},
              onSetAppearance: (id, appearance) {
                lastId = id;
                lastAppearance = appearance;
                setState(() => appearances = {...appearances, id: appearance});
              },
            ),
          ),
        ),
      ),
    );

    // 放置选项默认折叠，先展开内置与远程两项。
    await tester.tap(find.byKey(const ValueKey('placement-dropdown-dorm')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('placement-dropdown-demo')));
    await tester.pumpAndSettle();

    // 内置与远程已下载都展示三选项。
    expect(find.text('添加到首页'), findsNWidgets(3));
    expect(find.text('添加到侧栏'), findsNWidgets(2));
    expect(find.text('不添加'), findsNWidgets(3));
    // 远程默认未添加，内置默认首页。
    expect(find.byKey(const ValueKey('appearance-home-dorm')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('appearance-home-demo')));
    await tester.pumpAndSettle();
    expect(lastId, 'demo');
    expect(lastAppearance!.home, isTrue);
    expect(lastAppearance!.sidebar, isFalse);

    // 再次点击取消首页。
    await tester.tap(find.byKey(const ValueKey('appearance-home-demo')));
    await tester.pumpAndSettle();
    expect(lastAppearance!.home, isFalse);

    // 添加到侧栏。
    await tester.tap(find.byKey(const ValueKey('appearance-sidebar-demo')));
    await tester.pumpAndSettle();
    expect(lastAppearance!.sidebar, isTrue);
  });
}
