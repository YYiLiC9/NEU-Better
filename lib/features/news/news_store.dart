import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../core/models/news_models.dart';
import '../../core/storage/account_scope.dart';

/// 已缓存栏目及缓存时间戳。
class NewsSectionsCache {
  const NewsSectionsCache({required this.sections, required this.fetchedAt});

  final List<NewsSection> sections;
  final DateTime fetchedAt;

  bool get isFresh =>
      DateTime.now().difference(fetchedAt) < const Duration(hours: 24);
}

/// 新闻本地偏好与栏目缓存：均按账号隔离。
///
/// - `news_prefs.json`：`{selectedCids:[...]}`，默认仅「校内通知」。
/// - `news_sections_cache.json`：`{fetchedAt:<ms>, sections:[{id,name,group}]}`。
class NewsStore {
  const NewsStore({this.candidates, this.cacheCandidates, this.readCandidates});

  final List<File>? candidates;
  final List<File>? cacheCandidates;
  final List<File>? readCandidates;

  static const String _prefsFile = 'news_prefs.json';
  static const String _cacheFile = 'news_sections_cache.json';
  static const String _readFile = 'news_read_ids.json';

  List<File> get _prefsPrimary =>
      candidates ?? AccountScope.scopedFiles(_prefsFile);

  List<File> get _cachePrimary =>
      cacheCandidates ?? AccountScope.scopedFiles(_cacheFile);

  List<File> get _readPrimary =>
      readCandidates ?? AccountScope.scopedFiles(_readFile);

  // ───────────────────────── prefs ─────────────────────────

  Future<NewsPrefs> readPrefs() async {
    for (final file in _prefsPrimary) {
      try {
        if (!await file.exists()) continue;
        final decoded = jsonDecode(await file.readAsString());
        final prefs = NewsPrefs.fromJson(decoded);
        if (prefs != null) return prefs;
      } catch (error) {
        debugPrint('[news] read prefs failed at ${file.path}: $error');
      }
    }
    return NewsPrefs.defaults();
  }

  Future<void> savePrefs(NewsPrefs prefs) async {
    final payload = jsonEncode(prefs.toJson());
    Object? lastError;
    for (final file in _prefsPrimary) {
      try {
        await file.parent.create(recursive: true);
        await file.writeAsString(payload, flush: true);
        return;
      } catch (error) {
        lastError = error;
        debugPrint('[news] save prefs failed at ${file.path}: $error');
      }
    }
    if (lastError != null) {
      debugPrint('[news] no writable path for prefs: $lastError');
    }
  }

  // ───────────────────────── read ids ─────────────────────────

  Future<Set<String>> readReadIds() async {
    for (final file in _readPrimary) {
      try {
        if (!await file.exists()) continue;
        final decoded = jsonDecode(await file.readAsString());
        if (decoded is Map && decoded['ids'] is List) {
          return <String>{
            for (final id in decoded['ids'] as List)
              if (id is String && id.isNotEmpty) id,
          };
        }
      } catch (error) {
        debugPrint('[news] read ids failed at ${file.path}: $error');
      }
    }
    return <String>{};
  }

  Future<void> saveReadIds(Set<String> ids) async {
    final payload = jsonEncode(<String, dynamic>{'ids': ids.toList()});
    for (final file in _readPrimary) {
      try {
        await file.parent.create(recursive: true);
        await file.writeAsString(payload, flush: true);
        return;
      } catch (error) {
        debugPrint('[news] save ids failed at ${file.path}: $error');
      }
    }
  }

  // ───────────────────────── sections cache ─────────────────────────

  Future<NewsSectionsCache?> readSectionsCache() async {
    for (final file in _cachePrimary) {
      try {
        if (!await file.exists()) continue;
        final decoded = jsonDecode(await file.readAsString());
        if (decoded is! Map) continue;
        final rawList = decoded['sections'];
        if (rawList is! List) continue;
        final sections = <NewsSection>[];
        for (final item in rawList) {
          if (item is! Map) continue;
          final id = (item['id'] ?? '').toString();
          final name = (item['name'] ?? '').toString();
          if (id.isEmpty || name.isEmpty) continue;
          sections.add(
            NewsSection(
              id: id,
              name: name,
              group: (item['group'] ?? '').toString(),
            ),
          );
        }
        final fetchedMs = decoded['fetchedAt'];
        final fetchedAt = fetchedMs is num
            ? DateTime.fromMillisecondsSinceEpoch(fetchedMs.toInt())
            : DateTime.fromMillisecondsSinceEpoch(0);
        if (sections.isEmpty) continue;
        return NewsSectionsCache(sections: sections, fetchedAt: fetchedAt);
      } catch (error) {
        debugPrint('[news] read sections cache failed: $error');
      }
    }
    return null;
  }

  Future<void> saveSectionsCache(List<NewsSection> sections) async {
    final payload = jsonEncode(<String, dynamic>{
      'fetchedAt': DateTime.now().millisecondsSinceEpoch,
      'sections': <Map<String, dynamic>>[
        for (final section in sections)
          <String, dynamic>{
            'id': section.id,
            'name': section.name,
            'group': section.group,
          },
      ],
    });
    for (final file in _cachePrimary) {
      try {
        await file.parent.create(recursive: true);
        await file.writeAsString(payload, flush: true);
        return;
      } catch (error) {
        debugPrint('[news] save sections cache failed at ${file.path}: $error');
      }
    }
  }
}
