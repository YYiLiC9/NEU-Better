import 'plugin_models.dart';

const campusNetworkPluginId = 'campus-network';

// Native entry owned by the app, independent of downloaded plugin manifests.
final campusNetworkPlugin = PluginManifest.fromJson(const {
  'id': campusNetworkPluginId,
  'name': '网络连接',
  'description': '登录东北大学校园网，查看余额和连接用量',
  'version': '1.0.0',
  'rendererVersion': 1,
  'icon': {'type': 'text', 'value': '网'},
  'card': {'title': '网络连接', 'subtitle': '校园网 / 流量统计'},
  'startPage': 'home',
  'pages': {
    'home': {'title': '网络连接', 'body': []},
  },
})!;
