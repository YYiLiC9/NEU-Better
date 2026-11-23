import 'plugin_models.dart';

const campusNetworkPluginId = 'campus-network';

// Native entry owned by the app, independent of downloaded plugin manifests.
final campusNetworkPlugin = PluginManifest.fromJson(const {
  'id': campusNetworkPluginId,
  'name': '网络连接',
  'description': '检测东北大学校园网连接，登录学校网关并查看余额和已用流量',
  'version': '1.0.0',
  'rendererVersion': 1,
  'icon': {'type': 'material', 'value': 'router'},
  'card': {'title': '网络连接', 'subtitle': '校园网 / 流量统计'},
  'startPage': 'home',
  'pages': {
    'home': {'title': '网络连接', 'body': []},
  },
})!;
