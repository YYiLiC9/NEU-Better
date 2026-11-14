import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../core/storage/account_scope.dart';
import 'home_card_catalog.dart';
import 'home_card_layout.dart';

/// 首页卡片布局（顺序 + 尺寸）按账号持久化：`home_layout_<学号>.json`。
///
/// 内容：`{"order":["dorm","notify","mail"],"sizes":{"dorm":"s2x4",...}}`。
/// 空 / 损坏 / 未知 id 一律容错，缺省回落到 [defaultHomeCards] 的顺序与尺寸。
class HomeLayoutStore {
  const HomeLayoutStore({this.candidates});

  /// 测试可注入临时文件；生产用默认候选目录。
  final List<File>? candidates;

  static const _fileName = 'home_layout.json';

  List<File> get _primary =>
      candidates ?? AccountScope.scopedFiles(_fileName);

  List<File> get _legacy =>
      candidates != null ? const <File>[] : AccountScope.legacyFiles(_fileName);

  Future<List<HomeCardLayout>> read() async {
    for (final file in _primary) {
      final layout = await _tryRead(file);
      if (layout != null) return layout;
    }
    for (final file in _legacy) {
      final layout = await _tryRead(file);
      if (layout != null) {
        await save(layout);
        return layout;
      }
    }
    return defaultHomeCards();
  }

  Future<List<HomeCardLayout>?> _tryRead(File file) async {
    try {
      if (!await file.exists()) return null;
      final decoded = jsonDecode(await file.readAsString());
      return _normalize(decoded);
    } catch (error) {
      debugPrint('[home_layout] read failed at ${file.path}: $error');
      return null;
    }
  }

  List<HomeCardLayout>? _normalize(Object? decoded) {
    if (decoded is! Map) return null;

    final sizes = <String, HomeCardSize>{};
    final sizesRaw = decoded['sizes'];
    if (sizesRaw is Map) {
      sizesRaw.forEach((key, value) {
        final id = key?.toString() ?? '';
        final size = HomeCardLayout.sizeByName(value);
        if (knownHomeCardIds.contains(id) && size != null) sizes[id] = size;
      });
    }

    // 严格保留文件内的 id：只按 order 顺序重建，不自动补回被删除的卡片。
    final orderRaw = decoded['order'];
    final hasOrder = orderRaw is List;
    final ids = <String>[];
    if (hasOrder) {
      for (final entry in orderRaw) {
        final id = entry?.toString() ?? '';
        if (knownHomeCardIds.contains(id) && !ids.contains(id)) ids.add(id);
      }
    } else if (sizes.isNotEmpty) {
      // 无 order 但有 sizes：以 sizes 的键顺序作为顺序。
      ids.addAll(sizes.keys);
    } else {
      // 既无 order（数组）也无 sizes：视为损坏，回落默认。
      return null;
    }

    final defaults = <String, HomeCardSize>{
      for (final card in defaultHomeCards()) card.id: card.size,
    };
    return <HomeCardLayout>[
      for (final id in ids)
        HomeCardLayout(
          id: id,
          size: sizes[id] ?? defaults[id] ?? HomeCardSize.s1x1,
        ),
    ];
  }

  Future<void> save(List<HomeCardLayout> cards) async {
    final payload = jsonEncode(<String, dynamic>{
      'order': <String>[for (final card in cards) card.id],
      'sizes': <String, String>{
        for (final card in cards) card.id: card.size.name,
      },
    });
    for (final file in _primary) {
      try {
        await file.parent.create(recursive: true);
        await file.writeAsString(payload, flush: true);
        return;
      } catch (error) {
        debugPrint('[home_layout] save failed at ${file.path}: $error');
      }
    }
  }
}
