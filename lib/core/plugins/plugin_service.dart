// ignore_for_file: prefer_initializing_formals

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../storage/account_scope.dart';
import 'campus_network_plugin.dart';
import 'plugin_models.dart';
import 'plugin_registry.dart';

/// 插件目录 / 安装包读写的业务层。
///
/// - 目录：远程 `plugins/index.json`（固定读取 master 分支，失败走镜像），
///   成功缓存 `plugins_catalog.json`。
/// - 安装：写 `plugin_<id>.json` + 登记 `plugins.json`；卸载反之。
class PluginService {
  PluginService({
    PluginRegistry? registry,
    List<File>? candidates,
    List<File>? cacheCandidates,
    Dio? dio,
  }) : _registry = registry ?? PluginRegistry(candidates: candidates),
       _candidates = candidates,
       _cacheCandidates = cacheCandidates,
       _dio = dio ?? _buildDio();

  final PluginRegistry _registry;
  final List<File>? _candidates;
  final List<File>? _cacheCandidates;
  final Dio _dio;

  PluginRegistry get registry => _registry;

  /// 插件目录地址：固定 master 分支，失败依次尝试镜像。
  static const List<String> catalogUrls = <String>[
    'https://raw.githubusercontent.com/YYiLiC9/NEU-Better/master/plugins/index.json',
    'https://ghfast.top/https://raw.githubusercontent.com/YYiLiC9/NEU-Better/master/plugins/index.json',
    'https://gh-proxy.com/https://raw.githubusercontent.com/YYiLiC9/NEU-Better/master/plugins/index.json',
  ];

  static const int _maxCatalogBytes = 2 * 1024 * 1024;

  static Dio _buildDio() => Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 12),
      receiveTimeout: const Duration(seconds: 20),
      responseType: ResponseType.plain,
      validateStatus: (status) => status != null && status >= 200 && status < 300,
    ),
  );

  /// 目录缓存文件（测试与排查可读）。
  List<File> get catalogCacheFiles => _catalogCacheFiles;

  List<File> get _catalogCacheFiles {
    const name = 'plugins_catalog.json';
    if (_cacheCandidates != null) return _cacheCandidates;
    if (_candidates != null) {
      final dir = _candidates.first.parent.path;
      return <File>[File('$dir${Platform.pathSeparator}$name')];
    }
    return AccountScope.scopedFiles(name);
  }

  List<File> _pluginFiles(String id) => _candidates != null
      ? <File>[File('${_candidates.first.parent.path}${Platform.pathSeparator}plugin_$id.json')]
      : <File>[
          ...AccountScope.scopedFiles('plugin_$id.json'),
          ...AccountScope.legacyFiles('plugin_$id.json'),
        ];

  Future<PluginCatalog> fetchCatalog({bool force = false}) async {
    final catalog = await _fetchCatalog(force: force);
    return PluginCatalog(
      version: catalog.version,
      plugins: [
        if (_supportsCampusNetwork) campusNetworkPlugin,
        for (final manifest in catalog.plugins)
          if (manifest.id != campusNetworkPluginId) manifest,
      ],
    );
  }

  bool get _supportsCampusNetwork =>
      defaultTargetPlatform == TargetPlatform.windows ||
      defaultTargetPlatform == TargetPlatform.android;

  Future<PluginCatalog> _fetchCatalog({required bool force}) async {
    if (!force) {
      final cached = await _readCache();
      if (cached != null) return _mergeBundled(cached);
      // 无缓存时先用随包内置目录秒开（断网/被墙也能看到可选插件），
      // 同时后台静默刷新远程目录供下次使用。
      final bundled = await _readBundledCatalog();
      if (bundled != null) {
        unawaited(_refreshCacheFromRemote());
        return bundled;
      }
    }
    Object? lastError;
    for (final url in catalogUrls) {
      try {
        final response = await _dio.get<String>(url);
        final body = response.data;
        if (body == null) continue;
        if (body.length > _maxCatalogBytes) {
          throw PluginException('插件目录超过 2MB，已忽略');
        }
        final catalog = PluginCatalog.fromJson(jsonDecode(body));
        await _writeCache(body);
        return await _mergeBundled(catalog);
      } catch (error) {
        lastError = error;
        debugPrint('[plugin_service] catalog fetch failed ($url): $error');
      }
    }
    final cached = await _readCache();
    if (cached != null) return _mergeBundled(cached);
    final bundled = await _readBundledCatalog();
    if (bundled != null) return bundled;
    throw PluginException('无法获取插件目录：$lastError');
  }

  /// 后台静默刷新远程目录缓存（失败忽略），不阻塞 UI。
  Future<void> _refreshCacheFromRemote() async {
    for (final url in catalogUrls) {
      try {
        final response = await _dio.get<String>(url);
        final body = response.data;
        if (body == null || body.length > _maxCatalogBytes) continue;
        if (PluginCatalog.fromJson(jsonDecode(body)).plugins.isEmpty) continue;
        await _writeCache(body);
        return;
      } catch (error) {
        debugPrint('[plugin_service] background catalog refresh failed: $error');
      }
    }
  }

  Future<PluginCatalog?> _readBundledCatalog() async {    try {
      final body = await rootBundle.loadString('assets/plugins/index.json');
      return PluginCatalog.fromJson(jsonDecode(body));
    } catch (error) {
      debugPrint('[plugin_service] bundled catalog failed: $error');
      return null;
    }
  }

  /// 合并随包内置目录：远程/缓存缺失的内置插件（如新闻）始终补上，避免旧缓存
  /// 或断网导致可选插件消失。
  Future<PluginCatalog> _mergeBundled(PluginCatalog catalog) async {
    final bundled = await _readBundledCatalog();
    if (bundled == null || bundled.plugins.isEmpty) return catalog;
    final ids = catalog.plugins.map((p) => p.id).toSet();
    final extra = bundled.plugins.where((p) => !ids.contains(p.id)).toList();
    if (extra.isEmpty) return catalog;
    return PluginCatalog(
      version: catalog.version,
      plugins: <PluginManifest>[...catalog.plugins, ...extra],
    );
  }

  Future<PluginCatalog?> _readCache() async {
    for (final file in _catalogCacheFiles) {
      try {
        if (!await file.exists()) continue;
        final text = await file.readAsString();
        if (text.length > _maxCatalogBytes) continue;
        return PluginCatalog.fromJson(jsonDecode(text));
      } catch (error) {
        debugPrint('[plugin_service] cache read failed at ${file.path}: $error');
      }
    }
    return null;
  }

  Future<void> _writeCache(String body) async {
    for (final file in _catalogCacheFiles) {
      try {
        await file.parent.create(recursive: true);
        await file.writeAsString(body, flush: true);
        return;
      } catch (error) {
        debugPrint('[plugin_service] cache write failed at ${file.path}: $error');
      }
    }
  }

  /// 读取已安装插件的完整清单（registry 中有登记但文件缺失的跳过）。
  Future<List<PluginManifest>> readInstalledManifests() async {
    await _registry.load();
    final result = <PluginManifest>[];
    for (final id in _registry.installedIds) {
      if (id == campusNetworkPluginId) {
        if (_supportsCampusNetwork) result.add(campusNetworkPlugin);
        continue;
      }
      final manifest = await _readInstalledManifest(id);
      if (manifest != null) result.add(manifest);
    }
    return result;
  }

  Future<PluginManifest?> _readInstalledManifest(String id) async {
    for (final file in _pluginFiles(id)) {
      try {
        if (!await file.exists()) continue;
        final raw = jsonDecode(await file.readAsString());
        if (raw is Map<String, dynamic>) {
          // 已安装清单可能保留旧版占位描述，读取时就地迁移并回写一次。
          if (id == 'news') {
            final desc = (raw['description'] ?? '').toString();
            if (desc.trim().isEmpty || desc.contains('即将上线')) {
              raw['description'] = '东大校刊 · 校内通知与要闻';
              try {
                await file.writeAsString(jsonEncode(raw), flush: true);
              } catch (error) {
                debugPrint('[plugin_service] migrate news description failed: $error');
              }
            }
          }
          return PluginManifest.fromJson(raw);
        }
        return PluginManifest.fromJson(
          Map<String, dynamic>.from(raw as Map),
        );
      } catch (error) {
        debugPrint('[plugin_service] manifest read failed at ${file.path}: $error');
      }
    }
    return null;
  }

  Future<Map<String, String>> installedVersions() async {
    await _registry.load();
    return _registry.installed;
  }

  Future<void> install(PluginManifest manifest) async {
    if (manifest.id == campusNetworkPluginId) {
      if (!_supportsCampusNetwork) throw PluginException('网络连接仅支持 Windows 和 Android');
      await _registry.install(campusNetworkPluginId, campusNetworkPlugin.version);
      return;
    }
    final payload = jsonEncode(manifest.toJson());
    var written = false;
    for (final file in _pluginFiles(manifest.id)) {
      try {
        await file.parent.create(recursive: true);
        await file.writeAsString(payload, flush: true);
        written = true;
        break;
      } catch (error) {
        debugPrint('[plugin_service] install write failed at ${file.path}: $error');
      }
    }
    if (!written) throw PluginException('写入插件文件失败：${manifest.id}');
    await _registry.install(manifest.id, manifest.version);
  }

  Future<void> uninstall(String id) async {
    for (final file in _pluginFiles(id)) {
      try {
        if (await file.exists()) await file.delete();
      } catch (error) {
        debugPrint('[plugin_service] uninstall delete failed at ${file.path}: $error');
      }
    }
    await _registry.uninstall(id);
  }
}

class PluginException implements Exception {
  PluginException(this.message);

  final String message;

  @override
  String toString() => message;
}
