import 'package:flutter_test/flutter_test.dart';
import 'package:neu_better_pro/core/plugins/plugin_models.dart';

Map<String, Object?> _plugin(String id, int enabled) => <String, Object?>{
  'id': id,
  'name': id == 'news' ? '新闻' : '图书馆',
  'description': '',
  'version': '1.0.0',
  'minAppVersion': '0.4.1',
  'rendererVersion': 1,
  'startPage': 'home',
  'enabled': enabled,
  'pages': <String, Object?>{
    'home': <String, Object?>{'title': 'title', 'body': <Object?>[]},
  },
};

PluginCatalog _catalog(List<Map<String, Object?>> plugins) =>
    PluginCatalog.fromJson(<String, Object?>{'version': 1, 'plugins': plugins});

void main() {
  group('PluginCatalog online/offline merge', () {
    test('remote catalog wins over bundled for same id (online authoritative)', () {
      final remote = _catalog([_plugin('library', 0), _plugin('news', 1)]);
      final bundled = _catalog([_plugin('library', 1)]);

      final merged = PluginCatalog.mergeWithBundled(
        remote,
        bundled,
        preferBundled: false,
      );

      expect(merged.byId('library')!.enabled, 0);
      expect(merged.byId('news')!.enabled, 1);
      expect(merged.enabledPlugins.map((e) => e.id), <String>['news']);
    });

    test('cache/offline fallback prefers bundled enabled flag', () {
      final cached = _catalog([_plugin('library', 1)]);
      final bundled = _catalog([_plugin('library', 0)]);

      final merged = PluginCatalog.mergeWithBundled(cached, bundled);

      expect(merged.byId('library')!.enabled, 0);
      expect(merged.enabledPlugins, isEmpty);
    });

    test('bundled only fills missing ids in online mode', () {
      final remote = _catalog([_plugin('news', 1)]);
      final bundled = _catalog([_plugin('library', 0)]);

      final merged = PluginCatalog.mergeWithBundled(
        remote,
        bundled,
        preferBundled: false,
      );

      expect(merged.byId('library'), isNotNull);
      expect(merged.byId('library')!.enabled, 0);
      expect(merged.enabledPlugins.map((e) => e.id), <String>['news']);
    });
  });
}
