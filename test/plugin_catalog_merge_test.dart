import 'package:flutter_test/flutter_test.dart';

import 'package:neu_better_pro/core/plugins/plugin_models.dart';

Map<String, Object?> _plugin(
  String id, {
  int? enabled,
  String name = '插件',
}) {
  return <String, Object?>{
    'id': id,
    'name': name,
    'description': 'desc',
    'version': '1.0.0',
    'minAppVersion': '0.3.1',
    'rendererVersion': 1,
    'startPage': 'home',
    'pages': <String, Object?>{
      'home': <String, Object?>{
        'title': name,
        'body': <Object?>[],
      },
    },
    'enabled': ?enabled,
  };
}

PluginCatalog _catalog(List<Map<String, Object?>> plugins) =>
    PluginCatalog.fromJson(<String, Object?>{'version': 1, 'plugins': plugins});

void main() {
  test('missing enabled defaults to enabled', () {
    final catalog = _catalog([_plugin('library')]);
    expect(catalog.plugins.single.isEnabled, isTrue);
    expect(catalog.hasLegacyEnabledFlags, isTrue);
  });

  test('bundled manifest overrides same-id cached enabled flag', () {
    final cached = _catalog([_plugin('library', enabled: 1)]);
    final bundled = _catalog([_plugin('library', enabled: 0)]);
    final merged = PluginCatalog.mergePreferBundled(cached, bundled);
    expect(merged.byId('library')!.isEnabled, isFalse);
    expect(merged.plugins.length, 1);
  });

  test('bundled manifest adds missing plugins and keeps cache-only ones', () {
    final cached = _catalog([_plugin('library', enabled: 1), _plugin('extra')]);
    final bundled = _catalog([_plugin('news', enabled: 1)]);
    final merged = PluginCatalog.mergePreferBundled(cached, bundled);
    expect(merged.byId('library')!.isEnabled, isTrue);
    expect(merged.byId('extra'), isNotNull);
    expect(merged.byId('news'), isNotNull);
  });
}
