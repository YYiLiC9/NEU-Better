import 'package:flutter/material.dart';

import '../../core/models/news_models.dart';
import '../../core/network/news_client.dart';
import 'news_detail_page.dart';
import 'news_sections_page.dart';
import 'news_store.dart';
import 'news_theme.dart';

/// 新闻主页面：「东大校刊 · 号外」版式。
///
/// 报头 + 横向板块标签（全部 / 已选板块）+ 新闻列表。首条为头条（大图 + 衬线标题），
/// 其余为细线分隔行，右侧小缩略图。支持下拉刷新与上拉分页。
class NewsPage extends StatefulWidget {
  const NewsPage({super.key, this.client, this.store});

  final NewsClient? client;
  final NewsStore? store;

  @override
  State<NewsPage> createState() => _NewsPageState();
}

class _NewsPageState extends State<NewsPage> {
  static const String _allTab = '__all__';

  late final NewsClient _client;
  late final NewsStore _store;
  final ScrollController _scroll = ScrollController();

  List<NewsSection> _sections = const <NewsSection>[];
  List<String> _selected = const <String>[NewsPrefs.internalNoticeId];
  String _activeTab = _allTab;

  /// 本地已读集合：服务端未必回写，刷新后仍按本地记录显示已读。
  Set<String> _readIds = <String>{};

  final Map<String, List<NewsItem>> _itemsByCid = <String, List<NewsItem>>{};
  final Map<String, int> _pageByCid = <String, int>{};
  final Set<String> _exhaustedCid = <String>{};

  bool _bootstrapping = true;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _client = widget.client ?? NewsClient();
    _store = widget.store ?? const NewsStore();
    _scroll.addListener(_onScroll);
    _bootstrap();
  }

  @override
  void dispose() {
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    setState(() {
      _bootstrapping = true;
      _error = null;
    });
    final prefs = await _store.readPrefs();
    final readIds = await _store.readReadIds();
    List<NewsSection> sections = const <NewsSection>[];
    String? sectionsError;
    final cache = await _store.readSectionsCache();
    if (cache != null && cache.isFresh) {
      sections = cache.sections;
    } else {
      try {
        sections = await _client.sections();
        await _store.saveSectionsCache(sections);
      } catch (error) {
        sectionsError = error.toString();
        if (cache != null) sections = cache.sections;
      }
    }
    final validIds = sections.map((s) => s.id).toList(growable: false);
    final selected = prefs.normalized(validIds);
    if (!_sameList(selected, prefs.selectedCids)) {
      await _store.savePrefs(NewsPrefs(selectedCids: selected));
    }
    if (!mounted) return;
    setState(() {
      _sections = sections;
      _selected = selected;
      _readIds = readIds;
      _bootstrapping = false;
      if (sections.isEmpty && sectionsError != null) {
        _error = sectionsError;
      }
    });
    await _loadActive(reset: true);
  }

  bool _isRead(NewsItem item) => item.hasRead || _readIds.contains(item.id);

  bool _sameList(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  List<String> get _activeCids =>
      _activeTab == _allTab ? _selected : <String>[_activeTab];

  Future<void> _loadActive({required bool reset}) async {
    final cids = _activeCids;
    if (reset) {
      _itemsByCid.clear();
      _pageByCid.clear();
      _exhaustedCid.clear();
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      for (final cid in cids) {
        if (_exhaustedCid.contains(cid)) continue;
        final page = (_pageByCid[cid] ?? 0) + 1;
        final result = await _client.list(cid, page: page);
        final existing = _itemsByCid.putIfAbsent(cid, () => <NewsItem>[]);
        final known = existing.map((item) => item.id).toSet();
        for (final item in result.items) {
          if (known.add(item.id)) existing.add(item);
        }
        _pageByCid[cid] = page;
        if (result.items.isEmpty || existing.length >= result.total) {
          _exhaustedCid.add(cid);
        }
      }
      if (!mounted) return;
      setState(() {
        _loading = false;
        _sort();
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.toString();
      });
    }
  }

  void _sort() {
    for (final list in _itemsByCid.values) {
      list.sort((a, b) {
        final da = DateTime.tryParse(a.publishTime.replaceFirst(' ', 'T'));
        final db = DateTime.tryParse(b.publishTime.replaceFirst(' ', 'T'));
        if (da != null && db != null) return db.compareTo(da);
        return b.publishTime.compareTo(a.publishTime);
      });
    }
  }

  List<NewsItem> get _visibleItems {
    if (_activeTab == _allTab) {
      final merged = <NewsItem>[];
      final seen = <String>{};
      for (final cid in _selected) {
        for (final item in _itemsByCid[cid] ?? const <NewsItem>[]) {
          if (seen.add(item.id)) merged.add(item);
        }
      }
      merged.sort((a, b) {
        final da = DateTime.tryParse(a.publishTime.replaceFirst(' ', 'T'));
        final db = DateTime.tryParse(b.publishTime.replaceFirst(' ', 'T'));
        if (da != null && db != null) return db.compareTo(da);
        return b.publishTime.compareTo(a.publishTime);
      });
      return merged;
    }
    return _itemsByCid[_activeTab] ?? const <NewsItem>[];
  }

  void _onScroll() {
    if (!_scroll.hasClients || _loading) return;
    if (_scroll.position.pixels >= _scroll.position.maxScrollExtent - 240) {
      final anyMore = _activeCids.any((cid) => !_exhaustedCid.contains(cid));
      if (anyMore) _loadActive(reset: false);
    }
  }

  Future<void> _clearUnread() async {
    final ids = <String>{..._readIds};
    for (final list in _itemsByCid.values) {
      for (final item in list) {
        ids.add(item.id);
      }
    }
    setState(() => _readIds = ids);
    await _store.saveReadIds(ids);
    if (!mounted) return;
    ScaffoldMessenger.maybeOf(context)
        ?.showSnackBar(const SnackBar(content: Text('已清除未读')));
  }

  Future<void> _openSections() async {
    final result = await Navigator.of(context).push<List<String>>(
      MaterialPageRoute<List<String>>(
        builder: (_) => NewsSectionsPage(
          sections: _sections,
          initialSelected: _selected,
        ),
      ),
    );
    if (result == null) return;
    final normalized = NewsPrefs(selectedCids: result).normalized(
      _sections.map((s) => s.id),
    );
    await _store.savePrefs(NewsPrefs(selectedCids: normalized));
    setState(() {
      _selected = normalized;
      if (_activeTab != _allTab && !normalized.contains(_activeTab)) {
        _activeTab = _allTab;
      }
    });
    await _loadActive(reset: true);
  }

  String _sectionName(String id) {
    if (id == NewsPrefs.internalNoticeId) return '校内通知';
    for (final section in _sections) {
      if (section.id == id) return section.name;
    }
    return '板块';
  }

  Future<void> _openItem(NewsItem item) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => NewsDetailPage(item: item, client: _client),
      ),
    );
    if (!mounted) return;
    if (!_isRead(item)) {
      _readIds.add(item.id);
      await _store.saveReadIds(_readIds);
      if (!mounted) return;
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: NewsPalette.paper,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildMasthead(),
            _buildTabs(),
            const Divider(color: NewsPalette.hairline, height: 1),
            Expanded(child: _buildBody()),
          ],
        ),
      ),
    );
  }

  Widget _buildMasthead() {
    final now = DateTime.now();
    const weekdays = <String>['一', '二', '三', '四', '五', '六', '日'];
    final dateText =
        '${now.year}年${now.month}月${now.day}日 · 星期${weekdays[now.weekday - 1]}';
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 12, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              IconButton(
                key: const Key('news-back'),
                onPressed: () => Navigator.of(context).maybePop(),
                tooltip: '返回',
                icon: const Icon(
                  Icons.arrow_back_rounded,
                  size: 20,
                  color: NewsPalette.inkSoft,
                ),
                style: IconButton.styleFrom(
                  fixedSize: const Size(32, 32),
                  minimumSize: const Size(32, 32),
                  padding: EdgeInsets.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '东大校刊',
                      style: newsSerif(fontSize: 27, height: 1.05),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '号外 · NEU BETTER',
                      style: newsSans(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w600,
                        color: NewsPalette.red,
                      ),
                    ),
                  ],
                ),
              ),
              TextButton(
                key: const Key('news-clear-unread'),
                onPressed: _clearUnread,
                style: TextButton.styleFrom(
                  foregroundColor: NewsPalette.inkSoft,
                  minimumSize: const Size(0, 32),
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  textStyle: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                child: const Text('清除未读'),
              ),
              IconButton(
                key: const Key('news-settings'),
                onPressed: _openSections,
                tooltip: '选择板块',
                icon: const Icon(
                  Icons.tune_rounded,
                  size: 20,
                  color: NewsPalette.inkSoft,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Divider(color: NewsPalette.ink, height: 1, thickness: 1.2),
          const SizedBox(height: 2),
          const Divider(color: NewsPalette.ink, height: 1, thickness: 0.4),
          const SizedBox(height: 6),
          Row(
            children: [
              Text(
                dateText,
                style: newsSans(fontSize: 11, color: NewsPalette.inkSoft),
              ),
              const Spacer(),
              Text(
                '第 ${_visibleItems.length} 则',
                style: newsSans(fontSize: 11, color: NewsPalette.inkSoft),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTabs() {
    final tabs = <MapEntry<String, String>>[
      const MapEntry<String, String>(_allTab, '全部'),
      for (final id in _selected) MapEntry<String, String>(id, _sectionName(id)),
    ];
    return SizedBox(
      height: 42,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: tabs.length,
        separatorBuilder: (_, _) => const SizedBox(width: 20),
        itemBuilder: (context, index) {
          final tab = tabs[index];
          final active = tab.key == _activeTab;
          return GestureDetector(
            key: ValueKey<String>('news-tab-${tab.key}'),
            behavior: HitTestBehavior.opaque,
            onTap: () {
              if (_activeTab == tab.key) return;
              setState(() => _activeTab = tab.key);
              _loadActive(reset: true);
            },
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  tab.value,
                  style: newsSans(
                    fontSize: 14.5,
                    fontWeight: active ? FontWeight.w700 : FontWeight.w400,
                    color: active ? NewsPalette.ink : NewsPalette.inkSoft,
                  ),
                ),
                const SizedBox(height: 5),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  height: 2,
                  width: active ? 22 : 0,
                  color: NewsPalette.blue,
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildBody() {
    if (_bootstrapping) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }
    final items = _visibleItems;
    if (items.isEmpty) {
      if (_loading) {
        return const Center(child: CircularProgressIndicator(strokeWidth: 2));
      }
      if (_error != null) {
        return _buildError();
      }
      return _buildEmpty();
    }
    return RefreshIndicator(
      color: NewsPalette.blue,
      onRefresh: () => _loadActive(reset: true),
      child: ListView.builder(
        controller: _scroll,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 6, 20, 32),
        itemCount: items.length + 1,
        itemBuilder: (context, index) {
          if (index == items.length) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 18),
              child: Center(
                child: _loading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(
                        _activeCids.every(_exhaustedCid.contains)
                            ? '已加载全部'
                            : '',
                        style: newsSans(
                          fontSize: 11.5,
                          color: NewsPalette.inkSoft,
                        ),
                      ),
              ),
            );
          }
          final item = items[index];
          return index == 0 ? _buildHeadline(item) : _buildRow(item);
        },
      ),
    );
  }

  Widget _buildError() {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        const SizedBox(height: 100),
        const Icon(Icons.cloud_off_rounded, size: 32, color: NewsPalette.inkSoft),
        const SizedBox(height: 10),
        Center(
          child: Text('加载失败', style: newsSans(fontSize: 14)),
        ),
        const SizedBox(height: 4),
        Center(
          child: Text(
            _error ?? '',
            textAlign: TextAlign.center,
            style: newsSans(fontSize: 11.5, color: NewsPalette.inkSoft),
          ),
        ),
        const SizedBox(height: 12),
        Center(
          child: TextButton(
            onPressed: () => _loadActive(reset: true),
            child: const Text('重试'),
          ),
        ),
      ],
    );
  }

  Widget _buildEmpty() {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        const SizedBox(height: 120),
        Icon(Icons.article_outlined, size: 30, color: NewsPalette.inkSoft),
        const SizedBox(height: 10),
        Center(
          child: Text(
            '暂无内容',
            style: newsSans(fontSize: 13, color: NewsPalette.inkSoft),
          ),
        ),
        const SizedBox(height: 4),
        Center(
          child: Text(
            '下拉刷新或选择更多板块',
            style: newsSans(fontSize: 11.5, color: NewsPalette.inkSoft),
          ),
        ),
      ],
    );
  }

  Widget _buildHeadline(NewsItem item) {
    return GestureDetector(
      key: ValueKey<String>('news-item-${item.id}'),
      behavior: HitTestBehavior.opaque,
      onTap: () => _openItem(item),
      child: Container(
        padding: const EdgeInsets.only(bottom: 16),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: NewsPalette.hairline)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              item.cname.isEmpty ? '要闻' : item.cname,
              style: newsSans(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: NewsPalette.red,
              ),
            ),
            const SizedBox(height: 6),
            if (item.firstPic != null) ...[
              LayoutBuilder(
                builder: (context, constraints) {
                  final width = constraints.maxWidth < 460
                      ? constraints.maxWidth
                      : 460.0;
                  final height = (width * 9 / 16).clamp(0.0, 250.0);
                  return Align(
                    alignment: Alignment.centerLeft,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(2),
                      child: SizedBox(
                        width: width,
                        height: height,
                        child: Image.network(
                          item.firstPic!,
                          fit: BoxFit.cover,
                          loadingBuilder: (context, child, progress) {
                            if (progress == null) return child;
                            return Container(color: NewsPalette.hairline);
                          },
                          errorBuilder: (context, error, stack) => Container(
                            color: NewsPalette.hairline,
                            child: const Center(
                              child: Icon(
                                Icons.image_not_supported_outlined,
                                size: 26,
                                color: NewsPalette.inkSoft,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 10),
            ],
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (!_isRead(item))
                  Padding(
                    padding: const EdgeInsets.only(top: 8, right: 6),
                    child: Container(
                      width: 6,
                      height: 6,
                      decoration: const BoxDecoration(
                        color: NewsPalette.red,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                Expanded(
                  child: Text(
                    item.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: newsSerif(fontSize: 22, height: 1.32),
                  ),
                ),
              ],
            ),
            if (item.desc.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                item.desc,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: newsSans(
                  fontSize: 13,
                  height: 1.6,
                  color: NewsPalette.inkSoft,
                ),
              ),
            ],
            const SizedBox(height: 10),
            Text(
              '${item.cname.isEmpty ? _sectionName(item.cid) : item.cname} · ${item.shortDate}',
              style: newsSans(fontSize: 11, color: NewsPalette.inkSoft),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRow(NewsItem item) {
    return GestureDetector(
      key: ValueKey<String>('news-item-${item.id}'),
      behavior: HitTestBehavior.opaque,
      onTap: () => _openItem(item),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: NewsPalette.hairline)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (!_isRead(item))
                        Padding(
                          padding: const EdgeInsets.only(top: 7, right: 6),
                          child: Container(
                            width: 5,
                            height: 5,
                            decoration: const BoxDecoration(
                              color: NewsPalette.red,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                      Expanded(
                        child: Text(
                          item.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: newsSerif(fontSize: 16, height: 1.4),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${item.cname.isEmpty ? _sectionName(item.cid) : item.cname} · ${item.shortDate}',
                    style: newsSans(fontSize: 11, color: NewsPalette.inkSoft),
                  ),
                ],
              ),
            ),
            if (item.firstPic != null) ...[
              const SizedBox(width: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: Image.network(
                  item.firstPic!,
                  width: 96,
                  height: 72,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stack) => Container(
                    width: 96,
                    height: 72,
                    color: NewsPalette.hairline.withValues(alpha: 0.5),
                    child: const Icon(
                      Icons.image_not_supported_outlined,
                      size: 20,
                      color: NewsPalette.inkSoft,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
