import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:neu_better_pro/features/home/home_card_layout.dart';
import 'package:neu_better_pro/features/home/home_layout_store.dart';

void main() {
  test('spanOf maps sizes to rows/cols', () {
    expect(spanOf(HomeCardSize.s1x1), (1, 1));
    expect(spanOf(HomeCardSize.s2x2), (2, 2));
    expect(spanOf(HomeCardSize.s2x4), (2, 4));
  });

  test('defaultHomeCards order and sizes', () {
    final cards = defaultHomeCards();
    expect(cards.map((c) => c.id).toList(), ['dorm', 'notify', 'mail']);
    expect(cards[0].size, HomeCardSize.s2x4);
    expect(cards[1].size, HomeCardSize.s1x1);
    expect(cards[2].size, HomeCardSize.s1x1);
  });

  test('packHomeCards places dorm full width then small cards on next row', () {
    final pack = packHomeCards(defaultHomeCards(), 400, gap: 12, columns: 4);
    // unit = (400 - 12*3) / 4 = 91
    final dorm = pack.cards.firstWhere((c) => c.id == 'dorm');
    expect(dorm.rows, 2);
    expect(dorm.cols, 4);
    expect(dorm.left, 0);
    expect(dorm.top, 0);
    expect(dorm.width, closeTo(400, 0.001));

    final notify = pack.cards.firstWhere((c) => c.id == 'notify');
    expect(notify.rows, 1);
    expect(notify.cols, 1);
    expect(notify.left, 0);
    // 应排在 dorm 下方的第 3 行（index 2）。
    expect(notify.top, closeTo(2 * 91 + 2 * 12, 0.001));

    final mail = pack.cards.firstWhere((c) => c.id == 'mail');
    expect(mail.left, closeTo(91 + 12, 0.001));

    expect(pack.totalHeight, closeTo(3 * 91 + 2 * 12, 0.001));
  });

  test('packHomeCards compacts a 2x2 next to dorm overflow', () {
    final cards = <HomeCardLayout>[
      const HomeCardLayout(id: 'dorm', size: HomeCardSize.s2x2),
      const HomeCardLayout(id: 'notify', size: HomeCardSize.s2x2),
      const HomeCardLayout(id: 'mail', size: HomeCardSize.s1x1),
    ];
    final pack = packHomeCards(cards, 400);
    final dorm = pack.cards[0];
    final notify = pack.cards[1];
    // 两个 2×2 位于同一行（top 相同），notify 在 dorm 右侧。
    expect(notify.top, dorm.top);
    expect(notify.left, greaterThan(dorm.left));
  });

  test('HomeLayoutStore round-trips and falls back on corrupt file', () async {
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

    await file.writeAsString('not json at all');
    final fallback = await store.read();
    expect(fallback.map((c) => c.id).toList(), ['dorm', 'notify', 'mail']);

    await dir.delete(recursive: true);
  });

  test('HomeLayoutStore fills missing known ids from partial file', () async {
    final dir = await Directory.systemTemp.createTemp('home_layout_test2_');
    final file = File('${dir.path}/home_layout.json');
    await file.writeAsString('{"order":["notify"],"sizes":{"notify":"s2x2"}}');
    final store = HomeLayoutStore(candidates: [file]);

    final read = await store.read();
    expect(read.map((c) => c.id).toList(), ['notify', 'dorm', 'mail']);
    expect(read.first.size, HomeCardSize.s2x2);

    await dir.delete(recursive: true);
  });

  test('HomeLayoutStore ignores unknown ids', () async {
    final dir = await Directory.systemTemp.createTemp('home_layout_test3_');
    final file = File('${dir.path}/home_layout.json');
    await file.writeAsString(
      '{"order":["ghost","dorm"],"sizes":{"ghost":"s2x2"}}',
    );
    final store = HomeLayoutStore(candidates: [file]);

    final read = await store.read();
    expect(read.map((c) => c.id).toList(), ['dorm', 'notify', 'mail']);

    await dir.delete(recursive: true);
  });
}
