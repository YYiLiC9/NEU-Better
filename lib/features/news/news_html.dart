import 'dart:convert';

/// 一段带样式的行内文本。
class NewsSpan {
  const NewsSpan(
    this.text, {
    this.bold = false,
    this.italic = false,
    this.href,
  });

  final String text;
  final bool bold;
  final bool italic;
  final String? href;
}

enum NewsBlockKind { paragraph, heading, image, listItem }

/// 一个内容块：段落 / 标题 / 图片 / 列表项。
class NewsBlock {
  const NewsBlock({
    required this.kind,
    this.spans = const <NewsSpan>[],
    this.url,
    this.level = 0,
    this.caption,
  });

  final NewsBlockKind kind;
  final List<NewsSpan> spans;
  final String? url;
  final int level;
  final String? caption;

  String get plainText => spans.map((span) => span.text).join();

  bool get isEmpty => url == null && plainText.trim().isEmpty;
}

/// 无第三方依赖的极简 HTML → 块解析。
///
/// 支持：段落 / 标题(h1-h6) / 图片 / 列表项 / 表格行转文本 / br 换行，
/// 行内 bold(b/strong)、italic(i/em)、link(a href)，常见实体解码；
/// 过滤 script/style 与空块。不做完整 HTML 语义解析。
List<NewsBlock> parseNewsHtml(String html) {
  if (html.trim().isEmpty) return const <NewsBlock>[];

  var source = html;
  source = source.replaceAll(
    RegExp(r'<(script|style)[^>]*>[\s\S]*?</\1>', caseSensitive: false),
    '',
  );

  final tagPattern = RegExp(
    r'<(/?)(p|div|h([1-6])|li|tr|td|th|br|img|table|tbody|thead|ul|ol)\b([^>]*)>',
    caseSensitive: false,
  );

  final blocks = <NewsBlock>[];
  final buffer = StringBuffer();
  var blockKind = NewsBlockKind.paragraph;
  var headingLevel = 0;

  void flush() {
    final raw = buffer.toString();
    buffer.clear();
    final spans = _parseInline(raw);
    final text = spans.map((s) => s.text).join().trim();
    if (text.isEmpty) return;
    blocks.add(
      NewsBlock(
        kind: blockKind,
        spans: spans,
        level: headingLevel,
      ),
    );
  }

  var cursor = 0;
  for (final match in tagPattern.allMatches(source)) {
    // 标签之前的文本。
    if (match.start > cursor) {
      buffer.write(source.substring(cursor, match.start));
    }
    cursor = match.end;
    final closing = match.group(1) == '/';
    final name = (match.group(2) ?? '').toLowerCase();
    final attrs = match.group(4) ?? '';

    switch (name) {
      case 'br':
        buffer.write('\n');
        break;
      case 'img':
        flush();
        final src = _attr(attrs, 'src');
        if (src != null && src.isNotEmpty) {
          blocks.add(
            NewsBlock(
              kind: NewsBlockKind.image,
              url: _resolveUrl(src),
              caption: _attr(attrs, 'alt'),
            ),
          );
        }
        break;
      case 'table':
      case 'tbody':
      case 'thead':
      case 'ul':
      case 'ol':
        flush();
        blockKind = NewsBlockKind.paragraph;
        break;
      case 'tr':
        if (closing) {
          flush();
        } else {
          flush();
          blockKind = NewsBlockKind.paragraph;
        }
        break;
      case 'td':
      case 'th':
        buffer.write('  ');
        break;
      case 'li':
        if (closing) {
          flush();
        } else {
          flush();
          blockKind = NewsBlockKind.listItem;
        }
        break;
      default:
        if (RegExp(r'^h[1-6]$').hasMatch(name)) {
          if (closing) {
            flush();
            blockKind = NewsBlockKind.paragraph;
            headingLevel = 0;
          } else {
            flush();
            blockKind = NewsBlockKind.heading;
            headingLevel = int.parse(name.substring(1));
          }
        } else {
          // p / div 等块级标签：开始/结束都作为分段边界。
          flush();
        }
    }
  }
  if (cursor < source.length) buffer.write(source.substring(cursor));
  flush();

  return blocks
      .where((block) => !block.isEmpty)
      .toList(growable: false);
}

List<NewsSpan> _parseInline(String raw) {
  if (raw.isEmpty) return const <NewsSpan>[];

  final spans = <NewsSpan>[];
  final tokenPattern = RegExp(
    r'<(/?)(b|strong|i|em|a)\b([^>]*)>',
    caseSensitive: false,
  );
  var bold = 0;
  var italic = 0;
  String? href;
  var cursor = 0;

  void addText(String text) {
    if (text.isEmpty) return;
    // 兜底：清理未单独识别的行内/结构标签（如 <span style>、<font>、<colgroup>、
    // <col>、<o:p> 等），只保留其文本内容，避免原始 HTML 泄漏到正文。
    final withoutTags = text.replaceAll(RegExp(r'<[^>]*>'), '');
    if (withoutTags.isEmpty) return;
    final decoded = _decodeEntities(withoutTags);
    if (decoded.isEmpty) return;
    final last = spans.isEmpty ? null : spans.last;
    // 合并相同样式的相邻片段，减少 TextSpan 数量。
    if (last != null &&
        last.bold == (bold > 0) &&
        last.italic == (italic > 0) &&
        last.href == href) {
      spans[spans.length - 1] = NewsSpan(
        last.text + decoded,
        bold: last.bold,
        italic: last.italic,
        href: last.href,
      );
      return;
    }
    spans.add(
      NewsSpan(decoded, bold: bold > 0, italic: italic > 0, href: href),
    );
  }

  for (final match in tokenPattern.allMatches(raw)) {
    if (match.start > cursor) {
      addText(raw.substring(cursor, match.start));
    }
    cursor = match.end;
    final closing = match.group(1) == '/';
    final name = (match.group(2) ?? '').toLowerCase();
    final attrs = match.group(3) ?? '';
    switch (name) {
      case 'b':
      case 'strong':
        bold += closing ? -1 : 1;
        if (bold < 0) bold = 0;
        break;
      case 'i':
      case 'em':
        italic += closing ? -1 : 1;
        if (italic < 0) italic = 0;
        break;
      case 'a':
        if (closing) {
          href = null;
        } else {
          href = _attr(attrs, 'href');
        }
        break;
    }
  }
  if (cursor < raw.length) addText(raw.substring(cursor));

  // 去掉纯空白片段。
  return spans
      .where((span) => span.text.trim().isNotEmpty || span.text == '\n')
      .toList(growable: false);
}

String? _attr(String attrs, String name) {
  final match = RegExp(
    '$name\\s*=\\s*("([^"]*)"|\'([^\']*)\'|([^\\s>]+))',
    caseSensitive: false,
  ).firstMatch(attrs);
  if (match == null) return null;
  return match.group(2) ?? match.group(3) ?? match.group(4);
}

String _resolveUrl(String url) {
  final trimmed = url.trim();
  if (trimmed.startsWith('//')) return 'https:$trimmed';
  if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
    return trimmed;
  }
  if (trimmed.startsWith('/')) {
    return 'https://personal.neu.edu.cn$trimmed';
  }
  return trimmed;
}

/// 常见 HTML 实体与数字实体解码。
String _decodeEntities(String input) {
  if (!input.contains('&')) return input;
  var text = input;
  final named = <String, String>{
    '&nbsp;': ' ',
    '&amp;': '&',
    '&lt;': '<',
    '&gt;': '>',
    '&quot;': '"',
    '&#39;': "'",
    '&apos;': "'",
    '&ldquo;': '“',
    '&rdquo;': '”',
    '&lsquo;': '‘',
    '&rsquo;': '’',
    '&mdash;': '—',
    '&ndash;': '–',
    '&hellip;': '…',
  };
  named.forEach((key, value) => text = text.replaceAll(key, value));
  text = text.replaceAllMapped(RegExp(r'&#(\d+);'), (match) {
    final code = int.tryParse(match.group(1) ?? '');
    return code == null ? match.group(0) ?? '' : String.fromCharCode(code);
  });
  text = text.replaceAllMapped(RegExp(r'&#x([0-9a-fA-F]+);'), (match) {
    final code = int.tryParse(match.group(1) ?? '', radix: 16);
    return code == null ? match.group(0) ?? '' : String.fromCharCode(code);
  });
  return text;
}

/// 供测试/调试：把 HTML 直接转纯文本（段落以换行分隔）。
String newsHtmlToText(String html) => parseNewsHtml(html)
    .map((block) => block.plainText)
    .where((text) => text.trim().isNotEmpty)
    .join('\n');

/// 供调试输出（不会被 UI 使用）。
String debugBlocksJson(List<NewsBlock> blocks) => jsonEncode(<Object?>[
  for (final block in blocks)
    <String, dynamic>{
      'kind': block.kind.name,
      'level': block.level,
      'url': block.url,
      'text': block.plainText,
    },
]);
