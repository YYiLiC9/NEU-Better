import 'package:flutter_test/flutter_test.dart';
import 'package:neu_better_pro/features/news/news_html.dart';

void main() {
  group('parseNewsHtml', () {
    test('解析段落、头条标题、图片与列表项', () {
      const html = '''
      <style>.x{color:red}</style>
      <h1>大标题</h1>
      <p>第一段<strong>加粗</strong>与<a href="https://x">链接</a></p>
      <img src="//neunews.example.com/a.jpg" alt="配图">
      <ul><li>条目一</li><li>条目二</li></ul>
      <script>alert(1)</script>
      ''';
      final blocks = parseNewsHtml(html);
      expect(
        blocks.map((b) => b.kind).toList(),
        <NewsBlockKind>[
          NewsBlockKind.heading,
          NewsBlockKind.paragraph,
          NewsBlockKind.image,
          NewsBlockKind.listItem,
          NewsBlockKind.listItem,
        ],
      );
      final heading = blocks.first;
      expect(heading.plainText, '大标题');
      expect(heading.level, 1);
      final paragraph = blocks[1];
      expect(paragraph.plainText, '第一段加粗与链接');
      expect(paragraph.spans.any((s) => s.bold), isTrue);
      expect(
        paragraph.spans.any((s) => s.href == 'https://x'),
        isTrue,
      );
      final image = blocks[2];
      expect(image.url, 'https://neunews.example.com/a.jpg');
      expect(image.caption, '配图');
    });

    test('解码实体并过滤空块', () {
      const html = '<p>&nbsp;</p><p>A&amp;B &lt;C&gt; &hellip;</p>';
      final blocks = parseNewsHtml(html);
      expect(blocks, hasLength(1));
      expect(blocks.single.plainText, 'A&B <C> …');
    });

    test('空输入返回空列表', () {
      expect(parseNewsHtml('   '), isEmpty);
    });

    test('剥离未识别的行内/结构标签（span / colgroup / col）', () {
      const html =
          '<p><span style="font-size:16px">中文</span>'
          '<span style="font-size:16px">正文</span></p>'
          '<colgroup><col data-offset-left="1" style="width: 26%;"></colgroup>'
          '<p>第二段</p>';
      final blocks = parseNewsHtml(html);
      expect(blocks, hasLength(2));
      expect(blocks[0].plainText, '中文正文');
      expect(blocks[1].plainText, '第二段');
      // 不应残留任何尖括号标签文本。
      for (final block in blocks) {
        expect(block.plainText.contains('<'), isFalse);
      }
    });
  });

  group('newsHtmlToText', () {
    test('按段落换行拼接纯文本', () {
      const html = '<p>甲</p><div>乙</div><li>丙</li>';
      expect(newsHtmlToText(html), '甲\n乙\n丙');
    });
  });
}
