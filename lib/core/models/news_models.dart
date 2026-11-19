import 'dart:convert';

/// 校园新闻的一个栏目（板块）。
class NewsSection {
  const NewsSection({
    required this.id,
    required this.name,
    required this.group,
  });

  final String id;
  final String name;

  /// 一级分组名，例如「新闻资讯」「通知公告」。
  final String group;

  @override
  bool operator ==(Object other) =>
      other is NewsSection && other.id == id && other.name == name;

  @override
  int get hashCode => Object.hash(id, name);
}

/// 新闻列表中的一条。
class NewsItem {
  const NewsItem({
    required this.id,
    required this.title,
    required this.desc,
    required this.picurls,
    required this.publishTime,
    required this.cname,
    required this.author,
    required this.reader,
    required this.hasRead,
    required this.url,
    required this.cid,
  });

  final String id;
  final String title;
  final String desc;
  final List<String> picurls;
  final String publishTime;
  final String cname;
  final String author;
  final int reader;
  final bool hasRead;
  final String url;
  final String cid;

  String? get firstPic => picurls.isEmpty ? null : picurls.first;

  /// 列表里展示的日期，如「11-17」。
  String get shortDate {
    final parsed = _tryParseDate(publishTime);
    if (parsed != null) {
      return '${_two(parsed.month)}-${_two(parsed.day)}';
    }
    return publishTime.length >= 10 ? publishTime.substring(5, 10) : publishTime;
  }

  NewsItem copyWith({bool? hasRead}) => NewsItem(
    id: id,
    title: title,
    desc: desc,
    picurls: picurls,
    publishTime: publishTime,
    cname: cname,
    author: author,
    reader: reader,
    hasRead: hasRead ?? this.hasRead,
    url: url,
    cid: cid,
  );
}

/// 新闻详情。
class NewsDetail {
  const NewsDetail({
    required this.id,
    required this.title,
    required this.contentHtml,
    required this.publishTime,
    required this.author,
    required this.cname,
    required this.picurls,
    required this.url,
    required this.attachments,
  });

  final String id;
  final String title;
  final String contentHtml;
  final String publishTime;
  final String author;
  final String cname;
  final List<String> picurls;
  final String url;
  final List<String> attachments;
}

/// 新闻列表分页结果。
class NewsListResult {
  const NewsListResult({required this.items, required this.total});

  final List<NewsItem> items;
  final int total;
}

/// 首页卡片/已选板块的本地偏好。
class NewsPrefs {
  const NewsPrefs({required this.selectedCids});

  final List<String> selectedCids;

  static const String internalNoticeId = '2d7a11e6513d09816161861c8ea0b9b6';

  /// 默认仅选「校内通知」。
  factory NewsPrefs.defaults() => const NewsPrefs(
    selectedCids: <String>[internalNoticeId],
  );

  NewsPrefs copyWith({List<String>? selectedCids}) =>
      NewsPrefs(selectedCids: selectedCids ?? this.selectedCids);

  Map<String, dynamic> toJson() => <String, dynamic>{
    'selectedCids': selectedCids,
  };

  static NewsPrefs? fromJson(Object? json) {
    if (json is! Map) return null;
    final raw = json['selectedCids'];
    if (raw is! List) return null;
    return NewsPrefs(
      selectedCids: <String>[
        for (final value in raw)
          if (value != null && value.toString().trim().isNotEmpty)
            value.toString(),
      ],
    );
  }

  /// 动态校正：去掉失效栏目、去重、并保证「校内通知」始终在列。
  List<String> normalized(Iterable<String> validIds) {
    final valid = validIds.toSet();
    final result = <String>[];
    void add(String id) {
      if (!result.contains(id)) result.add(id);
    }

    add(internalNoticeId);
    for (final id in selectedCids) {
      if (valid.isEmpty || valid.contains(id)) add(id);
    }
    return result;
  }
}

// ─────────────────────────── JSON 解析 ───────────────────────────

/// 解析 `module` 接口：`d.list[]` 是分组，含空的子栏目分组跳过。
List<NewsSection> parseNewsSections(Object? root) {
  final list = _asList(_dig(root, <String>['d', 'list']));
  final sections = <NewsSection>[];
  for (final group in list) {
    if (group is! Map) continue;
    final groupName = (group['name'] ?? '').toString();
    final children = _asList(group['children']);
    for (final child in children) {
      if (child is! Map) continue;
      final id = (child['id'] ?? '').toString();
      final name = (child['name'] ?? '').toString().trim();
      if (id.isEmpty || name.isEmpty) continue;
      sections.add(NewsSection(id: id, name: name, group: groupName));
    }
  }
  return sections;
}

NewsListResult parseNewsList(Object? root) {
  final d = _dig(root, <String>['d']);
  final list = _asList(d is Map ? d['list'] : null);
  final total = _asInt(d is Map ? d['total'] : null) ?? list.length;
  final items = <NewsItem>[];
  for (final raw in list) {
    if (raw is! Map) continue;
    final id = (raw['id'] ?? '').toString();
    if (id.isEmpty) continue;
    items.add(
      NewsItem(
        id: id,
        title: (raw['title'] ?? '').toString().trim(),
        desc: (raw['desc'] ?? '').toString().trim(),
        picurls: _asStringList(raw['picurl']),
        publishTime:
            (raw['publish_date_time'] ?? raw['publish_time'] ?? '').toString(),
        cname: (raw['cname'] ?? '').toString(),
        author: (raw['author'] ?? '').toString(),
        reader: _asInt(raw['reader']) ?? 0,
        hasRead: raw['has_read'] == true,
        url: (raw['url'] ?? '').toString(),
        cid: (raw['cid'] ?? '').toString(),
      ),
    );
  }
  return NewsListResult(items: items, total: total);
}

NewsDetail? parseNewsDetail(Object? root) {
  final d = _dig(root, <String>['d', 'data']);
  if (d is! Map) return null;
  final id = (d['id'] ?? '').toString();
  if (id.isEmpty) return null;
  return NewsDetail(
    id: id,
    title: (d['title'] ?? '').toString().trim(),
    contentHtml: (d['content'] ?? '').toString(),
    publishTime:
        (d['publish_date_time'] ?? d['publish_time'] ?? '').toString(),
    author: (d['author'] ?? '').toString(),
    cname: (d['cname'] ?? '').toString(),
    picurls: _asStringList(d['picurl']),
    url: (d['url'] ?? '').toString(),
    attachments: _asStringList(d['attachment']),
  );
}

/// 容错：picurl 可能是字符串数组、单个字符串或 JSON 字符串。
List<String> _asStringList(Object? value) {
  if (value == null) return const <String>[];
  if (value is String) {
    final text = value.trim();
    if (text.isEmpty) return const <String>[];
    if (text.startsWith('[')) {
      try {
        return _asStringList(jsonDecode(text));
      } catch (_) {}
    }
    return <String>[text];
  }
  if (value is List) {
    return <String>[
      for (final item in value)
        if (item != null && item.toString().trim().isNotEmpty)
          item.toString(),
    ];
  }
  return const <String>[];
}

Object? _dig(Object? root, List<String> path) {
  Object? current = root;
  for (final key in path) {
    if (current is! Map) return null;
    current = current[key];
  }
  return current;
}

List<Object?> _asList(Object? value) =>
    value is List ? value.cast<Object?>() : const <Object?>[];

int? _asInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '');
}

DateTime? _tryParseDate(String text) {
  final trimmed = text.trim();
  if (trimmed.isEmpty) return null;
  return DateTime.tryParse(trimmed.replaceFirst(' ', 'T'));
}

String _two(int value) => value.toString().padLeft(2, '0');
