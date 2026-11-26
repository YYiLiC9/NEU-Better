import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:neu_better_pro/core/plugins/plugin_service.dart';

Map<String, Object?> _plugin(String id, int enabled) => <String, Object?>{
  'id': id,
  'name': id,
  'description': 'desc $id',
  'version': '1.0.0',
  'minAppVersion': '0.4.1',
  'rendererVersion': 1,
  'startPage': 'home',
  'enabled': enabled,
  'pages': <String, Object?>{
    'home': <String, Object?>{'title': 'title', 'body': <Object?>[]},
  },
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('catalog cache file name is scoped by app version', () {
    final dir = Directory.systemTemp.createTempSync('plugin_cache_');
    addTearDown(() => dir.deleteSync(recursive: true));
    final candidates = <File>[File('${dir.path}/plugins.json')];

    final v1 = PluginService(candidates: candidates, appVersion: '1.0.0');
    final v2 = PluginService(candidates: candidates, appVersion: '2.0.0');

    String base(File f) => f.path.replaceAll('\\', '/').split('/').last;
    expect(v1.catalogCacheFiles.single.path, contains('plugins_catalog_1.0.0.json'));
    expect(v2.catalogCacheFiles.single.path, contains('plugins_catalog_2.0.0.json'));
    expect(base(v1.catalogCacheFiles.single), isNot(base(v2.catalogCacheFiles.single)));
  });

  test('same-version cache is returned without network', () async {
    final dir = Directory.systemTemp.createTempSync('plugin_cache_');
    addTearDown(() => dir.deleteSync(recursive: true));
    final cache = File('${dir.path}/plugins_catalog_1.0.0.json');
    await cache.writeAsString(
      jsonEncode(<String, Object?>{
        'version': 1,
        'plugins': <Object?>[_plugin('library', 1)],
      }),
    );

    final service = PluginService(
      candidates: <File>[File('${dir.path}/plugins.json')],
      appVersion: '1.0.0',
    );
    final catalog = await service.fetchCatalog();
    expect(catalog.byId('library')?.enabled, 1);
  });
}
