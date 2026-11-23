import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/srun_portal_client.dart';
import '../../core/platform/external_url.dart';
import '../../core/settings/app_settings.dart';
import 'campus_network_format.dart';
import 'campus_network_polling.dart';
import 'campus_network_provider.dart';

class CampusNetworkPage extends ConsumerWidget {
  const CampusNetworkPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final network = ref.watch(campusNetworkControllerProvider);
    final settings = ref.watch(appSettingsProvider);
    final canRefresh =
        network.supported && !network.busy && !network.refreshing;
    final theme = Theme.of(context);
    final online = network.gatewayOnline == true;
    return CampusNetworkPolling(
      child: Scaffold(
        appBar: AppBar(
          title: const Text('网络连接'),
          actions: [
            IconButton(
              tooltip: '刷新网络状态',
              onPressed: canRefresh ? network.refresh : null,
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
                Align(
                  alignment: Alignment.centerLeft,
                  child: FilledButton.icon(
                    onPressed: online
                        ? (network.canLogout ? network.logoutGateway : null)
                        : (network.canLogin ? network.loginGateway : null),
                    style: online
                        ? FilledButton.styleFrom(
                            backgroundColor: theme.colorScheme.error,
                            foregroundColor: theme.colorScheme.onError,
                          )
                        : null,
                    icon: network.busy
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Icon(
                            online ? Icons.logout_rounded : Icons.login_rounded,
                          ),
                    label: Text(online ? '登出网关' : '登录网关'),
                  ),
                ),
                const SizedBox(height: 16),
                Semantics(
                  liveRegion: true,
                  child: Text(
                    !network.busy && online
                        ? '已连接校园网 · 已登录网关'
                        : network.statusLabel,
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                if (network.needsWifiPermission)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton(
                      onPressed: canRefresh
                          ? network.requestWifiPermission
                          : null,
                      child: const Text('授权识别 Wi-Fi'),
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
                if (network.canOpenPortal)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton(
                      onPressed: () =>
                          ExternalUrl.open(SrunPortalClient.ssoPageUrl),
                      child: const Text('在浏览器完成统一身份认证'),
                    ),
                  ),
                const SizedBox(height: 12),
                Card(
                  margin: EdgeInsets.zero,
                  child: Column(
                    children: [
                      ListTile(
                        title: const Text('当前网络'),
                        subtitle: Text(network.connectionLabel),
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
