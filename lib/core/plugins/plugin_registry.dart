import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../storage/account_scope.dart';

/// 已安装插件登记表：按账号持久化 `plugins.json`，内容
/// `{"installed":{"library":"1.0.0"}}`。只负责 id→version 的登记；
/// 插件清单文件 `plugin_<id>.json` 的读写由 [PluginService] 负责。
class PluginRegistry {
  // ignore: prefer_initializing_formals
  PluginRegistry({List<File>? candidates}) : _candidates = candidates;

  final List<File>? _candidates;

  static const _fileName = 'plugins.json';

  List<File> get _primary => _candidates ?? AccountScope.scopedFiles(_fileName);

  List<File> get _legacy =>
      _candidates != null ? const <File>[] : AccountScope.legacyFiles(_fileName);

  Map<String, String> _installed = <String, String>{};
  bool _loaded = false;

  Map<String, String> get installed => Map<String, String>.unmodifiable(_installed);

  Set<String> get installedIds => _installed.keys.toSet();

  bool isInstalled(String id) => _installed.containsKey(id);

  String? versionOf(String id) => _installed[id];

  Future<void> load() async {
    _installed = <String, String>{};
    for (final file in <File>[..._primary, ..._legacy]) {
      try {
        if (!await file.exists()) continue;
        final decoded = jsonDecode(await file.readAsString());
        _installed = _normalize(decoded);
        _loaded = true;
        if (_legacy.contains(file)) await save();
        return;
      } catch (error) {
        debugPrint('[plugin_registry] read failed at ${file.path}: $error');
      }
    }
    _loaded = true;
  }

  Map<String, String> _normalize(Object? decoded) {
    if (decoded is! Map) return <String, String>{};
    final raw = decoded['installed'];
    if (raw is! Map) return <String, String>{};
    final result = <String, String>{};
    raw.forEach((key, value) {
      final id = key?.toString().trim() ?? '';
      final version = value?.toString().trim() ?? '';
      if (id.isEmpty) return;
      result[id] = version;
    });
    return result;
  }

  Future<void> _ensureLoaded() async {
    if (!_loaded) await load();
  }

  Future<void> install(String id, String version) async {
    await _ensureLoaded();
    _installed = <String, String>{..._installed, id: version};
    await save();
  }

  Future<void> uninstall(String id) async {
    await _ensureLoaded();
    if (!_installed.containsKey(id)) return;
    final next = Map<String, String>.from(_installed)..remove(id);
    _installed = next;
    await save();
  }

  Future<void> save() async {
    final payload = jsonEncode(<String, dynamic>{'installed': _installed});
    for (final file in _primary) {
      try {
        await file.parent.create(recursive: true);
        await file.writeAsString(payload, flush: true);
        return;
      } catch (error) {
        debugPrint('[plugin_registry] save failed at ${file.path}: $error');
      }
    }
  }
}
