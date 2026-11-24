import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/auth/auth_exception.dart';
import '../../core/auth/saved_credentials.dart';
import '../../core/network/neu_cas_client.dart';
import '../../core/network/srun_portal_client.dart';
import '../../core/platform/android_campus_wifi.dart';
import '../../core/platform/campus_wifi.dart';
import '../../core/platform/windows_campus_route.dart';
import '../../core/platform/windows_wifi.dart';

enum CampusConnectPhase { idle, wifi, checking, login, logout, confirming }

class _CampusConnection {
  const _CampusConnection({
    this.label = '—',
    this.campusConnected,
    this.status,
    this.address,
    this.error,
  });

  final String label;
  final bool? campusConnected;
  final SrunStatus? status;
  final String? address;
  final String? error;
}

class CampusNetworkController extends ChangeNotifier {
  CampusNetworkController({
    required this._readCredentials,
    required this._requestGatewayTicket,
    required this._account,
    required this.supported,
    this.desktop = true,
    CampusWifi? wifi,
    SrunPortalClient? gateway,
    this._wiredAddress,
    this._connectWifiAtStartup,
    this._requestWifiPermission,
  }) : _wifi = wifi ?? WindowsWifi(),
       _gateway = gateway ?? SrunPortalClient();

  factory CampusNetworkController.forPlatform({
    required Future<SavedCredentials?> Function() readCredentials,
    required String? account,
    required TargetPlatform platform,
  }) {
    const android = AndroidCampusWifi();
    final windows = WindowsWifi();
    final desktop = platform == TargetPlatform.windows;
    final mobile = platform == TargetPlatform.android;
    return CampusNetworkController(
      readCredentials: readCredentials,
      requestGatewayTicket: _requestNativeGatewayTicket,
      account: account,
      supported: desktop || mobile,
      desktop: desktop,
      wifi: mobile ? android : windows,
      gateway: mobile
          ? SrunPortalClient(readResponse: android.readGateway)
          : null,
      wiredAddress: desktop ? const WindowsCampusRoute().wiredAddress : null,
      connectWifiAtStartup: desktop ? windows.connect : null,
      requestWifiPermission: mobile ? android.requestLocationPermission : null,
    );
  }

  static Future<String> _requestNativeGatewayTicket({
    required String username,
    required String password,
  }) async {
    final cas = NeuCasClient();
    try {
      return await cas
          .requestServiceTicket(
            username: username,
            password: password,
            service: SrunPortalClient.ssoService,
          )
          .timeout(
            const Duration(seconds: 35),
            onTimeout: () => throw const AuthException('统一身份认证超时，请使用网页登录。'),
          );
    } finally {
      cas.close();
    }
  }

  final Future<SavedCredentials?> Function() _readCredentials;
  final Future<String> Function({
    required String username,
    required String password,
  })
  _requestGatewayTicket;
  final String? _account;
  final CampusWifi _wifi;
  final SrunPortalClient _gateway;
  final Future<String?> Function()? _wiredAddress;
  final Future<void> Function(String)? _connectWifiAtStartup;
  final Future<void> Function()? _requestWifiPermission;
  final bool supported;
  final bool desktop;

  Timer? _poll;
  int _viewCount = 0;
  bool _disposed = false;
  bool _refreshing = false;
  bool _wifiPermissionRequired = false;
  _CampusConnection _connection = const _CampusConnection();
  CampusConnectPhase _phase = CampusConnectPhase.idle;
  String? _connectError;

  String get connectionLabel => _connection.label;
  String? get account => _account;
  String? get gatewayAddress => _connection.address;
  bool? get gatewayOnline => _connection.status?.online;
  double? get balance => _connection.status?.balance;
  int? get sumBytes => _connection.status?.sumBytes;
  CampusConnectPhase get phase => _phase;
  bool get busy => _phase != CampusConnectPhase.idle;
  bool get refreshing => _refreshing;
  bool get canLogin =>
      supported && !busy && !refreshing && gatewayOnline == false;
  bool get canLogout =>
      supported && !busy && !refreshing && gatewayOnline == true;
  bool get canOpenPortal =>
      supported && !busy && gatewayOnline != true && _connectError != null;
  bool get needsWifiPermission =>
      _wifiPermissionRequired && _requestWifiPermission != null;
  String? get error => _connectError ?? _connection.error;

  String get statusLabel => switch (_phase) {
    CampusConnectPhase.wifi => '正在连接 Wi-Fi…',
    CampusConnectPhase.checking => '正在检测学校网关…',
    CampusConnectPhase.login => '正在进行统一身份认证…',
    CampusConnectPhase.logout => '正在登出网关…',
    CampusConnectPhase.confirming => '正在确认网关状态…',
    CampusConnectPhase.idle when !supported => '仅支持 Windows 和 Android',
    CampusConnectPhase.idle when gatewayOnline == true => '已连接',
    CampusConnectPhase.idle when gatewayOnline == false => '已连接校园网 · 未登录网关',
    CampusConnectPhase.idle when _connection.campusConnected == true =>
      '已连接校园网 · 网关状态未知',
    CampusConnectPhase.idle when _connection.campusConnected == false =>
      '未连接校园网',
    CampusConnectPhase.idle when refreshing => '正在检测网络…',
    CampusConnectPhase.idle => '网络状态待检测',
  };

  void attach() {
    if (_disposed || !supported) return;
    _viewCount++;
    if (_viewCount != 1) return;
    _poll = Timer.periodic(
      const Duration(seconds: 15),
      (_) => unawaited(refresh()),
    );
    unawaited(refresh());
  }

  void detach() {
    if (_viewCount == 0 || --_viewCount != 0) return;
    _poll?.cancel();
    _poll = null;
  }

  Future<void> refresh() => _refresh();

  Future<void> requestWifiPermission() =>
      _refresh(requestPermission: _requestWifiPermission);

  Future<void> _refresh({Future<void> Function()? requestPermission}) async {
    if (_disposed || !supported || busy || refreshing) return;
    _refreshing = true;
    notifyListeners();
    try {
      await requestPermission?.call();
      if (_disposed) return;
      final connection = await _detectConnection();
      if (_disposed) return;
      _connection = connection;
      if (connection.status?.online != false) _connectError = null;
    } on CampusWifiException catch (failure) {
      _connectError = null;
      _connection = _CampusConnection(error: failure.message);
    } on Exception {
      _connectError = null;
      _connection = const _CampusConnection(error: '无法检测网络状态，请稍后刷新。');
    } finally {
      if (!_disposed) {
        _refreshing = false;
        notifyListeners();
      }
    }
  }

  Future<void> loginGateway() => _loginGateway();

  Future<void> connectAtStartup(String ssid) =>
      _loginGateway(startupSsid: ssid);

  Future<void> _loginGateway({String? startupSsid}) async {
    if (_disposed || !supported || busy || refreshing) return;
    _connectError = null;
    _updatePhase(CampusConnectPhase.checking);
    try {
      var connection = await _detectConnection();
      if (_disposed) return;
      _connection = connection;
      final connectWifi = _connectWifiAtStartup;
      if (connection.campusConnected == false &&
          startupSsid != null &&
          connectWifi != null) {
        _updatePhase(CampusConnectPhase.wifi);
        await connectWifi(startupSsid);
        if (_disposed) return;
        _updatePhase(CampusConnectPhase.checking);
        const timeout = Duration(seconds: 8);
        final address = await _waitForAddress(
          startupSsid,
          timeout,
        ).timeout(timeout, onTimeout: () => null);
        if (_disposed) return;
        final label = 'Wi-Fi · $startupSsid';
        connection = address == null
            ? _CampusConnection(
                label: label,
                campusConnected: false,
                error: 'Wi-Fi 尚未获取 IPv4 地址，请稍后重试。',
              )
            : await _probeGateway(label, address);
        if (_disposed) return;
        _connection = connection;
      }

      final initial = connection.status;
      if (initial == null || initial.online) return;
      _updatePhase(CampusConnectPhase.login);
      final saved = await _readCredentials().timeout(
        const Duration(seconds: 4),
        onTimeout: () => null,
      );
      if (_disposed) return;
      final password = saved?.password;
      final username = saved?.username.trim();
      if (username == null ||
          username.split('@').first != _account ||
          password == null ||
          password.isEmpty) {
        _connectError = '请先在应用中用当前账号登录，并勾选「保存账号密码」。';
        return;
      }
      final ticket = await _requestGatewayTicket(
        username: username,
        password: password,
      );
      if (_disposed) return;
      final current = await _probeGateway(connection.label, connection.address);
      if (_disposed) return;
      _connection = current;
      final status = current.status;
      if (status == null || status.online) return;
      if (initial.clientIp != null &&
          status.clientIp != null &&
          initial.clientIp != status.clientIp) {
        _connectError = '校园网 IPv4 已变化，请刷新状态后重新登录。';
        return;
      }
      await _gateway.loginWithTicket(ticket);
      await _confirmGateway(connection, online: true);
    } on CampusWifiException catch (failure) {
      _connectError = failure.message;
    } on AuthException catch (failure) {
      _connectError = failure.message;
    } on SrunRejected catch (failure) {
      _connectError = '网关登录失败。${failure.message}';
    } on SrunUnavailable {
      _connection = _gatewayUnavailable(_connection.label);
    } on FormatException {
      _connectError = '学校网关返回了无法识别的统一认证响应。';
    } catch (_) {
      _connectError = switch (phase) {
        CampusConnectPhase.wifi => '无法连接 Wi-Fi，请在系统设置中检查无线网络。',
        CampusConnectPhase.login => '无法完成统一身份认证，请使用网页登录。',
        _ => _gatewayUnavailable(_connection.label).error,
      };
    } finally {
      if (!_disposed) _updatePhase(CampusConnectPhase.idle);
    }
  }

  Future<void> logoutGateway() async {
    if (_disposed || !canLogout) return;
    final displayed = _connection;
    _connectError = null;
    _updatePhase(CampusConnectPhase.logout);
    try {
      final current = await _probeGateway(displayed.label, displayed.address);
      if (_disposed) return;
      _connection = current;
      final session = current.status;
      if (session == null || !session.online) return;
      if (session.connectionKey != displayed.status?.connectionKey) {
        _connectError = '网关在线会话已变化，请确认当前线路后再登出。';
        return;
      }
      await _gateway.logout(session);
      await _confirmGateway(current, online: false);
    } on SrunRejected catch (failure) {
      _connectError = '网关登出失败。${failure.message}';
    } on Exception {
      _connectError = '暂无法确认网关登出结果，请刷新状态。';
    } finally {
      if (!_disposed) _updatePhase(CampusConnectPhase.idle);
    }
  }

  Future<void> _confirmGateway(
    _CampusConnection connection, {
    required bool online,
  }) async {
    if (_disposed) return;
    _updatePhase(CampusConnectPhase.confirming);
    var confirmed = await _probeGateway(connection.label, connection.address);
    if (_disposed) return;
    if (confirmed.status?.online == !online) {
      await Future<void>.delayed(const Duration(milliseconds: 800));
      if (_disposed) return;
      confirmed = await _probeGateway(connection.label, connection.address);
      if (_disposed) return;
    }
    _connection = confirmed;
    if (confirmed.status?.online != online) {
      _connectError = online ? '网关尚未确认上线，请刷新状态。' : '网关尚未确认下线，请刷新状态。';
    }
  }

  Future<_CampusConnection> _detectConnection() async {
    String? wired;
    if (desktop) {
      wired = await _wiredAddress?.call();
      if (_disposed) return const _CampusConnection();
      if (wired != null) {
        final connection = await _probeGateway('有线网络', wired);
        if (_disposed || connection.campusConnected == true) return connection;
      }
    }

    _wifiPermissionRequired = false;
    String? ssid;
    String? address;
    try {
      ssid = await _wifi.currentSsid();
      if (_disposed) return const _CampusConnection();
      if (ssid != null && (desktop || AndroidCampusWifi.isCampusSsid(ssid))) {
        address = await _wifi.ipv4Address(ssid);
      }
    } on CampusWifiException catch (failure) {
      if (!desktop) {
        _wifiPermissionRequired = failure is CampusWifiPermissionRequired;
        return _CampusConnection(
          label: ssid == null ? '—' : 'Wi-Fi · $ssid',
          campusConnected: ssid == null ? null : true,
          error: failure.message,
        );
      }
    }
    if (_disposed) return const _CampusConnection();

    if (!desktop && !AndroidCampusWifi.isCampusSsid(ssid)) {
      return _CampusConnection(
        label: ssid == null ? '—' : 'Wi-Fi · $ssid',
        campusConnected: false,
        error: '请在系统 Wi-Fi 设置中连接 NEU、NEU-mobile 或 NEU2.4G。',
      );
    }

    final wifiLabel = ssid == null ? null : 'Wi-Fi · $ssid';
    if (address != null) {
      final connection = await _probeGateway(wifiLabel!, address);
      if (!desktop || _disposed || connection.campusConnected == true) {
        return connection;
      }
    }
    if (!desktop) {
      return _CampusConnection(
        label: wifiLabel!,
        campusConnected: true,
        error: '校园 Wi-Fi 尚未获取 IPv4 地址，请稍后刷新。',
      );
    }

    // The system route may reach IPGW through a VPN or a virtual adapter.
    final label = wifiLabel ?? (wired == null ? null : '有线网络');
    final connection = await _probeGateway(label ?? '系统当前线路', null);
    return connection.campusConnected == false && label == null
        ? _gatewayUnavailable('—')
        : connection;
  }

  Future<_CampusConnection> _probeGateway(String label, String? address) async {
    _gateway.useSourceAddress(address);
    try {
      return _CampusConnection(
        label: label,
        campusConnected: true,
        address: address,
        status: await _gateway.status(),
      );
    } on SrunUnavailable {
      return _gatewayUnavailable(label);
    } on SrunRejected catch (failure) {
      return _CampusConnection(
        label: label,
        campusConnected: true,
        error: failure.message,
      );
    } on FormatException {
      return _CampusConnection(
        label: label,
        campusConnected: true,
        error: '学校网关返回了无法识别的状态，请稍后刷新。',
      );
    }
  }

  _CampusConnection _gatewayUnavailable(String label) => _CampusConnection(
    label: label,
    campusConnected: !desktop,
    error: desktop
        ? '无法访问学校网关，请检查是否已连接东北大学校园网。'
        : '无法访问学校网关，请确认当前校园 Wi-Fi 可用后刷新。',
  );

  Future<String?> _waitForAddress(String ssid, Duration timeout) async {
    final clock = Stopwatch()..start();
    while (!_disposed && clock.elapsed < timeout) {
      final address = await _wifi.ipv4Address(ssid);
      if (address != null) return address;
      await Future<void>.delayed(const Duration(milliseconds: 600));
    }
    return null;
  }

  void _updatePhase(CampusConnectPhase phase) {
    _phase = phase;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _poll?.cancel();
    _gateway.close();
    super.dispose();
  }
}
