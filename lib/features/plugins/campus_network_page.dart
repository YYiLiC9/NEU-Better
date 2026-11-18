import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:webview_flutter_windows/webview_flutter_windows.dart';

import '../../core/network/campus_gateway_client.dart';
import 'campus_network_format.dart';
import 'campus_network_monitor.dart';

class CampusNetworkPage extends ConsumerStatefulWidget {
  const CampusNetworkPage({super.key});

  @override
  ConsumerState<CampusNetworkPage> createState() => _CampusNetworkPageState();
}

class _CampusNetworkPageState extends ConsumerState<CampusNetworkPage> {
  late final CampusNetworkMonitor _monitor;

  @override
  void initState() {
    super.initState();
    _monitor = ref.read(campusNetworkMonitorProvider);
    // Start polling after the navigation frame so existing listeners are idle.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _attached = true;
      _monitor.attach();
    });
  }

  bool _attached = false;

  @override
  void dispose() {
    if (_attached) _monitor.detach();
    super.dispose();
  }

  Future<void> _openPortal(Uri url, String title) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => _CampusGatewayWebPage(
          url: url,
          title: title,
          onNavigationCompleted: () => unawaited(_monitor.refresh()),
        ),
      ),
    );
    if (mounted) unawaited(_monitor.refresh());
  }

  @override
  Widget build(BuildContext context) {
    final monitor = ref.watch(campusNetworkMonitorProvider);
    final status = monitor.status;
    final online = status?.online == true;
    final connectionLabel = monitor.statusUnavailable
        ? '网关状态暂不可用'
        : switch (status?.online) {
            true => '校园网已连接',
            false => '校园网未登录',
            null => '正在查询网关',
          };

    return Scaffold(
      appBar: AppBar(
        title: const Text('网络连接'),
        actions: [
          IconButton(
            tooltip: '刷新网关数据',
            onPressed: monitor.refreshing ? null : monitor.refresh,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
            children: [
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  online && !monitor.statusUnavailable
                      ? Icons.wifi_rounded
                      : Icons.wifi_off_rounded,
                ),
                title: Text(connectionLabel),
                subtitle: Text(
                  monitor.statusUnavailable
                      ? '请检查电脑是否已接入东北大学校园网。'
                      : '接入校园网后，可通过学校统一身份认证连接互联网。',
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 12,
                runSpacing: 8,
                children: [
                  FilledButton.icon(
                    onPressed: () =>
                        _openPortal(CampusGatewayClient.portal, '东北大学校园网关'),
                    icon: const Icon(Icons.login_rounded),
                    label: Text(online ? '管理连接' : '登录网关'),
                  ),
                  OutlinedButton(
                    onPressed: () => _openPortal(
                      CampusGatewayClient.accountPortal,
                      '费用与流量明细',
                    ),
                    child: const Text('费用与流量明细'),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Card(
                margin: EdgeInsets.zero,
                child: Column(
                  children: [
                    ListTile(
                      title: const Text('网费余额'),
                      subtitle: const Text('网关账户余额'),
                      trailing: Text(formatCampusBalance(status?.balance)),
                    ),
                    const Divider(height: 1),
                    ListTile(
                      title: const Text('网关已用流量'),
                      subtitle: const Text('仅校外 IPv4 流量计入网关用量，套餐与结算以学校为准。'),
                      trailing: Text(formatCampusTraffic(status?.usedBytes)),
                    ),
                    const Divider(height: 1),
                    ListTile(
                      title: Text(
                        online || monitor.connectionBytes == null
                            ? '本次连接流量'
                            : '上次连接流量',
                      ),
                      subtitle: Text(
                        monitor.partial
                            ? '有采样中断，显示已统计的本机收发量。'
                            : '从识别到连接开始，每 5 秒统计本机网卡收发量，含校内及 IPv6。',
                      ),
                      trailing: Text(
                        formatCampusTraffic(monitor.connectionBytes),
                      ),
                    ),
                  ],
                ),
              ),
              if (monitor.statusUnavailable && status?.online == true) ...[
                const SizedBox(height: 8),
                const Text('网费和已用流量为最近一次成功读数。'),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _CampusGatewayWebPage extends StatefulWidget {
  const _CampusGatewayWebPage({
    required this.url,
    required this.title,
    required this.onNavigationCompleted,
  });

  final Uri url;
  final String title;
  final VoidCallback onNavigationCompleted;

  @override
  State<_CampusGatewayWebPage> createState() => _CampusGatewayWebPageState();
}

class _CampusGatewayWebPageState extends State<_CampusGatewayWebPage> {
  WebviewController? _controller;
  StreamSubscription<LoadingState>? _navigation;
  StreamSubscription<WebErrorStatus>? _loadErrors;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    unawaited(_initialize());
  }

  Future<void> _initialize() async {
    final controller = WebviewController();
    try {
      final directory = Directory(
        '${Directory.systemTemp.path}\\NEU Better\\WebView2',
      );
      await directory.create(recursive: true);
      try {
        await WebviewController.initializeEnvironment(
          userDataPath: directory.path,
        );
      } on PlatformException catch (error) {
        if (error.code != 'environment_already_initialized') rethrow;
      }
      await controller.initialize();
      await controller.setPopupWindowPolicy(
        WebviewPopupWindowPolicy.sameWindow,
      );
      if (!mounted) {
        await controller.dispose();
        return;
      }
      _navigation = controller.loadingState.listen((state) {
        if (state == LoadingState.navigationCompleted) {
          widget.onNavigationCompleted();
        }
      });
      _loadErrors = controller.onLoadError.listen((error) {
        if (mounted && error != WebErrorStatus.operationCanceled) {
          setState(() => _failed = true);
        }
      });
      setState(() => _controller = controller);
      await controller.loadUrl(widget.url.toString());
    } catch (_) {
      if (!identical(_controller, controller)) await controller.dispose();
      if (mounted) setState(() => _failed = true);
    }
  }

  Future<void> _retry() async {
    setState(() => _failed = false);
    final controller = _controller;
    if (controller == null) {
      await _initialize();
      return;
    }
    try {
      await controller.loadUrl(widget.url.toString());
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  void dispose() {
    unawaited(_navigation?.cancel());
    unawaited(_loadErrors?.cancel());
    unawaited(_controller?.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: _failed
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('暂时无法打开学校网关。'),
                  TextButton(onPressed: _retry, child: const Text('重试')),
                ],
              ),
            )
          : controller == null
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                StreamBuilder<String>(
                  stream: controller.url,
                  builder: (context, snapshot) {
                    final uri = Uri.tryParse(snapshot.data ?? '');
                    final origin =
                        uri != null &&
                            (uri.scheme == 'http' || uri.scheme == 'https') &&
                            uri.host.isNotEmpty
                        ? uri.origin
                        : widget.url.origin;
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Text(
                        origin,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    );
                  },
                ),
                Expanded(child: Webview(controller)),
              ],
            ),
    );
  }
}
