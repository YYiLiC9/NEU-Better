import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neu_better_pro/features/home/home_card_layout.dart';
import 'package:neu_better_pro/features/home/home_layout_store.dart';
import 'package:neu_better_pro/features/home/home_page.dart' show HomeCardGallery;

void main() {
  test('spanOf maps sizes to rows/cols', () {
    expect(spanOf(HomeCardSize.s1x1), (1, 1));
    expect(spanOf(HomeCardSize.s2x2), (2, 2));
    expect(spanOf(HomeCardSize.s2x4), (2, 4));
  });

  test('nextSizeOf cycles 1x1 -> 2x2 -> 2x4 -> 1x1', () {
    expect(nextSizeOf(HomeCardSize.s1x1), HomeCardSize.s2x2);
    expect(nextSizeOf(HomeCardSize.s2x2), HomeCardSize.s2x4);
    expect(nextSizeOf(HomeCardSize.s2x4), HomeCardSize.s1x1);
  });

  test('defaultHomeCards order and all 1x1', () {
    final cards = defaultHomeCards();
    expect(cards.map((c) => c.id).toList(), ['dorm', 'notify', 'mail']);
    expect(cards.every((c) => c.size == HomeCardSize.s1x1), isTrue);
  });

  test('packHomeCards fixed unit computes dynamic columns (wide)', () {
    final pack = packHomeCards(defaultHomeCards(), 809, unit: 88);
    // ((809 + 12) / (88 + 12)).floor = 8 列
    expect(pack.columns, 8);
    expect(pack.unit, 88);
    expect(pack.usedWidth, closeTo(8 * 88 + 7 * 12, 0.001));
    final dorm = pack.cards.first;
    expect(dorm.left, 0);
    expect(dorm.top, 0);
    expect(dorm.width, 88);
    expect(pack.totalHeight, 88);
  });

  test('packHomeCards fixed unit clamps to >= 4 columns (narrow)', () {
    final pack = packHomeCards(defaultHomeCards(), 484, unit: 88);
    expect(pack.columns, 4);
    expect(pack.usedWidth, closeTo(4 * 88 + 3 * 12, 0.001));
  });

  test('packHomeCards mobile columns scale equally', () {
    final pack = packHomeCards(defaultHomeCards(), 484, columns: 4);
    expect(pack.columns, 4);
    expect(pack.unit, closeTo((484 - 12 * 3) / 4, 0.001));
    expect(pack.usedWidth, closeTo(484, 0.001));
  });

  test('packHomeCards empty list has zero height', () {
    final pack = packHomeCards(const [], 400, unit: 88);
    expect(pack.cards, isEmpty);
    expect(pack.totalHeight, 0);
  });

  test('HomeLayoutStore round-trips and preserves explicit order', () async {
    final dir = await Directory.systemTemp.createTemp('home_layout_test_');
    final file = File('${dir.path}/home_layout.json');
    final store = HomeLayoutStore(candidates: [file]);

    final cards = <HomeCardLayout>[
      const HomeCardLayout(id: 'dorm', size: HomeCardSize.s2x2),
      const HomeCardLayout(id: 'notify', size: HomeCardSize.s1x1),
      const HomeCardLayout(id: 'mail', size: HomeCardSize.s2x4),
    ];
    await store.save(cards);
    final read = await store.read();
    expect(
      read.map((c) => '${c.id}:${c.size.name}').toList(),
      ['dorm:s2x2', 'notify:s1x1', 'mail:s2x4'],
    );
    await dir.delete(recursive: true);
  });

  test('HomeLayoutStore strictly keeps file ids (no auto re-add)', () async {
    final dir = await Directory.systemTemp.createTemp('home_layout_test2_');
    final file = File('${dir.path}/home_layout.json');
    await file.writeAsString(
      '{"order":["notify","mail"],"sizes":{"notify":"s2x2"}}',
    );
    final store = HomeLayoutStore(candidates: [file]);
    final read = await store.read();
    expect(read.map((c) => c.id).toList(), ['notify', 'mail']);
    expect(read.first.size, HomeCardSize.s2x2);
    expect(read.last.size, HomeCardSize.s1x1);
    await dir.delete(recursive: true);
  });

  test('HomeLayoutStore treats empty order as legal empty layout', () async {
    final dir = await Directory.systemTemp.createTemp('home_layout_test3_');
    final file = File('${dir.path}/home_layout.json');
    await file.writeAsString('{"order":[],"sizes":{}}');
    final store = HomeLayoutStore(candidates: [file]);
    final read = await store.read();
    expect(read, isEmpty);
    await dir.delete(recursive: true);
  });

  test('HomeLayoutStore ignores unknown ids and does not refill', () async {
    final dir = await Directory.systemTemp.createTemp('home_layout_test4_');
    final file = File('${dir.path}/home_layout.json');
    await file.writeAsString(
      '{"order":["ghost","dorm"],"sizes":{"ghost":"s2x2"}}',
    );
    final store = HomeLayoutStore(candidates: [file]);
    final read = await store.read();
    expect(read.map((c) => c.id).toList(), ['dorm']);
    expect(read.first.size, HomeCardSize.s1x1);
    await dir.delete(recursive: true);
  });

  test('HomeLayoutStore falls back to default on corrupt file', () async {
    final dir = await Directory.systemTemp.createTemp('home_layout_test5_');
    final file = File('${dir.path}/home_layout.json');
    await file.writeAsString('not json at all');
    final store = HomeLayoutStore(candidates: [file]);
    final read = await store.read();
    expect(read.map((c) => c.id).toList(), ['dorm', 'notify', 'mail']);
    expect(read.every((c) => c.size == HomeCardSize.s1x1), isTrue);
    await dir.delete(recursive: true);
  });

  test('HomeLayoutStore filters ids to allowedIds (installed plugins)', () async {
    final dir = await Directory.systemTemp.createTemp('home_layout_test6_');
    final file = File('${dir.path}/home_layout.json');
    await file.writeAsString(
      '{"order":["dorm","library","mail"],"sizes":{"library":"s2x2"}}',
    );
    final store = HomeLayoutStore(candidates: [file]);
    final allowed = <String>{'dorm', 'mail', 'library'};
    final read = await store.read(allowedIds: allowed);
    expect(read.map((c) => c.id).toList(), ['dorm', 'library', 'mail']);
    expect(read[1].size, HomeCardSize.s2x2);

    final narrow = await store.read(allowedIds: <String>{'dorm', 'mail'});
    expect(narrow.map((c) => c.id).toList(), ['dorm', 'mail']);
    await dir.delete(recursive: true);
  });

  testWidgets('card gallery disables added cards and adds missing', (
    tester,
  ) async {
    String? added;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HomeCardGallery(
            cards: const <HomeCardLayout>[
              HomeCardLayout(id: 'dorm', size: HomeCardSize.s1x1),
            ],
            onBack: () {},
            onAdd: (id) => added = id,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('余额中心'), findsWidgets);
    expect(find.text('已添加'), findsOneWidget);
    expect(find.text('添加'), findsNWidgets(3));

    await tester.tap(find.text('添加').first);
    expect(added, 'notify');
  });
}
