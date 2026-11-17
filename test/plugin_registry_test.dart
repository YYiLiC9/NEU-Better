import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:neu_better_pro/core/plugins/plugin_registry.dart';

void main() {
  test('install / uninstall persists to plugins.json', () async {
    final dir = await Directory.systemTemp.createTemp('plugin_registry_test_');
    final file = File('${dir.path}/plugins.json');

    final registry = PluginRegistry(candidates: [file]);
    await registry.load();
    expect(registry.installedIds, isEmpty);

    await registry.install('library', '1.0.0');
    await registry.install('news', '2.3.4');
    expect(registry.isInstalled('library'), isTrue);
    expect(registry.versionOf('news'), '2.3.4');

    // 重新加载验证落盘。
    final reloaded = PluginRegistry(candidates: [file]);
    await reloaded.load();
    expect(reloaded.installed, {'library': '1.0.0', 'news': '2.3.4'});

    await reloaded.uninstall('library');
    expect(reloaded.isInstalled('library'), isFalse);

    final third = PluginRegistry(candidates: [file]);
    await third.load();
    expect(third.installed, {'news': '2.3.4'});
    await dir.delete(recursive: true);
  });

  test('corrupt registry file falls back to empty', () async {
    final dir = await Directory.systemTemp.createTemp('plugin_registry_test2_');
    final file = File('${dir.path}/plugins.json');
    await file.writeAsString('not json');
    final registry = PluginRegistry(candidates: [file]);
    await registry.load();
    expect(registry.installedIds, isEmpty);
    await dir.delete(recursive: true);
  });
}
