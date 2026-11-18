import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neu_better_pro/core/network/campus_gateway_client.dart';
import 'package:neu_better_pro/core/plugins/campus_network_plugin.dart';
import 'package:neu_better_pro/core/plugins/plugin_service.dart';
import 'package:neu_better_pro/features/home/home_card_layout.dart';
import 'package:neu_better_pro/features/home/widgets/campus_network_card.dart';
import 'package:neu_better_pro/features/plugins/campus_network_monitor.dart';
import 'package:neu_better_pro/features/plugins/campus_network_page.dart';

class _Gateway extends CampusGatewayClient {
  CampusGatewayStatus next = const CampusGatewayStatus.offline();
  int reads = 0;

  @override
  Future<CampusGatewayStatus> readStatus() async {
    reads++;
    return next;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'the native plugin is installable on Windows from a cached catalog',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'campus_plugin_test_',
      );
      addTearDown(() => directory.delete(recursive: true));
      final cache = File('${directory.path}/catalog.json');
      await cache.writeAsString('''
      {"version":1,"plugins":[{
        "id":"campus-network","name":"Remote replacement","version":"9.0.0",
        "rendererVersion":1,"startPage":"home","pages":{"home":{"body":[]}}
      }]}
    ''');
      final service = PluginService(
        candidates: [File('${directory.path}/plugins.json')],
        cacheCandidates: [cache],
      );
      addTearDown(() => debugDefaultTargetPlatformOverride = null);

      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      final catalog = await service.fetchCatalog();
      final manifest = catalog.byId(campusNetworkPluginId);
      expect(manifest, same(campusNetworkPlugin));
      await service.install(manifest!);
      expect(
        await service.readInstalledManifests(),
        contains(campusNetworkPlugin),
      );

      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      expect(
        (await service.fetchCatalog()).byId(campusNetworkPluginId),
        isNull,
      );
      expect(await service.readInstalledManifests(), isEmpty);
    },
  );

  testWidgets(
    'the plugin shows gateway account data and PC traffic separately',
    (tester) async {
      final gateway = _Gateway()
        ..next = const CampusGatewayStatus.online(
          connectionKey: 'session',
          balance: 12.5,
          usedBytes: 1024 * 1024,
        );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            campusNetworkMonitorProvider.overrideWith(
              (_) => CampusNetworkMonitor(
                gateway: gateway,
                readCounters: () async => (id: 'A', received: 500, sent: 300),
              ),
            ),
          ],
          child: const MaterialApp(home: CampusNetworkPage()),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('校园网已连接'), findsOneWidget);
      expect(find.text('¥12.50'), findsOneWidget);
      expect(find.text('1.00 MiB'), findsOneWidget);
      expect(find.text('0 B'), findsOneWidget);
      expect(find.text('管理连接'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('resized home cards show live metrics and keep the same tally', (
    tester,
  ) async {
    final gateway = _Gateway()
      ..next = const CampusGatewayStatus.online(
        connectionKey: 'session',
        balance: 12.5,
        usedBytes: 1024 * 1024,
      );
    var received = 500;
    var opened = false;
    final size = ValueNotifier(HomeCardSize.s1x1);
    addTearDown(size.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          campusNetworkMonitorProvider.overrideWith(
            (_) => CampusNetworkMonitor(
              gateway: gateway,
              readCounters: () async =>
                  (id: 'A', received: received, sent: 300),
            ),
          ),
        ],
        child: MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(1.25)),
            child: child!,
          ),
          home: Center(
            child: ValueListenableBuilder(
              valueListenable: size,
              builder: (context, value, _) {
                final (rows, columns) = spanOf(value);
                return SizedBox(
                  height: rows * 88.0,
                  width: columns * 88.0,
                  child: CampusNetworkCard(
                    size: value,
                    onTap: () => opened = true,
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
    expect(gateway.reads, 0);
    expect(find.text('网费余额'), findsNothing);

    size.value = HomeCardSize.s2x2;
    await tester.pumpAndSettle();
    expect(find.text('已连接'), findsOneWidget);
    expect(find.text('¥12.50'), findsOneWidget);
    expect(find.text('1.00 MiB'), findsOneWidget);
    expect(find.text('0 B'), findsOneWidget);
    await tester.tap(find.text('网费余额'));
    expect(opened, isTrue);

    received += 250;
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    expect(find.text('250 B'), findsOneWidget);
    size.value = HomeCardSize.s2x4;
    await tester.pumpAndSettle();
    expect(find.text('250 B'), findsOneWidget);
    expect(find.text('¥12.50'), findsOneWidget);
    expect(find.text('1.00 MiB'), findsOneWidget);
    expect(tester.takeException(), isNull);

    gateway.next = const CampusGatewayStatus.offline();
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    expect(find.text('未登录'), findsOneWidget);
    expect(find.text('上次流量'), findsOneWidget);
    final reads = gateway.reads;
    size.value = HomeCardSize.s1x1;
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 5));
    expect(gateway.reads, reads);
    await tester.pumpWidget(const SizedBox());
  });

  test('parses online, offline and billing data from the gateway', () {
    final online = CampusGatewayClient.parseStatus('''
      neuBetterStatus({"error":"ok","online_ip":"192.0.2.1","add_time":90,
        "user_balance":"-1.50","sum_bytes":5368709120});
    ''');
    expect(online.online, isTrue);
    expect(online.balance, -1.5);
    expect(online.usedBytes, 5368709120);

    final missing = CampusGatewayClient.parseStatus('{"error":"ok"}');
    expect(missing.balance, isNull);
    expect(missing.usedBytes, isNull);
    expect(
      CampusGatewayClient.parseStatus(
        'neuBetterStatus({"res":"not_online_error"})',
      ).online,
      isFalse,
    );
    expect(
      () => CampusGatewayClient.parseStatus('{"error":"server_error"}'),
      throwsFormatException,
    );
  });

  test(
    'counts only local deltas and starts a fresh tally after reconnecting',
    () async {
      final gateway = _Gateway();
      var counters = (id: 'A', received: 1000, sent: 500);
      final monitor = CampusNetworkMonitor(
        gateway: gateway,
        readCounters: () async => counters,
      );
      addTearDown(monitor.dispose);

      await monitor.refresh();
      expect(monitor.connectionBytes, isNull);
      gateway.next = const CampusGatewayStatus.online(
        connectionKey: 'session-1',
        usedBytes: 100000,
      );
      await monitor.refresh();
      expect(monitor.connectionBytes, 0);

      counters = (id: 'A', received: 1300, sent: 550);
      gateway.next = const CampusGatewayStatus.online(
        connectionKey: 'session-1',
        usedBytes: 0, // Billing cycle reset.
      );
      await monitor.refresh();
      expect(monitor.status?.usedBytes, 0);
      expect(monitor.connectionBytes, 350);

      counters = (id: 'B', received: 1000000, sent: 600);
      await monitor.refresh();
      expect(monitor.connectionBytes, 350);
      expect(monitor.partial, isTrue);

      gateway.next = const CampusGatewayStatus.offline();
      await monitor.refresh();
      expect(monitor.connectionBytes, 350);
      gateway.next = const CampusGatewayStatus.online(
        connectionKey: 'session-2',
      );
      await monitor.refresh();
      expect(monitor.connectionBytes, 0);
      expect(monitor.partial, isFalse);
    },
  );
}
