import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neu_better_pro/core/auth/saved_credentials.dart';
import 'package:neu_better_pro/core/network/srun_portal_client.dart';
import 'package:neu_better_pro/core/platform/windows_wifi.dart';
import 'package:neu_better_pro/core/plugins/campus_network_plugin.dart';
import 'package:neu_better_pro/core/plugins/plugin_service.dart';
import 'package:neu_better_pro/core/settings/app_settings.dart';
import 'package:neu_better_pro/features/home/home_card_layout.dart';
import 'package:neu_better_pro/features/home/widgets/campus_network_card.dart';
import 'package:neu_better_pro/features/plugins/campus_network_controller.dart';
import 'package:neu_better_pro/features/plugins/campus_network_page.dart';
import 'package:neu_better_pro/features/plugins/campus_network_provider.dart';
import 'package:neu_better_pro/features/plugins/campus_network_startup.dart';

const _credentials = SavedCredentials(
  username: '20260001',
  password: 'test-only',
);
const _online = SrunStatus(online: true, balance: 12.5, sumBytes: 1048576);
const _offline = SrunStatus(online: false, clientIp: '192.0.2.9');

class _MemorySettings extends AppSettingsStore {
  Map<String, dynamic> json = {};

  @override
  Future<AppSettings> read() async => AppSettings.fromJson(json);

  @override
  Future<void> save(AppSettings settings) async => json = settings.toJson();
}

class _StartupSettings extends AppSettingsStore {
  late AppSettings settings;

  @override
  Future<AppSettings> readForAccount(String account) async {
    expect(account, _credentials.username);
    return settings;
  }
}

class _Wifi extends WindowsWifi {
  String? current;
  bool unavailable = false;
  Future<void> Function(String)? onConnect;
  int attempts = 0;

  @override
  Future<String?> currentSsid({String? preferred}) async {
    if (unavailable) throw const WindowsWifiException('没有可用的 Wi-Fi 网卡');
    return current;
  }

  @override
  Future<String?> ipv4Address(String ssid) async =>
      current == ssid ? '192.0.2.9' : null;

  @override
  Future<void> connect(String ssid) async {
    attempts++;
    await onConnect?.call(ssid);
    current = ssid;
  }
}

class _Gateway extends SrunPortalClient {
  SrunStatus next = _offline;
  SrunStatus? systemStatus;
  Future<SrunStatus> Function()? onStatus;
  Future<void> Function()? onLogin;
  int reads = 0;
  int systemReads = 0;
  int logins = 0;
  String? sourceAddress;

  @override
  void useSourceAddress(String? ip) => sourceAddress = ip;

  @override
  Future<SrunStatus> status() async {
    if (sourceAddress == null) {
      systemReads++;
      return systemStatus ?? (throw const SrunUnavailable());
    }
    reads++;
    return onStatus != null ? await onStatus!() : next;
  }

  @override
  Future<void> login({
    required String username,
    required String password,
    String? clientIp,
  }) async {
    expect(username, _credentials.username);
    expect(password, _credentials.password);
    expect(clientIp, _offline.clientIp);
    logins++;
    await onLogin?.call();
    next = _online;
  }
}

class _TestNetwork {
  _TestNetwork({
    SavedCredentials? saved = _credentials,
    bool supported = true,
    bool desktop = true,
    AppSettings initial = const AppSettings(),
    Future<String?> Function()? wiredAddress,
  }) {
    settings = AppSettingsController(store: store, initial: initial);
    controller = CampusNetworkController(
      settings: settings,
      readCredentials: () async {
        credentialReads++;
        return saved;
      },
      account: _credentials.username,
      supported: supported,
      desktop: desktop,
      wiredAddress: wiredAddress,
      wifi: wifi,
      gateway: gateway,
    );
  }

  final _Wifi wifi = _Wifi();
  final _Gateway gateway = _Gateway();
  final store = _MemorySettings();
  late final AppSettingsController settings;
  late final CampusNetworkController controller;
  int credentialReads = 0;

  Widget scope(Widget widget) => ProviderScope(
    overrides: [
      appSettingsProvider.overrideWith((_) => settings),
      campusNetworkControllerProvider.overrideWith((_) => controller),
    ],
    child: widget,
  );

  void dispose() {
    controller.dispose();
    settings.dispose();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('keeps the local plugin for Windows and Android', () async {
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
    final manifest = (await service.fetchCatalog()).byId(campusNetworkPluginId);
    expect(manifest, same(campusNetworkPlugin));
    await service.install(manifest!);
    expect(
      await service.readInstalledManifests(),
      contains(campusNetworkPlugin),
    );
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    expect(
      (await service.fetchCatalog()).byId(campusNetworkPluginId),
      same(campusNetworkPlugin),
    );
    expect(
      await service.readInstalledManifests(),
      contains(campusNetworkPlugin),
    );
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    expect((await service.fetchCatalog()).byId(campusNetworkPluginId), isNull);
    expect(await service.readInstalledManifests(), isEmpty);
  });

  test(
    'one-click connects Wi-Fi, logs in, confirms online and persists SSID',
    () async {
      final network = _TestNetwork();
      addTearDown(network.dispose);
      final controller = network.controller;
      final phases = <CampusConnectPhase>[];
      controller.addListener(() => phases.add(controller.phase));
      expect(controller.ssid, 'NEU');
      await controller.connectFlow(' NEU-Test ');
      expect(phases, [
        CampusConnectPhase.wifi,
        CampusConnectPhase.checking,
        CampusConnectPhase.login,
        CampusConnectPhase.confirming,
        CampusConnectPhase.idle,
      ]);
      expect(controller.wifiConnected, isTrue);
      expect(controller.gatewayOnline, isTrue);
      expect(controller.currentSsid, 'NEU-Test');
      expect(controller.balance, 12.5);
      expect(controller.sumBytes, 1048576);
      expect(controller.lastUpdated, isNotNull);
      expect(network.gateway.logins, 1);

      network.wifi.current = null;
      await controller.connectFlow('NEU-Test');
      expect(network.wifi.attempts, 2);
      expect(network.gateway.logins, 1);
      expect(network.credentialReads, 1);
      await network.settings.flush();
      expect((await network.store.read()).campusWifiSsid, 'NEU-Test');
      expect(AppSettings.fromJson({'campusWifiSsid': 7}).campusWifiSsid, 'NEU');
    },
  );

  test('stops at Wi-Fi failure and never reads credentials', () async {
    final network = _TestNetwork();
    addTearDown(network.dispose);
    network.wifi.onConnect = (_) async =>
        throw const WindowsWifiException('无线电已关闭');
    await network.controller.connectFlow('NEU');
    expect(network.controller.error, '无线电已关闭');
    expect(network.gateway.reads, 0);
    expect(network.credentialReads, 0);
  });

  test(
    'reports unreachable gateway and login rejection at the correct stages',
    () async {
      final network = _TestNetwork();
      addTearDown(network.dispose);
      network.gateway.onStatus = () async => throw const SrunUnavailable();
      await network.controller.connectFlow('NEU');
      expect(network.controller.error, contains('无法访问学校网关'));
      expect(network.credentialReads, 0);
      network.gateway.onStatus = null;
      network.gateway.onLogin = () async => throw const SrunRejected('账户余额不足');
      await network.controller.connectFlow('NEU');
      expect(network.controller.error, contains('账户余额不足'));
      expect(network.controller.gatewayOnline, isFalse);
    },
  );

  for (final saved in [
    null,
    const SavedCredentials(username: 'other', password: 'test'),
  ]) {
    test(
      'will not log in with ${saved == null ? 'missing' : 'another account’s'} credentials',
      () async {
        final network = _TestNetwork(saved: saved);
        addTearDown(network.dispose);
        await network.controller.connectFlow('NEU');
        expect(network.controller.error, contains('保存账号密码'));
        expect(network.gateway.logins, 0);
      },
    );
  }

  testWidgets('shows the one-click stages and the confirmed school metrics', (
    tester,
  ) async {
    final network = _TestNetwork();
    final wifiGate = Completer<void>();
    final loginGate = Completer<void>();
    network.wifi.onConnect = (_) => wifiGate.future;
    network.gateway.onLogin = () => loginGate.future;

    await tester.pumpWidget(
      network.scope(const MaterialApp(home: CampusNetworkPage())),
    );
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      'NEU',
    );
    await tester.tap(find.text('一键联网'));
    await tester.pump();
    expect(find.text('正在连接 Wi-Fi…'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    wifiGate.complete();
    await tester.pump();
    expect(find.text('正在登录网关…'), findsOneWidget);
    loginGate.complete();
    await tester.pumpAndSettle();
    expect(find.text('已连接'), findsOneWidget);
    expect(find.text('¥12.50'), findsOneWidget);
    expect(find.text('1.00 MiB'), findsOneWidget);
    expect(find.textContaining('本次连接流量'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('shows the missing password error and permits retry', (
    tester,
  ) async {
    final network = _TestNetwork(saved: null);
    await tester.pumpWidget(
      network.scope(const MaterialApp(home: CampusNetworkPage())),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('一键联网'));
    await tester.pumpAndSettle();
    expect(find.textContaining('保存账号密码'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, '一键联网'))
          .onPressed,
      isNotNull,
    );
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'polls only visible expanded cards and shows school metrics at both sizes',
    (tester) async {
      final network = _TestNetwork();
      network.wifi.current = 'NEU';
      network.gateway.next = _online;
      final size = ValueNotifier(HomeCardSize.s1x1);
      addTearDown(size.dispose);
      final navigator = GlobalKey<NavigatorState>();
      var opened = false;
      await tester.pumpWidget(
        network.scope(
          MaterialApp(
            navigatorKey: navigator,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: const TextScaler.linear(1.25)),
              child: child!,
            ),
            home: Scaffold(
              body: Center(
                child: ValueListenableBuilder(
                  valueListenable: size,
                  builder: (context, value, _) {
                    final (rows, columns) = spanOf(value);
                    return SizedBox(
                      height: rows * 88,
                      width: columns * 88,
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
        ),
      );
      expect(network.gateway.reads, 0);
      for (final expanded in [HomeCardSize.s2x2, HomeCardSize.s2x4]) {
        size.value = expanded;
        await tester.pumpAndSettle();
        expect(find.text('已连接'), findsOneWidget);
        expect(find.text('¥12.50'), findsOneWidget);
        expect(find.text('1.00 MiB'), findsOneWidget);
        expect(find.textContaining('本次'), findsNothing);
        expect(tester.takeException(), isNull);
      }
      await tester.tap(find.text('网费余额'));
      expect(opened, isTrue);
      await tester.pump(const Duration(seconds: 15));
      await tester.pumpAndSettle();
      expect(network.gateway.reads, greaterThanOrEqualTo(2));

      unawaited(
        navigator.currentState!.push<void>(
          MaterialPageRoute(
            builder: (_) => const Scaffold(body: Text('Another page')),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final before = network.gateway.reads;
      await tester.pump(const Duration(seconds: 31));
      expect(network.gateway.reads, before);
      navigator.currentState!.pop();
      await tester.pumpAndSettle();
      expect(network.gateway.reads, greaterThan(before));
      size.value = HomeCardSize.s1x1;
      await tester.pumpAndSettle();
      final collapsed = network.gateway.reads;
      await tester.pump(const Duration(seconds: 16));
      expect(network.gateway.reads, collapsed);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('the page cannot start Wi-Fi on other platforms', (tester) async {
    final network = _TestNetwork(supported: false);
    await tester.pumpWidget(
      network.scope(const MaterialApp(home: CampusNetworkPage())),
    );
    await tester.pumpAndSettle();
    expect(find.text('仅支持 Windows 和 Android'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, '一键联网'))
          .onPressed,
      isNull,
    );
    expect(network.wifi.attempts, 0);
    await tester.pumpWidget(const SizedBox());
  });

  test('uses the current Ethernet route before attempting Wi-Fi', () async {
    final network = _TestNetwork(wiredAddress: () async => '192.0.2.10');
    addTearDown(network.dispose);
    await network.controller.connectFlow('NEU');
    expect(network.wifi.attempts, 0);
    expect(network.gateway.sourceAddress, '192.0.2.10');
    expect(network.gateway.logins, 1);
    expect(network.controller.connectionLabel, '有线网络');
    expect(network.controller.gatewayOnline, isTrue);
  });

  test(
    'detects a campus session on a virtual Windows route without Wi-Fi',
    () async {
      final network = _TestNetwork(wiredAddress: () async => null);
      addTearDown(network.dispose);
      network.wifi.unavailable = true;
      network.gateway.systemStatus = _online;

      await network.controller.refresh();
      expect(network.controller.connectionLabel, '系统当前线路');
      expect(network.controller.gatewayOnline, isTrue);
      expect(network.controller.balance, 12.5);
      expect(network.controller.sumBytes, 1048576);
      expect(network.controller.error, isNull);

      await network.controller.connectFlow('NEU');
      expect(network.wifi.attempts, 0);
      expect(network.credentialReads, 0);
      expect(network.gateway.logins, 0);
      expect(network.gateway.systemReads, 2);
    },
  );

  test(
    'releases the source binding when the selected interface cannot reach SRun',
    () async {
      final network = _TestNetwork(wiredAddress: () async => '192.0.2.10');
      addTearDown(network.dispose);
      network.gateway.onStatus = () async => throw const SrunUnavailable();
      network.gateway.systemStatus = _online;

      await network.controller.refresh();
      expect(network.gateway.sourceAddress, isNull);
      expect(network.controller.gatewayOnline, isTrue);
      expect(network.controller.connectionLabel, '系统当前线路');

      network.gateway.onStatus = null;
      network.gateway.next = _online;
      await network.controller.refresh();
      expect(network.gateway.sourceAddress, '192.0.2.10');
      expect(network.controller.connectionLabel, '有线网络');
    },
  );

  test(
    'logs in through the selected Wi-Fi if the default route reports offline',
    () async {
      final network = _TestNetwork(wiredAddress: () async => null);
      addTearDown(network.dispose);
      network.gateway.systemStatus = _offline;
      await network.controller.refresh();
      expect(network.controller.gatewayOnline, isFalse);

      await network.controller.connectFlow('NEU');
      expect(network.wifi.attempts, 1);
      expect(network.gateway.sourceAddress, '192.0.2.9');
      expect(network.gateway.logins, 1);
      expect(network.controller.connectionLabel, 'Wi-Fi · NEU');
    },
  );

  test(
    'falls back to Wi-Fi only when the wired gateway is unreachable',
    () async {
      final network = _TestNetwork(wiredAddress: () async => '192.0.2.10');
      addTearDown(network.dispose);
      network.gateway.onStatus = () async {
        if (network.gateway.sourceAddress == '192.0.2.10') {
          throw const SrunUnavailable();
        }
        return network.gateway.next;
      };
      await network.controller.connectFlow('NEU');
      expect(network.wifi.attempts, 1);
      expect(network.gateway.sourceAddress, '192.0.2.9');
      expect(network.controller.connectionLabel, 'Wi-Fi · NEU');
      expect(network.controller.gatewayOnline, isTrue);
      await network.controller.refresh();
      expect(network.controller.gatewayOnline, isTrue);
    },
  );

  testWidgets(
    'Android continues through the gateway when system settings return',
    (tester) async {
      final network = _TestNetwork(desktop: false);
      final selection = Completer<void>();
      network.wifi.onConnect = (name) {
        expect(name, 'NEU');
        return selection.future;
      };
      await tester.pumpWidget(
        network.scope(const MaterialApp(home: CampusNetworkPage())),
      );
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsNothing);
      expect(find.byType(SwitchListTile), findsNothing);
      await tester.tap(find.text('一键联网'));
      await tester.pump();
      expect(find.text('请在系统界面连接 NEU Wi-Fi…'), findsOneWidget);
      expect(network.gateway.logins, 0);
      selection.complete();
      await tester.pumpAndSettle();
      expect(network.gateway.logins, 1);
      expect(find.text('已连接'), findsOneWidget);
      expect(find.text('Wi-Fi · NEU'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'Windows exposes the boot switch only when app startup is enabled',
    (tester) async {
      for (final autoStart in [false, true]) {
        final network = _TestNetwork(
          initial: AppSettings(autoStart: autoStart),
        );
        await tester.pumpWidget(
          network.scope(const MaterialApp(home: CampusNetworkPage())),
        );
        await tester.pumpAndSettle();
        final tile = tester.widget<SwitchListTile>(find.byType(SwitchListTile));
        expect(tile.onChanged != null, autoStart);
        tile.onChanged?.call(true);
        expect(network.settings.campusAutoConnect, autoStart);
        expect(
          network.settings.settings
              .copyWith(autoStart: false)
              .campusAutoConnect,
          isFalse,
        );
        await tester.pumpWidget(const SizedBox());
      }
    },
  );

  test(
    'startup only reads the scoped settings and respects both flags',
    () async {
      final store = _StartupSettings();
      var attempts = 0;
      for (final flags in [
        const AppSettings(campusAutoConnect: true),
        const AppSettings(autoStart: true),
        const AppSettings(autoStart: true, campusAutoConnect: true),
      ]) {
        store.settings = AppSettings.fromJson(flags.toJson());
        await connectCampusNetworkAtStartup(
          sessionAccount: _credentials.username,
          readCredentials: () async => _credentials,
          settingsStore: store,
          connect: (settings, account, credentials) async {
            attempts++;
            expect(settings.campusAutoConnect, isTrue);
            expect(account, _credentials.username);
            expect(credentials, same(_credentials));
          },
        );
      }
      expect(attempts, 1);
    },
  );

  testWidgets('does not poll cards outside the scroll viewport', (
    tester,
  ) async {
    final network = _TestNetwork();
    network.wifi.current = 'NEU';
    final scroll = ScrollController();
    addTearDown(scroll.dispose);
    await tester.pumpWidget(
      network.scope(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              controller: scroll,
              child: Column(
                children: [
                  const SizedBox(height: 900),
                  SizedBox(
                    height: 176,
                    width: 176,
                    child: CampusNetworkCard(
                      size: HomeCardSize.s2x2,
                      onTap: () {},
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(network.gateway.reads, 0);
    scroll.jumpTo(scroll.position.maxScrollExtent);
    await tester.pumpAndSettle();
    expect(network.gateway.reads, 1);
    scroll.jumpTo(0);
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 16));
    expect(network.gateway.reads, 1);
    await tester.pumpWidget(const SizedBox());
  });
}
