import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/platform/external_url.dart';
import '../../core/settings/app_settings.dart';
import 'campus_network_format.dart';
import 'campus_network_polling.dart';
import 'campus_network_provider.dart';

class CampusNetworkPage extends ConsumerStatefulWidget {
  const CampusNetworkPage({super.key});

  @override
  ConsumerState<CampusNetworkPage> createState() => _CampusNetworkPageState();
}

class _CampusNetworkPageState extends ConsumerState<CampusNetworkPage> {
  late final _ssid = TextEditingController(
    text: ref.read(appSettingsProvider).campusWifiSsid,
  );
  bool _editingSsid = false;

  @override
  void dispose() {
    _ssid.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final network = ref.watch(campusNetworkControllerProvider);
    final settings = ref.watch(appSettingsProvider);
    ref.listen(
      appSettingsProvider.select((settings) => settings.campusWifiSsid),
      (_, next) {
        if (!_editingSsid) _ssid.text = next;
      },
    );
    final canConnect = network.supported && !network.busy;
    void connect() {
      FocusScope.of(context).unfocus();
      _editingSsid = false;
      network.connectFlow(_ssid.text);
    }

    final theme = Theme.of(context);
    return CampusNetworkPolling(
      child: Scaffold(
        appBar: AppBar(
          title: const Text('网络连接'),
          actions: [
            IconButton(
              tooltip: '刷新网关数据',
              onPressed: canConnect && !network.refreshing
                  ? network.refresh
                  : null,
              icon: const Icon(Icons.refresh_rounded),
            ),
          ],
        ),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
              children: [
                if (network.desktop)
                  TextField(
                    controller: _ssid,
                    enabled: canConnect,
                    onChanged: (_) => _editingSsid = true,
                    onSubmitted: canConnect ? (_) => connect() : null,
                    autocorrect: false,
                    decoration: const InputDecoration(
                      labelText: '备用 Wi-Fi 名称',
                      hintText: AppSettings.defaultCampusWifiSsid,
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.wifi_rounded),
                    ),
                  )
                else
                  const Text('校园 Wi-Fi · NEU'),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerLeft,
                  child: FilledButton.icon(
                    onPressed: canConnect ? connect : null,
                    icon: network.busy
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.wifi_rounded),
                    label: const Text('一键联网'),
                  ),
                ),
                const SizedBox(height: 16),
                Semantics(
                  liveRegion: true,
                  child: Text(
                    network.statusLabel,
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                if (network.error case final error?)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Semantics(
                      liveRegion: true,
                      child: Text(
                        error,
                        style: TextStyle(color: theme.colorScheme.error),
                      ),
                    ),
                  ),
                const SizedBox(height: 12),
                Card(
                  margin: EdgeInsets.zero,
                  child: Column(
                    children: [
                      ListTile(
                        title: const Text('当前网络'),
                        trailing: Text(network.connectionLabel),
                      ),
                      const Divider(height: 1),
                      ListTile(
                        title: const Text('网费余额'),
                        trailing: Text(formatCampusBalance(network.balance)),
                      ),
                      const Divider(height: 1),
                      ListTile(
                        title: const Text('网关已用流量'),
                        trailing: Text(formatCampusTraffic(network.sumBytes)),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  '流量为学校网关统计（仅校外 IPv4），以学校账单为准。',
                  style: theme.textTheme.bodySmall,
                ),
                if (network.desktop && network.supported)
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('开机自动连接校园网'),
                    subtitle: Text(
                      settings.autoStart
                          ? '应用随 Windows 启动时，自动检测线路并登录网关。'
                          : '请先在应用设置中开启「开机自启」。',
                    ),
                    value: settings.campusAutoConnect,
                    onChanged: settings.autoStart
                        ? settings.setCampusAutoConnect
                        : null,
                  ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: network.supported
                        ? () =>
                              ExternalUrl.open('https://ipgw.neu.edu.cn:8800/')
                        : null,
                    icon: const Icon(Icons.open_in_new_rounded, size: 16),
                    label: const Text('在浏览器查看明细'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
