import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neu_better_pro/core/plugins/plugin_models.dart';
import 'package:neu_better_pro/core/plugins/plugin_renderer.dart';

const String _manifestJson = '''
{
  "id": "library",
  "name": "图书馆",
  "description": "馆藏检索与借阅",
  "version": "1.0.0",
  "minAppVersion": "0.3.1",
  "rendererVersion": 1,
  "icon": {"type": "material", "value": "menu_book"},
  "startPage": "home",
  "pages": {
    "home": {"title": "图书馆", "body": [
      {"type": "text", "style": "title", "value": "热门馆藏"},
      {"type": "list",
       "data": {"type": "static", "items": [
         {"id": "b001", "title": "三体", "author": "刘慈欣"},
         {"id": "b002", "title": "人类简史", "author": "尤瓦尔"}
       ]},
       "item": {"title": "{{title}}", "subtitle": "{{author}}",
                "onTap": {"type": "openPage", "page": "detail", "params": {"id": "{{id}}"}}}}
    ]},
    "detail": {"title": "详情", "body": [{"type": "text", "value": "编号 {{id}}"}]},
    "form": {"title": "表单", "body": [
      {"type": "form", "fields": [
        {"key": "name", "label": "姓名", "type": "text"},
        {"key": "remark", "label": "备注", "type": "multiline"}
      ], "action": {"type": "refresh"}}
    ]}
  }
}
''';

void main() {
  PluginManifest manifest() =>
      PluginManifest.fromJson(jsonDecode(_manifestJson))!;

  testWidgets('renders text and static list, openPage carries params', (
    tester,
  ) async {
    String? openedPage;
    Map<String, Object?>? openedParams;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PluginRuntimeScope(
            openPage: (page, params) {
              openedPage = page;
              openedParams = params;
            },
            openUrl: (_) {},
            refresh: () {},
            child: Builder(
              builder: (context) =>
                  buildPluginPage(context, manifest(), 'home', const {}, null),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('热门馆藏'), findsOneWidget);
    expect(find.text('三体'), findsOneWidget);
    expect(find.text('刘慈欣'), findsOneWidget);

    await tester.tap(find.text('三体'));
    await tester.pumpAndSettle();
    expect(openedPage, 'detail');
    expect(openedParams?['id'], 'b001');
  });

  testWidgets('renders detail page with interpolated param', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => buildPluginPage(
              context,
              manifest(),
              'detail',
              <String, Object?>{'id': 'b002'},
              null,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('编号 b002'), findsOneWidget);
  });

  testWidgets('renders form fields and submit button', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) =>
                buildPluginPage(context, manifest(), 'form', const {}, null),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('姓名'), findsOneWidget);
    expect(find.text('备注'), findsOneWidget);
    expect(find.text('提交'), findsOneWidget);
  });

  test('template interpolation does not execute expressions', () {
    // 表达式不是合法字段名，原样保留（不执行）。
    expect(interpolateTemplate(r'{{1+1}}', const {}), r'{{1+1}}');
    expect(interpolateTemplate('a{{x}}b', {'x': 'Z'}), 'aZb');
  });
}
