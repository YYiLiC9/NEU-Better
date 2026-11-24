import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neu_better_pro/core/plugins/plugin_models.dart';
import 'package:neu_better_pro/core/plugins/plugin_placement_store.dart';
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
    expect(store.placementOf('demo'), PluginPlacement.none);
    expect(store.sidebarIds, isEmpty);
    expect(store.placements, isEmpty);
  });

  test('set and reload round-trips placements and sidebar order', () async {
    final dir = await Directory.systemTemp.createTemp('placement_round_');
    final file = File('${dir.path}/plugin_placements.json');
    final store = PluginPlacementStore(candidates: <File>[file]);
    await store.load();

    await store.setPlacement('a', PluginPlacement.home);
    await store.setPlacement('b', PluginPlacement.sidebar);
    await store.setPlacement('c', PluginPlacement.sidebar);
    expect(store.sidebarIds, <String>['b', 'c']);

    final reloaded = PluginPlacementStore(candidates: <File>[file]);
    await reloaded.load();
    expect(reloaded.placementOf('a'), PluginPlacement.home);
    expect(reloaded.placementOf('b'), PluginPlacement.sidebar);
    expect(reloaded.placementOf('c'), PluginPlacement.sidebar);
    expect(reloaded.sidebarIds, <String>['b', 'c']);
    expect(reloaded.placements['a'], PluginPlacement.home);
  });

  test('none removes placement and sidebar membership', () async {
    final dir = await Directory.systemTemp.createTemp('placement_none_');
    final file = File('${dir.path}/plugin_placements.json');
    final store = PluginPlacementStore(candidates: <File>[file]);
    await store.load();

    await store.setPlacement('a', PluginPlacement.sidebar);
    expect(store.sidebarIds, <String>['a']);
    await store.setPlacement('a', PluginPlacement.none);
    expect(store.placementOf('a'), PluginPlacement.none);
    expect(store.sidebarIds, isEmpty);

    await store.setPlacement('b', PluginPlacement.sidebar);
    await store.remove('b');
    expect(store.placementOf('b'), PluginPlacement.none);
    expect(store.sidebarIds, isEmpty);
  });

  test('home placement drops the plugin out of sidebar order', () async {
    final dir = await Directory.systemTemp.createTemp('placement_home_');
    final file = File('${dir.path}/plugin_placements.json');
    final store = PluginPlacementStore(candidates: <File>[file]);
    await store.load();

    await store.setPlacement('a', PluginPlacement.sidebar);
    expect(store.sidebarIds, <String>['a']);
    await store.setPlacement('a', PluginPlacement.home);
    expect(store.placementOf('a'), PluginPlacement.home);
    expect(store.sidebarIds, isEmpty);
  });

  test('corrupt file falls back to empty without throwing', () async {
    final dir = await Directory.systemTemp.createTemp('placement_bad_');
    final file = File('${dir.path}/plugin_placements.json');
    await file.writeAsString('{not valid json');
    final store = PluginPlacementStore(candidates: <File>[file]);
    await store.load();
    expect(store.placementOf('demo'), PluginPlacement.none);
    expect(store.sidebarIds, isEmpty);
  });

  testWidgets('downloaded plugin offers an inline placement selector', (
    tester,
  ) async {
    PluginPlacement? chosen;
    String? chosenId;
    final placements = <String, PluginPlacement>{};
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => HomeCardGallery(
              cards: const [],
              builtins: const [],
              plugins: <PluginManifest>[_manifest('demo')],
              installedVersions: const <String, String>{'demo': '1.0.0'},
              placements: Map<String, PluginPlacement>.from(placements),
              allowSidebar: true,
              onBack: () {},
              onAdd: (_) {},
              onSetPlacement: (id, placement) {
                chosenId = id;
                chosen = placement;
                setState(() => placements[id] = placement);
              },
            ),
          ),
        ),
      ),
    );

    expect(find.text('演示插件'), findsOneWidget);
    expect(find.text('未添加'), findsOneWidget);
    expect(find.text('添加到侧栏'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('placement-demo')));
    await tester.pumpAndSettle();
    expect(find.text('添加到首页'), findsOneWidget);
    expect(find.text('添加到侧栏'), findsOneWidget);

    await tester.tap(find.text('添加到侧栏'));
    await tester.pumpAndSettle();
    expect(chosenId, 'demo');
    expect(chosen, PluginPlacement.sidebar);
    expect(find.text('添加到侧栏'), findsNothing);
    expect(find.text('侧栏'), findsOneWidget);
  });
}
