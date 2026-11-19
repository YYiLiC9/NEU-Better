import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/app_theme.dart';
import '../../../core/plugins/campus_network_plugin.dart';
import '../../plugins/campus_network_format.dart';
import '../../plugins/campus_network_monitor.dart';
import '../home_card_layout.dart';
import 'plugin_card.dart';

class CampusNetworkCard extends StatelessWidget {
  const CampusNetworkCard({super.key, required this.size, required this.onTap});

  final HomeCardSize size;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => PluginCard(
    size: size,
    manifest: campusNetworkPlugin,
    onTap: onTap,
    expandedContent: size == HomeCardSize.s1x1
        ? null
        : _CampusNetworkDetails(wide: size == HomeCardSize.s2x4),
  );
}

class _CampusNetworkDetails extends ConsumerStatefulWidget {
  const _CampusNetworkDetails({required this.wide});

  final bool wide;

  @override
  ConsumerState<_CampusNetworkDetails> createState() =>
      _CampusNetworkDetailsState();
}

class _CampusNetworkDetailsState extends ConsumerState<_CampusNetworkDetails> {
  CampusNetworkMonitor? _attachedMonitor;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final monitor = ref.read(campusNetworkMonitorProvider);
      _attachedMonitor = monitor;
      monitor.attach();
    });
  }

  @override
  void dispose() {
    _attachedMonitor?.detach();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final monitor = ref.watch(campusNetworkMonitorProvider);
    final status = monitor.status;
    final statusLabel = monitor.statusUnavailable
        ? (status?.online == true ? '状态未知 · 最近读数' : '网关暂不可用')
        : switch (status?.online) {
            true => '已连接',
            false => '未登录',
            null => '正在查询',
          };
    final connectionLabel =
        status?.online == false && monitor.connectionBytes != null
        ? '上次流量'
        : '本次流量';
    final metrics = [
      (
        monitor.partial ? '$connectionLabel（部分）' : connectionLabel,
        formatCampusTraffic(monitor.connectionBytes),
      ),
      ('网费余额', formatCampusBalance(status?.balance)),
      ('网关已用', formatCampusTraffic(status?.usedBytes)),
    ];
    final labelStyle = TextStyle(fontSize: 10, color: AppColors.muted);
    final valueStyle = TextStyle(
      fontSize: widget.wide ? 14 : 11,
      fontWeight: FontWeight.w600,
      color: AppColors.ink,
      fontFeatures: const [FontFeature.tabularFigures()],
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          statusLabel,
          style: labelStyle.copyWith(
            color: status?.online == true && !monitor.statusUnavailable
                ? AppColors.campusBlue
                : AppColors.muted,
          ),
        ),
        const SizedBox(height: 6),
        if (widget.wide)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final (label, value) in metrics)
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(label, style: labelStyle),
                      const SizedBox(height: 2),
                      Text(value, style: valueStyle),
                    ],
                  ),
                ),
            ],
          )
        else
          for (final (label, value) in metrics)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 1),
              child: Row(
                children: [
                  Expanded(child: Text(label, style: labelStyle)),
                  Text(value, style: valueStyle),
                ],
              ),
            ),
      ],
    );
  }
}
