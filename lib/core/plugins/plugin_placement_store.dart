import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../storage/account_scope.dart';

/// 内置常驻卡片的默认外观：默认只在首页显示。
const Set<String> kDefaultHomePluginIds = <String>{'dorm', 'notify', 'mail'};

/// 插件在界面中的外观（可同时出现在首页与侧栏）。
@immutable
class PluginAppearance {
  const PluginAppearance({this.home = false, this.sidebar = false});

  final bool home;
  final bool sidebar;

  bool get none => !home && !sidebar;

  PluginAppearance copyWith({bool? home, bool? sidebar}) => PluginAppearance(
    home: home ?? this.home,
    sidebar: sidebar ?? this.sidebar,
  );

  Map<String, dynamic> toJson() => <String, dynamic>{
    'home': home,
    'sidebar': sidebar,
  };

  @override
  bool operator ==(Object other) =>
      other is PluginAppearance &&
      other.home == home &&
      other.sidebar == sidebar;

  @override
  int get hashCode => Object.hash(home, sidebar);

  @override
  String toString() => 'PluginAppearance(home: $home, sidebar: $sidebar)';
}

/// 某插件的默认外观：内置常驻卡片默认首页，其余默认不显示。
PluginAppearance defaultPluginAppearance(String id) => kDefaultHomePluginIds
    .contains(id)
    ? const PluginAppearance(home: true)
    : const PluginAppearance();

/// 解析单个 placement 值，兼容旧版字符串与新版对象。
PluginAppearance? _appearanceFrom(Object? value) {
  if (value is Map) {
    final home = value['home'] == true;
    final sidebar = value['sidebar'] == true;
    return PluginAppearance(home: home, sidebar: sidebar);
  }
  // 旧格式：字符串 home / sidebar / none。
  return switch (value?.toString()) {
    'home' => const PluginAppearance(home: true),
    'sidebar' => const PluginAppearance(sidebar: true),
    'none' => const PluginAppearance(),
    _ => null,
  };
}

/// 插件外观与侧栏顺序按账号持久化：`plugin_placements_<学号>.json`。
///
/// 内容：`{"placements":{"id":{"home":bool,"sidebar":bool}},
/// "sidebarOrder":["id",...],"sidebarCustomOrder":bool}`。
/// 兼容旧格式字符串 `home|sidebar|none`。空 / 损坏一律容错回落为空，不抛异常。
class PluginPlacementStore {
  PluginPlacementStore({this.candidates});

  /// 测试可注入临时文件；生产用默认候选目录。
  final List<File>? candidates;

  static const _fileName = 'plugin_placements.json';

  List<File> get _primary =>
      candidates ?? AccountScope.scopedFiles(_fileName);

  List<File> get _legacy =>
      candidates != null ? const <File>[] : AccountScope.legacyFiles(_fileName);

  final Map<String, PluginAppearance> _appearances =
      <String, PluginAppearance>{};
  final List<String> _sidebarOrder = <String>[];
  bool _sidebarCustomOrder = false;

  /// 已记录的外观（可能包含显式的 none）。
  Map<String, PluginAppearance> get appearances =>
      Map<String, PluginAppearance>.unmodifiable(_appearances);

  /// 侧栏插件 id（按顺序）。
  List<String> get sidebarIds => List<String>.unmodifiable(_sidebarOrder);

  /// 用户是否自定义过侧栏顺序（拖动后置 true）。
  bool get sidebarCustomOrder => _sidebarCustomOrder;

  /// 插件外观；无记录时返回平台默认（内置三项 home）。
  PluginAppearance appearanceOf(String id) =>
      _appearances[id] ?? defaultPluginAppearance(id);

  /// 从磁盘读取；无文件或损坏时保持为空。
  Future<void> load() async {
    _appearances.clear();
    _sidebarOrder.clear();
    _sidebarCustomOrder = false;
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
        final appearance = _appearanceFrom(value);
        if (id.isNotEmpty && appearance != null) {
          _appearances[id] = appearance;
        }
      });
    }

    _sidebarCustomOrder = decoded['sidebarCustomOrder'] == true;

    final orderRaw = decoded['sidebarOrder'];
    if (orderRaw is List) {
      for (final entry in orderRaw) {
        final id = entry?.toString() ?? '';
        if (id.isNotEmpty &&
            !_sidebarOrder.contains(id) &&
            appearanceOf(id).sidebar) {
          _sidebarOrder.add(id);
        }
      }
    }

    // 侧栏顺序与外观保持一致：sidebar 的插件一定在顺序里；顺序中的插件
    // 必须仍是 sidebar（否则剔除）。
    for (final id in _appearances.entries
        .where((e) => e.value.sidebar)
        .map((e) => e.key)) {
      if (!_sidebarOrder.contains(id)) _sidebarOrder.add(id);
    }
    _sidebarOrder.removeWhere((id) => !appearanceOf(id).sidebar);
    return true;
  }

  /// 设置插件外观并持久化。
  Future<void> setAppearance(String id, PluginAppearance appearance) async {
    _appearances[id] = appearance;
    if (appearance.sidebar) {
      if (!_sidebarOrder.contains(id)) _sidebarOrder.add(id);
    } else {
      _sidebarOrder.remove(id);
    }
    await save();
  }

  /// 用户拖动侧栏后写入自定义顺序并持久化。
  Future<void> reorderSidebar(List<String> ids) async {
    final next = <String>[];
    for (final id in ids) {
      if (id.isNotEmpty &&
          !next.contains(id) &&
          appearanceOf(id).sidebar) {
        next.add(id);
      }
    }
    // 追加未列出的 sidebar 项，避免丢失。
    for (final id in _appearances.entries
        .where((e) => e.value.sidebar)
        .map((e) => e.key)) {
      if (!next.contains(id)) next.add(id);
    }
    _sidebarOrder
      ..clear()
      ..addAll(next);
    _sidebarCustomOrder = true;
    await save();
  }

  /// 移除某插件（卸载时调用）并持久化。
  Future<void> remove(String id) async {
    _appearances.remove(id);
    _sidebarOrder.remove(id);
    await save();
  }

  Future<void> save() async {
    final payload = jsonEncode(<String, dynamic>{
      'placements': <String, dynamic>{
        for (final entry in _appearances.entries)
          entry.key: entry.value.toJson(),
      },
      'sidebarOrder': List<String>.from(_sidebarOrder),
      'sidebarCustomOrder': _sidebarCustomOrder,
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
