import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/app_theme.dart';
import '../../app/widgets/secondary_page_header.dart';
import '../../app/widgets/secondary_page_title.dart';
import '../../core/network/srun_portal_client.dart';
import '../../core/platform/external_url.dart';
import '../../core/settings/app_settings.dart';
import 'campus_network_controller.dart';
import 'campus_network_format.dart';
import 'campus_network_polling.dart';
import 'campus_network_provider.dart';

/// 网络连接页。
///
/// [onBack] 非空时作为「首页内嵌次级页」渲染（SecondaryPageHeader + 内容区，无 Scaffold）；
/// 为空时作为独立页（Scaffold + AppBar），供测试/独立路由复用。
class CampusNetworkPage extends ConsumerWidget {
  const CampusNetworkPage({super.key, this.onBack, this.visible = true});

  final VoidCallback? onBack;
  final bool visible;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final network = ref.watch(campusNetworkControllerProvider);
    final settings = ref.watch(appSettingsProvider);
    final canRefresh =
        network.supported && !network.busy && !network.refreshing;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    const duration = Duration(milliseconds: 280);

    final online = network.gatewayOnline == true;
    final usage = online
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

    final refreshButton = IconButton(
      tooltip: '刷新网络状态',
      onPressed: canRefresh ? network.refresh : null,
      icon: const Icon(Icons.refresh_rounded),
    );

    final content = Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          children: [
            _StatusCard(network: network, canRefresh: canRefresh),
            ?usageArea,
            if (network.desktop && network.supported) ...[
              const SizedBox(height: 16),
              _SurfaceCard(
                child: SwitchListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 20),
                  title: const Text('开机自动连接校园网'),
                  subtitle: Text(
                    settings.autoStart
                        ? '应用随 Windows 启动时，自动检测线路并登录网关。'
                        : '请先在应用设置中开启「开机自启」。',
                  ),
                  value: settings.campusAutoConnect,
                  onChanged:
                      settings.autoStart ? settings.setCampusAutoConnect : null,
                ),
              ),
            ],
          ],
        ),
      ),
    );

    return CampusNetworkPolling(
      active: visible,
      child: onBack != null
          ? Column(
              children: [
                SecondaryPageHeader(
                  title: '网络连接',
                  onBack: onBack,
                  actions: [refreshButton],
                ),
                Divider(height: 1, color: AppColors.line),
                Expanded(child: content),
              ],
            )
          : Scaffold(
              backgroundColor: AppColors.canvas,
              appBar: AppBar(
                backgroundColor: AppColors.surface,
                surfaceTintColor: Colors.transparent,
                elevation: 0,
                foregroundColor: AppColors.ink,
                title: const SecondaryPageTitle('网络连接'),
                actions: [refreshButton],
              ),
              body: content,
            ),
    );
  }
}

/// 统一的白底圆角卡片容器（AppColors 令牌，无阴影）。
class _SurfaceCard extends StatelessWidget {
  const _SurfaceCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: AppColors.line),
      ),
      child: Padding(padding: const EdgeInsets.all(24), child: child),
    );
  }
}

/// 状态卡：状态点 + 状态文字 + 账号/网关 IP + 单一主按钮。
class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.network, required this.canRefresh});

  final CampusNetworkController network;
  final bool canRefresh;

  @override
  Widget build(BuildContext context) {
    final online = network.gatewayOnline == true;
    final busy = network.busy;
    final hasGatewayStatus = !busy && network.gatewayOnline != null;
    final error = network.error;

    final Widget statusText;
    if (busy) {
      statusText = Text(network.statusLabel);
    } else if (hasGatewayStatus) {
      statusText = Text(online ? '已连接' : '未连接');
    } else {
      statusText = Text(network.statusLabel);
    }

    final dotColor = online
        ? AppColors.campusBlue
        : (error != null ? AppColors.nowRed : AppColors.muted);

    final status = Row(
      children: [
        if (busy)
          const SizedBox(
            width: 12,
            height: 12,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        else
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle),
          ),
        const SizedBox(width: 10),
        Expanded(
          child: Semantics(
            liveRegion: true,
            child: DefaultTextStyle.merge(
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: AppColors.ink,
              ),
              child: statusText,
            ),
          ),
        ),
      ],
    );

    final primaryLabel = online ? '登出网关' : '登录网关';
    final action = network.supported
        ? FilledButton.icon(
            onPressed: online
                ? (network.canLogout ? network.logoutGateway : null)
                : (network.canLogin ? network.loginGateway : null),
            style: online
                ? FilledButton.styleFrom(backgroundColor: AppColors.nowRed)
                : null,
            icon: busy
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(online ? Icons.logout_rounded : Icons.login_rounded),
            label: Text(primaryLabel),
          )
        : const SizedBox.shrink();

    return _SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              if (constraints.maxWidth >=
                  MediaQuery.textScalerOf(context).scale(16) * 26) {
                return Row(
                  children: [
                    Expanded(child: status),
                    const SizedBox(width: 16),
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
          Divider(height: 24, color: AppColors.line),
          Wrap(
            spacing: 24,
            runSpacing: 8,
            children: [
              _MetaItem(label: '账号', value: network.account ?? '—'),
              _MetaItem(
                label: '网关IP',
                value: network.gatewayAddress ?? '—',
              ),
              _MetaItem(label: '网络', value: network.connectionLabel),
            ],
          ),
          if (!online) ...[
            const SizedBox(height: 10),
            Text(
              campusGatewayUsageHint,
              style: TextStyle(fontSize: 12, color: AppColors.muted),
            ),
          ],
          if (error != null) ...[
            const SizedBox(height: 12),
            Semantics(
              liveRegion: true,
              child: Text(
                error,
                style: TextStyle(fontSize: 13, color: AppColors.nowRed),
              ),
            ),
          ],
          if (network.needsWifiPermission || network.canOpenPortal) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 4,
              children: [
                if (network.needsWifiPermission)
                  TextButton(
                    onPressed:
                        canRefresh ? network.requestWifiPermission : null,
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
        ],
      ),
    );
  }
}

class _MetaItem extends StatelessWidget {
  const _MetaItem({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: TextStyle(fontSize: 12, color: AppColors.muted)),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 13,
              color: AppColors.ink,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
      ],
    );
  }
}

/// 数据两列：网费余额 / 网关已用流量。宽屏两列，窄屏单列。
class _GatewayUsage extends StatelessWidget {
  const _GatewayUsage({required this.balance, required this.traffic});

  final String balance;
  final String traffic;

  @override
  Widget build(BuildContext context) {
    final metrics = <(String, String)>[
      ('网费余额', balance),
      ('网关已用', traffic),
    ];

    return _SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final unit = MediaQuery.textScalerOf(context).scale(16) * 6;
              final threeCol = constraints.maxWidth >= unit * 3;
              final twoCol = constraints.maxWidth >= unit * 2;
              if (threeCol) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (var i = 0; i < metrics.length; i++) ...[
                      if (i > 0)
                        Container(
                          width: 1,
                          height: 36,
                          color: AppColors.line,
                          margin: const EdgeInsets.symmetric(horizontal: 12),
                        ),
                      Expanded(
                        child: _Metric(
                          label: metrics[i].$1,
                          value: metrics[i].$2,
                        ),
                      ),
                    ],
                  ],
                );
              }
              final columns = twoCol ? 2 : 1;
              final gap = 16.0;
              final itemWidth = columns == 2
                  ? (constraints.maxWidth - gap) / 2
                  : constraints.maxWidth;
              return Wrap(
                spacing: gap,
                runSpacing: 16,
                children: [
                  for (final (label, value) in metrics)
                    SizedBox(
                      width: itemWidth,
                      child: _Metric(label: label, value: value),
                    ),
                ],
              );
            },
          ),
          Divider(height: 24, color: AppColors.line),
          Text(
            '流量为学校网关统计（仅校外 IPv4），以学校账单为准。',
            style: TextStyle(fontSize: 12, color: AppColors.muted),
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

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(fontSize: 12, color: AppColors.muted),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: AppColors.ink,
            fontFeatures: [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}
