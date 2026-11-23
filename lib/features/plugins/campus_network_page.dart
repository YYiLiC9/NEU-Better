import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/srun_portal_client.dart';
import '../../core/platform/external_url.dart';
import '../../core/plugins/campus_network_plugin.dart';
import '../../core/plugins/plugin_icon_resolver.dart';
import '../../core/settings/app_settings.dart';
import 'campus_network_controller.dart';
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
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    const duration = Duration(milliseconds: 280);
    final usage = network.gatewayOnline == true
        ? Padding(
            padding: const EdgeInsets.only(top: 16),
            child: _GatewayUsage(
              balance: formatCampusBalance(network.balance),
              traffic: formatCampusTraffic(network.sumBytes),
            ),
          )
        : null;
    final usageArea = reduceMotion
        ? usage
        : AnimatedSize(
            alignment: Alignment.topCenter,
            duration: duration,
            curve: Curves.easeOutCubic,
            child: usage == null
                ? const SizedBox.shrink()
                : TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0, end: 1),
                    duration: duration,
                    curve: Curves.easeOutCubic,
                    child: usage,
                    builder: (context, opacity, child) =>
                        Opacity(opacity: opacity, child: child),
                  ),
          );

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
        body: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
              children: [
                _GatewayOverview(network: network, canRefresh: canRefresh),
                ?usageArea,
                if (network.desktop && network.supported) ...[
                  const SizedBox(height: 16),
                  _NetworkSection(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: SwitchListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 20,
                      ),
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
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NetworkSection extends StatelessWidget {
  const _NetworkSection({
    required this.child,
    this.padding = const EdgeInsets.all(20),
  });

  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      color: colors.surface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: colors.outlineVariant),
      ),
      child: Padding(padding: padding, child: child),
    );
  }
}

class _GatewayOverview extends StatelessWidget {
  const _GatewayOverview({required this.network, required this.canRefresh});

  final CampusNetworkController network;
  final bool canRefresh;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final online = network.gatewayOnline == true;
    final hasGatewayStatus = !network.busy && network.gatewayOnline != null;
    final status = Row(
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            color: online
                ? colors.primaryContainer
                : colors.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Padding(
            padding: const EdgeInsets.all(11),
            child: Icon(
              resolvePluginIcon(campusNetworkPlugin.icon),
              color: online
                  ? colors.onPrimaryContainer
                  : colors.onSurfaceVariant,
            ),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Semantics(
            liveRegion: true,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  hasGatewayStatus
                      ? (online ? '已登录网关' : '未登录网关')
                      : network.statusLabel,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (hasGatewayStatus) ...[
                  const SizedBox(height: 2),
                  Text('已连接校园网', style: theme.textTheme.bodyMedium),
                ],
              ],
            ),
          ),
        ),
      ],
    );
    final action = FilledButton.icon(
      onPressed: online
          ? (network.canLogout ? network.logoutGateway : null)
          : (network.canLogin ? network.loginGateway : null),
      style: online
          ? FilledButton.styleFrom(
              backgroundColor: colors.error,
              foregroundColor: colors.onError,
            )
          : null,
      icon: network.busy
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Icon(online ? Icons.logout_rounded : Icons.login_rounded),
      label: Text(online ? '登出网关' : '登录网关'),
    );

    return _NetworkSection(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              if (constraints.maxWidth >=
                  MediaQuery.textScalerOf(context).scale(16) * 30) {
                return Row(
                  children: [
                    Expanded(child: status),
                    const SizedBox(width: 20),
                    action,
                  ],
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [status, const SizedBox(height: 16), action],
              );
            },
          ),
          const Divider(height: 32),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 2,
                child: Text('当前网络', style: theme.textTheme.bodyMedium),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 3,
                child: Text(
                  network.connectionLabel,
                  textAlign: TextAlign.end,
                  style: theme.textTheme.titleMedium,
                ),
              ),
            ],
          ),
          if (!online) ...[
            const SizedBox(height: 6),
            Text(
              campusGatewayUsageHint,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            ),
          ],
          if (network.error case final error?) ...[
            const SizedBox(height: 12),
            Semantics(
              liveRegion: true,
              child: Text(
                error,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colors.error,
                ),
              ),
            ),
          ],
          if (network.needsWifiPermission || network.canOpenPortal)
            Wrap(
              children: [
                if (network.needsWifiPermission)
                  TextButton(
                    onPressed: canRefresh
                        ? network.requestWifiPermission
                        : null,
                    child: const Text('授权识别 Wi-Fi'),
                  ),
                if (network.canOpenPortal)
                  TextButton(
                    onPressed: () =>
                        ExternalUrl.open(SrunPortalClient.ssoPageUrl),
                    child: const Text('在浏览器完成统一身份认证'),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

class _GatewayUsage extends StatelessWidget {
  const _GatewayUsage({required this.balance, required this.traffic});

  final String balance;
  final String traffic;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final balanceReading = _UsageReading(label: '网费余额', value: balance);
    final trafficReading = _UsageReading(label: '已用流量', value: traffic);

    return _NetworkSection(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              if (constraints.maxWidth >=
                  MediaQuery.textScalerOf(context).scale(16) * 26) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: balanceReading),
                    const SizedBox(width: 24),
                    Expanded(child: trafficReading),
                  ],
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  balanceReading,
                  const Divider(height: 24),
                  trafficReading,
                ],
              );
            },
          ),
          const Divider(height: 24),
          Text(
            '流量为学校网关统计（仅校外 IPv4），以学校账单为准。',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          TextButton.icon(
            onPressed: () => ExternalUrl.open('https://ipgw.neu.edu.cn:8800/'),
            icon: const Icon(Icons.open_in_new_rounded, size: 16),
            label: const Text('在浏览器查看明细'),
          ),
        ],
      ),
    );
  }
}

class _UsageReading extends StatelessWidget {
  const _UsageReading({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: theme.textTheme.bodyMedium),
        const SizedBox(height: 4),
        Text(
          value,
          style: theme.textTheme.headlineSmall?.copyWith(
            color: theme.colorScheme.primary,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}
