import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/app_theme.dart';
import '../../../core/plugins/campus_network_plugin.dart';
import '../../plugins/campus_network_format.dart';
import '../../plugins/campus_network_polling.dart';
import '../../plugins/campus_network_provider.dart';
import '../home_card_layout.dart';
import 'plugin_card.dart';

class CampusNetworkCard extends StatelessWidget {
  const CampusNetworkCard({
    super.key,
    required this.size,
    required this.onTap,
    this.visible = true,
  });

  final HomeCardSize size;
  final VoidCallback onTap;
  final bool visible;

  @override
  Widget build(BuildContext context) => PluginCard(
    size: size,
    manifest: campusNetworkPlugin,
    onTap: onTap,
    expandedContent: size == HomeCardSize.s1x1
        ? null
        : CampusNetworkPolling(
            active: visible,
            child: _CampusNetworkDetails(wide: size == HomeCardSize.s2x4),
          ),
  );
}

class _CampusNetworkDetails extends ConsumerWidget {
  const _CampusNetworkDetails({required this.wide});

  final bool wide;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final network = ref.watch(campusNetworkControllerProvider);
    final metrics = [
      ('网费余额', formatCampusBalance(network.balance)),
      ('网关已用', formatCampusTraffic(network.sumBytes)),
    ];
    final labelStyle = TextStyle(fontSize: 10, color: AppColors.muted);
    final valueStyle = TextStyle(
      fontSize: wide ? 14 : 11,
      fontWeight: FontWeight.w600,
      color: AppColors.ink,
      fontFeatures: const [FontFeature.tabularFigures()],
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          network.statusLabel,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: labelStyle.copyWith(
            color: network.gatewayOnline == true
                ? AppColors.campusBlue
                : AppColors.muted,
          ),
        ),
        const SizedBox(height: 6),
        if (wide)
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
