import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neu_better_pro/core/models/news_models.dart';
import 'package:neu_better_pro/features/home/home_card_layout.dart';
import 'package:neu_better_pro/features/home/widgets/news_card.dart';
import 'package:neu_better_pro/features/news/news_detail_page.dart';
import 'package:neu_better_pro/features/news/news_sections_page.dart';

void main() {
  testWidgets('板块选择：校内通知必选且不可关闭，选板块后返回', (tester) async {
    const sections = <NewsSection>[
      NewsSection(
        id: NewsPrefs.internalNoticeId,
        name: '校内通知',
        group: '新闻资讯',
      ),
      NewsSection(id: 'c1', name: '东大要闻', group: '新闻资讯'),
      NewsSection(id: 'c2', name: '媒体东大', group: '新闻资讯'),
      NewsSection(id: 'c3', name: '通知公告', group: '通知公告'),
    ];
    List<String>? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () async {
                  result = await Navigator.of(context).push<List<String>>(
                    MaterialPageRoute<List<String>>(
                      builder: (_) => const NewsSectionsPage(
                        sections: sections,
                        initialSelected: <String>[NewsPrefs.internalNoticeId],
                      ),
                    ),
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // 校内通知与其它板块同列表，默认选中且不可取消。
    expect(find.text('校内通知'), findsOneWidget);
    final lockedTile = tester.widget<CheckboxListTile>(
      find.byKey(
        ValueKey('news-section-${NewsPrefs.internalNoticeId}'),
      ),
    );
    expect(lockedTile.value, isTrue);
    expect(lockedTile.onChanged, isNull);

    // 选中一个板块。
    await tester.tap(find.byKey(const ValueKey('news-section-c1')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('news-sections-done')));
    await tester.pumpAndSettle();

    expect(result, isNotNull);
    expect(result, contains(NewsPrefs.internalNoticeId));
    expect(result, contains('c1'));
    expect(result, isNot(contains('c2')));
  });

  testWidgets('新闻详情渲染标题与正文段落', (tester) async {
    const item = NewsItem(
      id: 'n1',
      title: '列表标题',
      desc: '',
      picurls: <String>[],
      publishTime: '2026-11-16',
      cname: '校内通知',
      author: '办公室',
      reader: 3,
      hasRead: false,
      url: '',
      cid: 'c1',
    );
    const detail = NewsDetail(
      id: 'n1',
      title: '详情大标题',
      contentHtml: '<p>正文第一段</p><p>第二段</p>',
      publishTime: '2026-11-16 10:10',
      author: '办公室',
      cname: '校内通知',
      picurls: <String>[],
      url: '',
      attachments: <String>[],
    );
    await tester.pumpWidget(
      const MaterialApp(
        home: NewsDetailPage(item: item, initialDetail: detail),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('详情大标题'), findsOneWidget);
    expect(find.text('正文第一段'), findsOneWidget);
    expect(find.text('第二段'), findsOneWidget);
  });

  testWidgets('首页新闻卡：2×2 显示未读与最近标题', (tester) async {
    const items = <NewsItem>[
      NewsItem(
        id: 'n1',
        title: '新闻标题一',
        desc: '摘要一',
        picurls: <String>[],
        publishTime: '2026-11-16',
        cname: '东大要闻',
        author: '',
        reader: 0,
        hasRead: false,
        url: '',
        cid: 'c1',
      ),
      NewsItem(
        id: 'n2',
        title: '新闻标题二',
        desc: '摘要二',
        picurls: <String>[],
        publishTime: '2026-11-15',
        cname: '东大要闻',
        author: '',
        reader: 0,
        hasRead: false,
        url: '',
        cid: 'c1',
      ),
    ];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 150,
              height: 150,
              child: NewsCard(
                size: HomeCardSize.s2x2,
                unread: 8,
                latest: items,
                onOpen: () {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('未读 8 条'), findsOneWidget);
    expect(find.text('新闻标题一'), findsOneWidget);
    expect(find.text('新闻标题二'), findsOneWidget);
  });
}
