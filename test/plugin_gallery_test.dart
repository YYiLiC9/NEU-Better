import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neu_better_pro/core/plugins/plugin_models.dart';
import 'package:neu_better_pro/core/plugins/plugin_placement_store.dart';
import 'package:neu_better_pro/features/home/home_card_catalog.dart';
import 'package:neu_better_pro/features/home/home_card_layout.dart';
import 'package:neu_better_pro/features/home/home_page.dart' show HomeCardGallery;

PluginManifest _manifest(String id, String version, {int renderer = 1}) {
  return PluginManifest.fromJson(jsonDecode('''
  {
    "id": "$id", "name": "$id", "description": "desc $id", "version": "$version",
    "rendererVersion": $renderer, "startPage": "home",
    "pages": {"home": {"title": "$id", "body": []}}
  }
  '''))!;
}

Widget _wrap(Widget child) =>
    MaterialApp(home: Scaffold(body: child));

void main() {
  testWidgets('gallery shows four plugin states and disables high renderer', (
    tester,
  ) async {
    final plugins = <PluginManifest>[
      _manifest('newplug', '1.0.0'),
      _manifest('installedplug', '1.0.0'),
      _manifest('addedplug', '1.0.0'),
      _manifest('highplug', '1.0.0', renderer: 99),
      _manifest('updateplug', '2.0.0'),
    ];
    String? downloaded;
    await tester.pumpWidget(
      _wrap(
        HomeCardGallery(
          cards: const <HomeCardLayout>[
            HomeCardLayout(id: 'addedplug', size: HomeCardSize.s1x1),
          ],
          builtins: const <HomeCardInfo>[],
          plugins: plugins,
          installedVersions: const <String, String>{
            'installedplug': '1.0.0',
            'addedplug': '1.0.0',
            'updateplug': '1.0.0',
          },
          onBack: () {},
          onAdd: (_) {},
          onDownload: (manifest) => downloaded = manifest.id,
          onDeletePlugin: (_) {},
          onUpdate: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    // newplug 未下载 → 下载
    expect(find.text('下载'), findsOneWidget);
    // installedplug 已下载未添加 + addedplug 已添加
    expect(find.text('添加'), findsOneWidget);
    expect(find.text('已添加'), findsOneWidget);
    // updateplug 有更新
    expect(find.text('更新'), findsOneWidget);
    // highplug 渲染器过高
    expect(find.text('需更新App'), findsOneWidget);

    await tester.tap(find.text('下载'));
    expect(downloaded, 'newplug');
  });

  testWidgets('gallery shows progress and retry states', (tester) async {
    final plugins = <PluginManifest>[
      _manifest('progressplug', '1.0.0'),
      _manifest('failedplug', '1.0.0'),
    ];
    await tester.pumpWidget(
      _wrap(
        HomeCardGallery(
          cards: const <HomeCardLayout>[],
          builtins: const <HomeCardInfo>[],
          plugins: plugins,
          downloading: const <String, double>{'progressplug': 0.42},
          failed: const <String>{'failedplug'},
          onBack: () {},
          onAdd: (_) {},
          onDownload: (_) {},
        ),
      ),
    );
    await tester.pump();
    expect(find.text('42%'), findsOneWidget);
    expect(find.text('重试'), findsOneWidget);
  });

  testWidgets('builtin delete is disabled and does not remove', (tester) async {
    await tester.pumpWidget(
      _wrap(
        HomeCardGallery(
          cards: const <HomeCardLayout>[
            HomeCardLayout(id: 'dorm', size: HomeCardSize.s1x1),
          ],
          onBack: () {},
          onAdd: (_) {},
          onDeleteBuiltin: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('已添加'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('delete-builtin-dorm')));
    await tester.pumpAndSettle();
    // 常驻内置插件删除按钮置灰，不弹确认框。
    expect(find.text('从首页移除'), findsNothing);
  });

  testWidgets('placement options replace add buttons when enabled', (
    tester,
  ) async {
    final plugins = <PluginManifest>[_manifest('remote', '1.0.0')];
    var appearances = <String, PluginAppearance>{};
    await tester.pumpWidget(
      _wrap(
        StatefulBuilder(
          builder: (context, setState) => HomeCardGallery(
            cards: const <HomeCardLayout>[],
            builtins: <HomeCardInfo>[homeCardInfo('dorm')!],
            plugins: plugins,
            installedVersions: const <String, String>{'remote': '1.0.0'},
            appearances: appearances,
            allowPlacementOptions: true,
            onBack: () {},
            onAdd: (_) {},
            onDeletePlugin: (_) {},
            onSetAppearance: (id, appearance) {
              setState(() => appearances = {...appearances, id: appearance});
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    // 放置选项默认折叠，先展开内置与远程两项。
    await tester.tap(find.byKey(const ValueKey('placement-dropdown-dorm')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('placement-dropdown-remote')));
    await tester.pumpAndSettle();

    // 内置与远程已下载都展示三选项，旧的「添加/已添加」不再出现。
    expect(find.text('添加'), findsNothing);
    expect(find.text('已添加'), findsNothing);
    expect(find.text('不添加'), findsNWidgets(2));
    expect(find.text('添加到首页'), findsNWidgets(2));
    expect(find.text('添加到侧栏'), findsNWidgets(2));

    await tester.tap(find.byKey(const ValueKey('appearance-sidebar-remote')));
    await tester.pumpAndSettle();
    expect(appearances['remote']?.sidebar, isTrue);
    expect(appearances['remote']?.home, isFalse);
  });
}
