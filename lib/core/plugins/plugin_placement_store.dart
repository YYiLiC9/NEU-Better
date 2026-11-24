import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../storage/account_scope.dart';

/// 插件在界面中的摆放位置。
enum PluginPlacement {
  /// 不显示。
  none,

  /// 仅在首页卡片区显示。
  home,

  /// 显示在侧栏（同时保证首页有一张卡兜底）。
  sidebar,
}

PluginPlacement? _placementByName(Object? value) {
  return switch (value?.toString()) {
    'home' => PluginPlacement.home,
    'sidebar' => PluginPlacement.sidebar,
    'none' => PluginPlacement.none,
    _ => null,
  };
}

/// 插件摆放位置按账号持久化：`plugin_placements_<学号>.json`。
///
/// 内容：`{"placements":{"id":"home|sidebar"},"sidebarOrder":["id",...]}`。
/// `none` 可省略；空 / 损坏一律容错回落为空，不抛异常。
class PluginPlacementStore {
  PluginPlacementStore({this.candidates});

  /// 测试可注入临时文件；生产用默认候选目录。
  final List<File>? candidates;

  static const _fileName = 'plugin_placements.json';

  List<File> get _primary =>
      candidates ?? AccountScope.scopedFiles(_fileName);

  List<File> get _legacy =>
      candidates != null ? const <File>[] : AccountScope.legacyFiles(_fileName);

  final Map<String, PluginPlacement> _placements = <String, PluginPlacement>{};
  final List<String> _sidebarOrder = <String>[];

  /// 已记录的摆放（不含 none）。
  Map<String, PluginPlacement> get placements =>
      Map<String, PluginPlacement>.unmodifiable(_placements);

  /// 侧栏插件 id（按顺序）。
  List<String> get sidebarIds => List<String>.unmodifiable(_sidebarOrder);

  PluginPlacement placementOf(String id) =>
      _placements[id] ?? PluginPlacement.none;

  /// 从磁盘读取；无文件或损坏时保持为空。
  Future<void> load() async {
    _placements.clear();
    _sidebarOrder.clear();
    for (final file in _primary) {
      if (await _tryRead(file)) return;
    }
    for (final file in _legacy) {
      if (await _tryRead(file)) {
        await save();
        return;
      }
    }
  }

  Future<bool> _tryRead(File file) async {
    try {
      if (!await file.exists()) return false;
      final decoded = jsonDecode(await file.readAsString());
      return _apply(decoded);
    } catch (error) {
      debugPrint('[plugin_placements] read failed at ${file.path}: $error');
      return false;
    }
  }

  bool _apply(Object? decoded) {
    if (decoded is! Map) return false;

    final placementsRaw = decoded['placements'];
    if (placementsRaw is Map) {
      placementsRaw.forEach((key, value) {
        final id = key?.toString() ?? '';
        final placement = _placementByName(value);
        if (id.isNotEmpty &&
            placement != null &&
            placement != PluginPlacement.none) {
          _placements[id] = placement;
        }
      });
    }

    final orderRaw = decoded['sidebarOrder'];
    if (orderRaw is List) {
      for (final entry in orderRaw) {
        final id = entry?.toString() ?? '';
        if (id.isNotEmpty && !_sidebarOrder.contains(id)) _sidebarOrder.add(id);
      }
    }

    // 侧栏顺序与摆放保持一致：sidebar 放置的插件一定在顺序里；顺序中的插件
    // 必须是 sidebar（否则剔除）。
    for (final id in _placements.entries
        .where((e) => e.value == PluginPlacement.sidebar)
        .map((e) => e.key)) {
      if (!_sidebarOrder.contains(id)) _sidebarOrder.add(id);
    }
    _sidebarOrder.removeWhere(
      (id) => _placements[id] != PluginPlacement.sidebar,
    );
    return true;
  }

  /// 设置插件摆放位置并持久化。
  Future<void> setPlacement(String id, PluginPlacement placement) async {
    if (placement == PluginPlacement.none) {
      _placements.remove(id);
      _sidebarOrder.remove(id);
    } else {
      _placements[id] = placement;
      if (placement == PluginPlacement.sidebar) {
        if (!_sidebarOrder.contains(id)) _sidebarOrder.add(id);
      } else {
        _sidebarOrder.remove(id);
      }
    }
    await save();
  }

  /// 移除某插件（卸载时调用）并持久化。
  Future<void> remove(String id) async {
    _placements.remove(id);
    _sidebarOrder.remove(id);
    await save();
  }

  Future<void> save() async {
    final payload = jsonEncode(<String, dynamic>{
      'placements': <String, String>{
        for (final entry in _placements.entries)
          if (entry.value != PluginPlacement.none) entry.key: entry.value.name,
      },
      'sidebarOrder': List<String>.from(_sidebarOrder),
    });
    for (final file in _primary) {
      try {
        await file.parent.create(recursive: true);
        await file.writeAsString(payload, flush: true);
        return;
      } catch (error) {
        debugPrint('[plugin_placements] save failed at ${file.path}: $error');
      }
    }
  }
}
