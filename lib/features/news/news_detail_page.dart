import 'package:flutter/material.dart';

import '../../core/models/news_models.dart';
import '../../core/platform/external_url.dart';
import '../../core/network/news_client.dart';
import 'news_html.dart';
import 'news_theme.dart';

/// 原生新闻详情：衬线大标题 + 元信息 + HTML 转块渲染（段落/图片/标题/列表）。
///
/// 内容不使用 WebView；仅「查看原文」在必要时打开原文网页。
class NewsDetailPage extends StatefulWidget {
  const NewsDetailPage({
    super.key,
    required this.item,
    this.client,
    this.initialDetail,
  });

  final NewsItem item;
  final NewsClient? client;
  final NewsDetail? initialDetail;

  @override
  State<NewsDetailPage> createState() => _NewsDetailPageState();
}

class _NewsDetailPageState extends State<NewsDetailPage> {
  late final NewsClient _client;
  NewsDetail? _detail;
  List<NewsBlock> _blocks = const <NewsBlock>[];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _client = widget.client ?? NewsClient();
    _detail = widget.initialDetail;
    if (_detail != null) {
      _blocks = parseNewsHtml(_detail!.contentHtml);
      _loading = false;
    } else {
      _load();
    }
    _markRead();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final detail = await _client.detail(widget.item.id);
      if (!mounted) return;
      setState(() {
        _detail = detail;
        _blocks = parseNewsHtml(detail.contentHtml);
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _loading = false;
      });
    }
  }

  void _markRead() {
    // best-effort：减少服务端未读角标，失败忽略。
    _client.markRead(widget.item.id).catchError((_) {});
  }

  @override
  Widget build(BuildContext context) {
    final detail = _detail;
    return Scaffold(
      backgroundColor: NewsPalette.paper,
      appBar: AppBar(
        backgroundColor: NewsPalette.paper,
        foregroundColor: NewsPalette.ink,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        actions: [
          if (detail != null && detail.url.isNotEmpty)
            TextButton(
              key: const Key('news-open-original'),
              onPressed: () => _openOriginal(detail),
              child: Text(
                '查看原文',
                style: newsSans(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: NewsPalette.blue,
                ),
              ),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
        children: [
          if (detail != null) ..._buildMeta(detail),
          if (_loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 48),
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
            )
          else if (_error != null)
            _buildError()
          else
            NewsArticleBody(blocks: _blocks, baseItem: widget.item),
          if (detail != null && detail.url.isNotEmpty) ...[
            const SizedBox(height: 24),
            const Divider(color: NewsPalette.hairline, height: 1),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: () => _openOriginal(detail),
                child: Text(
                  '查看原文 ›',
                  style: newsSans(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: NewsPalette.blue,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  List<Widget> _buildMeta(NewsDetail detail) {
    final source = detail.cname.isEmpty ? widget.item.cname : detail.cname;
    final author = detail.author.isEmpty ? widget.item.author : detail.author;
    final meta = <String>[
      if (source.isNotEmpty) source,
      if (author.isNotEmpty) author,
      if (detail.publishTime.isNotEmpty) detail.publishTime,
    ].join(' · ');
    return <Widget>[
      if (source.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            source,
            style: newsSans(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: NewsPalette.red,
            ),
          ),
        ),
      Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Text(
          detail.title.isEmpty ? widget.item.title : detail.title,
          style: newsSerif(fontSize: 24, height: 1.35),
        ),
      ),
      if (meta.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: Text(
            meta,
            style: newsSans(fontSize: 11.5, color: NewsPalette.inkSoft),
          ),
        ),
      const Divider(color: NewsPalette.hairline, height: 1),
      const SizedBox(height: 16),
    ];
  }

  Widget _buildError() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40),
      child: Column(
        children: [
          const Icon(Icons.cloud_off_rounded, size: 32, color: NewsPalette.inkSoft),
          const SizedBox(height: 10),
          Text(
            '详情加载失败',
            style: newsSans(fontSize: 14, color: NewsPalette.ink),
          ),
          const SizedBox(height: 4),
          Text(
            _error ?? '',
            textAlign: TextAlign.center,
            style: newsSans(fontSize: 11.5, color: NewsPalette.inkSoft),
          ),
          const SizedBox(height: 12),
          TextButton(onPressed: _load, child: const Text('重试')),
        ],
      ),
    );
  }

  Future<void> _openOriginal(NewsDetail detail) async {
    await ExternalUrl.open(detail.url);
  }
}

/// 纯原生 HTML 块渲染：段落 / 标题 / 图片 / 列表项。
class NewsArticleBody extends StatelessWidget {
  const NewsArticleBody({
    super.key,
    required this.blocks,
    this.baseItem,
  });

  final List<NewsBlock> blocks;
  final NewsItem? baseItem;

  @override
  Widget build(BuildContext context) {
    if (blocks.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 32),
        child: Center(
          child: Text(
            '（暂无正文）',
            style: newsSans(fontSize: 13, color: NewsPalette.inkSoft),
          ),
        ),
      );
    }
    const maxWidth = 680.0;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: maxWidth),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final block in blocks) _buildBlock(context, block),
          ],
        ),
      ),
    );
  }

  Widget _buildBlock(BuildContext context, NewsBlock block) {
    switch (block.kind) {
      case NewsBlockKind.image:
        final url = block.url;
        if (url == null || url.isEmpty) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 380),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: Image.network(
                url,
                width: double.infinity,
                fit: BoxFit.contain,
                loadingBuilder: (context, child, progress) {
                  if (progress == null) return child;
                  return Container(
                    height: 160,
                    color: NewsPalette.hairline.withValues(alpha: 0.4),
                    child: const Center(
                      child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  );
                },
                errorBuilder: (context, error, stack) => Container(
                  height: 120,
                  color: NewsPalette.hairline.withValues(alpha: 0.3),
                  child: Center(
                    child: Text(
                      '图片加载失败',
                      style: newsSans(fontSize: 12, color: NewsPalette.inkSoft),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      case NewsBlockKind.heading:
        return Padding(
          padding: const EdgeInsets.only(top: 10, bottom: 10),
          child: Text.rich(
            TextSpan(
              children: _spans(block, fontWeight: FontWeight.w700),
            ),
            style: newsSerif(fontSize: block.level <= 2 ? 19 : 17),
          ),
        );
      case NewsBlockKind.listItem:
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '· ',
                style: newsSans(fontSize: 15.5, height: 1.9, color: NewsPalette.ink),
              ),
              Expanded(
                child: Text.rich(
                  TextSpan(children: _spans(block)),
                  style: newsSans(fontSize: 15.5, height: 1.9),
                ),
              ),
            ],
          ),
        );
      case NewsBlockKind.paragraph:
        return Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: Text.rich(
            TextSpan(children: _spans(block)),
            style: newsSans(fontSize: 15.5, height: 1.9),
          ),
        );
    }
  }

  List<InlineSpan> _spans(NewsBlock block, {FontWeight? fontWeight}) {
    return <InlineSpan>[
      for (final span in block.spans)
        TextSpan(
          text: span.text,
          style: TextStyle(
            fontWeight: span.bold ? FontWeight.w700 : fontWeight,
            fontStyle: span.italic ? FontStyle.italic : FontStyle.normal,
            color: span.href != null ? NewsPalette.blue : null,
            decoration: span.href != null ? TextDecoration.underline : null,
          ),
        ),
    ];
  }
}

