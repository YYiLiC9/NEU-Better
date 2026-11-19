import 'package:flutter/material.dart';

import '../../core/models/news_models.dart';
import 'news_theme.dart';

/// 板块选择页：校内通知固定必选且禁用，其余可搜索、分组多选。
///
/// 完成后通过 [Navigator.pop] 返回 `List<String>`（始终包含校内通知）。
class NewsSectionsPage extends StatefulWidget {
  const NewsSectionsPage({
    super.key,
    required this.sections,
    required this.initialSelected,
  });

  final List<NewsSection> sections;
  final List<String> initialSelected;

  @override
  State<NewsSectionsPage> createState() => _NewsSectionsPageState();
}

class _NewsSectionsPageState extends State<NewsSectionsPage> {
  late final TextEditingController _search;
  late Set<String> _selected;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _search = TextEditingController();
    _selected = <String>{
      NewsPrefs.internalNoticeId,
      ...widget.initialSelected,
    }..removeWhere((id) => id.isEmpty);
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<NewsSection> get _selectable => widget.sections
      .where((section) {
        final query = _query.trim();
        if (query.isEmpty) return true;
        return section.name.contains(query);
      })
      .toList(growable: false);

  Map<String, List<NewsSection>> get _grouped {
    final groups = <String, List<NewsSection>>{};
    for (final section in _selectable) {
      groups.putIfAbsent(section.group, () => <NewsSection>[]).add(section);
    }
    return groups;
  }

  void _toggle(String id) {
    setState(() {
      if (_selected.contains(id)) {
        _selected.remove(id);
      } else {
        _selected.add(id);
      }
    });
  }

  void _done() {
    final ids = <String>[
      NewsPrefs.internalNoticeId,
      for (final section in widget.sections)
        if (section.id != NewsPrefs.internalNoticeId &&
            _selected.contains(section.id))
          section.id,
    ];
    Navigator.of(context).pop(ids);
  }

  @override
  Widget build(BuildContext context) {
    final groups = _grouped;
    return Scaffold(
      backgroundColor: NewsPalette.paper,
      appBar: AppBar(
        backgroundColor: NewsPalette.paper,
        foregroundColor: NewsPalette.ink,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        title: Text('选择板块', style: newsSerif(fontSize: 19)),
        actions: [
          TextButton(
            key: const Key('news-sections-done'),
            onPressed: _done,
            child: Text(
              '完成 · 已选 ${_selected.length}',
              style: newsSans(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: NewsPalette.blue,
              ),
            ),
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: TextField(
              key: const Key('news-sections-search'),
              controller: _search,
              style: newsSans(fontSize: 14),
              decoration: InputDecoration(
                isDense: true,
                hintText: '搜索板块',
                hintStyle: newsSans(
                  fontSize: 13,
                  color: NewsPalette.inkSoft,
                ),
                prefixIcon: const Icon(
                  Icons.search_rounded,
                  size: 18,
                  color: NewsPalette.inkSoft,
                ),
                filled: true,
                fillColor: Colors.white,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                enabledBorder: const OutlineInputBorder(
                  borderSide: BorderSide(color: NewsPalette.hairline),
                  borderRadius: BorderRadius.zero,
                ),
                focusedBorder: const OutlineInputBorder(
                  borderSide: BorderSide(color: NewsPalette.blue),
                  borderRadius: BorderRadius.zero,
                ),
              ),
              onChanged: (value) => setState(() => _query = value),
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
              children: [
                for (final entry in groups.entries) ...[
                  if (entry.key.trim().isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 12, bottom: 6),
                    child: Text(
                      entry.key,
                      style: newsSans(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: NewsPalette.inkSoft,
                      ),
                    ),
                  ),
                  for (final section in entry.value)
                    Builder(builder: (_) {
                      final locked =
                          section.id == NewsPrefs.internalNoticeId;
                      final tile = CheckboxListTile(
                        key: ValueKey('news-section-${section.id}'),
                        value: locked ? true : _selected.contains(section.id),
                        onChanged: locked ? null : (_) => _toggle(section.id),
                        controlAffinity: ListTileControlAffinity.leading,
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        activeColor:
                            locked ? NewsPalette.inkSoft : NewsPalette.blue,
                        title: Text(
                          section.name,
                          style: newsSans(
                            fontSize: 14,
                            color: locked
                                ? NewsPalette.inkSoft
                                : NewsPalette.ink,
                          ),
                        ),
                      );
                      return locked
                          ? Opacity(opacity: 0.55, child: tile)
                          : tile;
                    }),
                ],
                if (groups.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 40),
                    child: Center(
                      child: Text(
                        '没有匹配的板块',
                        style: newsSans(
                          fontSize: 13,
                          color: NewsPalette.inkSoft,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
