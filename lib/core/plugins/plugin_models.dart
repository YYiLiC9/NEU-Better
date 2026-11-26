import 'package:flutter/foundation.dart';

/// 当前 App 支持的插件渲染器版本。清单里 rendererVersion 更高则禁用（需更新 App）。
const int kPluginRendererVersion = 1;

/// 插件 id 允许的字符：小写字母、数字、下划线、连字符。
final RegExp pluginIdPattern = RegExp(r'^[a-z0-9_-]+$');

/// 把 `{{field}}` 模板用参数插值；只做字符串替换，不执行任何表达式/脚本。
/// 未提供的字段替换为空串。
String interpolateTemplate(String template, Map<String, Object?> params) {
  if (!template.contains('{{')) return template;
  return template.replaceAllMapped(RegExp(r'\{\{\s*([A-Za-z0-9_.-]+)\s*\}\}'), (m) {
    final key = m.group(1)!;
    final value = params[key];
    return value?.toString() ?? '';
  });
}

Map<String, Object?> _asMap(Object? value) {
  if (value is Map) {
    return <String, Object?>{
      for (final entry in value.entries) entry.key.toString(): entry.value,
    };
  }
  return <String, Object?>{};
}

List<Object?> _asList(Object? value) => value is List ? value : const <Object?>[];

@immutable
class PluginIcon {
  const PluginIcon({required this.type, required this.value});

  final String type;
  final String value;

  static PluginIcon? fromJson(Object? json) {
    if (json is! Map) return null;
    final type = json['type']?.toString().trim() ?? '';
    final value = json['value']?.toString().trim() ?? '';
    if (value.isEmpty) return null;
    return PluginIcon(type: type.isEmpty ? 'material' : type, value: value);
  }

  Map<String, Object?> toJson() => <String, Object?>{'type': type, 'value': value};
}

@immutable
class PluginActionSpec {
  const PluginActionSpec({
    required this.type,
    this.page,
    this.url,
    this.params = const <String, Object?>{},
  });

  final String type;
  final String? page;
  final String? url;
  final Map<String, Object?> params;

  bool get isSupported =>
      type == 'openPage' || type == 'openUrl' || type == 'refresh' || type == 'submitForm';

  static PluginActionSpec? fromJson(Object? json) {
    if (json is String && json.trim().isNotEmpty) {
      return PluginActionSpec(type: json.trim());
    }
    if (json is! Map) return null;
    final type = json['type']?.toString().trim() ?? '';
    if (type.isEmpty) return null;
    return PluginActionSpec(
      type: type,
      page: json['page']?.toString(),
      url: json['url']?.toString(),
      params: _asMap(json['params']),
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'type': type,
    if (page != null) 'page': page,
    if (url != null) 'url': url,
    if (params.isNotEmpty) 'params': params,
  };
}

/// 一个 DSL 组件。保留原始 json 供渲染器按需读取（list/text/button/form...）。
@immutable
class PluginComponentSpec {
  const PluginComponentSpec({required this.type, required this.json});

  final String type;
  final Map<String, Object?> json;

  Map<String, Object?> get data => _asMap(json['data']);
  Map<String, Object?>? get item => json['item'] == null ? null : _asMap(json['item']);
  String? get value => json['value']?.toString();
  String? get style => json['style']?.toString();
  String? get text => json['text']?.toString();
  PluginActionSpec? get action => PluginActionSpec.fromJson(json['action']);
  List<Object?> get fields => _asList(json['fields']);

  static PluginComponentSpec? fromJson(Object? json) {
    if (json is! Map) return null;
    final type = json['type']?.toString().trim() ?? '';
    if (type.isEmpty) return null;
    return PluginComponentSpec(type: type, json: _asMap(json));
  }
}

@immutable
class PluginPageSpec {
  const PluginPageSpec({required this.title, required this.body});

  final String title;
  final List<PluginComponentSpec> body;

  static PluginPageSpec? fromJson(Object? json) {
    if (json is! Map) return null;
    final title = json['title']?.toString().trim() ?? '';
    final body = <PluginComponentSpec>[];
    for (final entry in _asList(json['body'])) {
      final spec = PluginComponentSpec.fromJson(entry);
      if (spec != null) body.add(spec);
    }
    return PluginPageSpec(title: title.isEmpty ? '插件' : title, body: body);
  }
}

@immutable
class PluginManifest {
  const PluginManifest({
    required this.id,
    required this.name,
    required this.description,
    required this.version,
    required this.minAppVersion,
    required this.rendererVersion,
    required this.startPage,
    required this.pages,
    this.icon,
    this.cardTitle,
    this.cardSubtitle,
    this.enabled = 1,
    required this.raw,
  });

  final String id;
  final String name;
  final String description;
  final String version;
  final String minAppVersion;
  final int rendererVersion;
  final String startPage;
  final Map<String, PluginPageSpec> pages;
  final PluginIcon? icon;
  final String? cardTitle;
  final String? cardSubtitle;

  /// 远程插件开关：0=禁用（不上架、不可下载、插件库不显示）；1=正常可用。
  /// 缺省按 1 处理，兼容旧插件清单。
  final int enabled;

  final Map<String, Object?> raw;

  bool get isEnabled => enabled == 1;

  String get title => name;

  /// 当前 App 是否能渲染该插件（rendererVersion 不过高）。
  bool get rendererSupported => rendererVersion <= kPluginRendererVersion;

  /// 校验失败返回错误说明，合法返回 null。
  String? validate() {
    if (!pluginIdPattern.hasMatch(id)) return '非法插件 id：$id';
    if (name.trim().isEmpty) return '缺少插件名称';
    if (version.trim().isEmpty) return '缺少版本';
    if (rendererVersion <= 0) return '缺少 rendererVersion';
    if (pages.isEmpty) return '缺少 pages';
    if (!pages.containsKey(startPage)) return 'startPage 未在 pages 中：$startPage';
    return null;
  }

  bool get isValid => validate() == null;

  static PluginManifest? fromJson(Object? json) {
    if (json is! Map) return null;
    final pages = <String, PluginPageSpec>{};
    final pagesRaw = json['pages'];
    if (pagesRaw is Map) {
      pagesRaw.forEach((key, value) {
        final page = PluginPageSpec.fromJson(value);
        if (page != null) pages[key.toString()] = page;
      });
    }
    final card = json['card'] is Map ? _asMap(json['card']) : const <String, Object?>{};
    final manifest = PluginManifest(
      id: json['id']?.toString().trim() ?? '',
      name: json['name']?.toString().trim() ?? '',
      description: json['description']?.toString().trim() ?? '',
      version: json['version']?.toString().trim() ?? '',
      minAppVersion: json['minAppVersion']?.toString().trim() ?? '',
      rendererVersion: int.tryParse(json['rendererVersion']?.toString() ?? '') ?? 0,
      startPage: json['startPage']?.toString().trim() ?? '',
      pages: pages,
      icon: PluginIcon.fromJson(json['icon']),
      cardTitle: card['title']?.toString(),
      cardSubtitle: card['subtitle']?.toString(),
      enabled: int.tryParse(json['enabled']?.toString() ?? '') ?? 1,
      raw: _asMap(json),
    );
    return manifest.isValid ? manifest : null;
  }

  Map<String, Object?> toJson() => raw;
}

@immutable
class PluginCatalog {
  const PluginCatalog({required this.version, required this.plugins});

  final int version;
  final List<PluginManifest> plugins;

  PluginManifest? byId(String id) {
    for (final plugin in plugins) {
      if (plugin.id == id) return plugin;
    }
    return null;
  }

  Map<String, PluginManifest> byIdMap() => <String, PluginManifest>{
    for (final plugin in plugins) plugin.id: plugin,
  };

  static const PluginCatalog empty = PluginCatalog(version: 0, plugins: <PluginManifest>[]);

  /// 仅 enabled==1 的可选插件。
  List<PluginManifest> get enabledPlugins =>
      plugins.where((plugin) => plugin.isEnabled).toList(growable: false);

  /// 与随包目录合并。
  /// [preferBundled]=true 时同名以随包为准（用于缓存/离线兜底）；
  /// false 时同名以 [catalog] 为准（远程在线目录优先），仅补充随包中缺失的 id。
  static PluginCatalog mergeWithBundled(
    PluginCatalog catalog,
    PluginCatalog bundled, {
    bool preferBundled = true,
  }) {
    final merged = <String, PluginManifest>{
      for (final plugin in catalog.plugins) plugin.id: plugin,
    };
    if (preferBundled) {
      for (final plugin in bundled.plugins) {
        merged[plugin.id] = plugin;
      }
    } else {
      for (final plugin in bundled.plugins) {
        merged.putIfAbsent(plugin.id, () => plugin);
      }
    }
    return PluginCatalog(
      version: catalog.version,
      plugins: merged.values.toList(growable: false),
    );
  }

  static PluginCatalog fromJson(Object? json) {
    if (json is! Map) return empty;
    final version = int.tryParse(json['version']?.toString() ?? '') ?? 0;
    final seen = <String>{};
    final plugins = <PluginManifest>[];
    for (final entry in _asList(json['plugins'])) {
      final manifest = PluginManifest.fromJson(entry);
      if (manifest == null) continue;
      if (!seen.add(manifest.id)) continue; // 重复 id 跳过
      plugins.add(manifest);
    }
    return PluginCatalog(version: version, plugins: plugins);
  }
}
