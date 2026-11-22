import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/auth/saved_credentials.dart';
import '../../core/network/srun_portal_client.dart';
import '../../core/platform/android_campus_wifi.dart';
import '../../core/platform/campus_wifi.dart';
import '../../core/platform/windows_campus_route.dart';
import '../../core/platform/windows_wifi.dart';
import '../../core/settings/app_settings.dart';

enum CampusConnectPhase { idle, wifi, checking, login, confirming }

enum _DesktopRoute { ethernet, system }

class CampusNetworkController extends ChangeNotifier {
  CampusNetworkController({
    required this._settings,
    required this._readCredentials,
    required this._account,
    required this.supported,
    this.desktop = true,
    CampusWifi? wifi,
    SrunPortalClient? gateway,
    this._wiredAddress,
  }) : _wifi = wifi ?? WindowsWifi(),
       _gateway = gateway ?? SrunPortalClient();

  factory CampusNetworkController.forPlatform({
    required AppSettingsController settings,
    required Future<SavedCredentials?> Function() readCredentials,
    required String? account,
    required TargetPlatform platform,
  }) {
    const android = AndroidCampusWifi();
    final desktop = platform == TargetPlatform.windows;
    final mobile = platform == TargetPlatform.android;
    return CampusNetworkController(
      settings: settings,
      readCredentials: readCredentials,
      account: account,
      supported: desktop || mobile,
      desktop: desktop,
      wifi: mobile ? android : null,
      gateway: mobile
          ? SrunPortalClient(
              readResponse: android.readGateway,
              deviceName: 'Android',
            )
          : null,
      wiredAddress: desktop ? const WindowsCampusRoute().wiredAddress : null,
    );
  }

  final AppSettingsController _settings;
  final Future<SavedCredentials?> Function() _readCredentials;
  final String? _account;
  final CampusWifi _wifi;
  final SrunPortalClient _gateway;
  final Future<String?> Function()? _wiredAddress;
  final bool supported;
  final bool desktop;

  Timer? _poll;
  int _viewCount = 0;
  int _generation = 0;
  bool _disposed = false;
  bool _refreshing = false;
  _DesktopRoute? _desktopRoute;
  String? _currentSsid;
  SrunStatus? _status;
  DateTime? _lastUpdated;
  CampusConnectPhase _phase = CampusConnectPhase.idle;
  String? _connectError;
  String? _statusError;

  String get ssid =>
      desktop ? _settings.campusWifiSsid : AndroidCampusWifi.ssid;
  String? get currentSsid => _currentSsid;
  bool get wifiConnected => _desktopRoute == null && _currentSsid == ssid;
  String get connectionLabel => switch (_desktopRoute) {
    _DesktopRoute.ethernet => '有线网络',
    _DesktopRoute.system => '系统当前线路',
    null => _currentSsid == null ? '—' : 'Wi-Fi · $_currentSsid',
  };
  bool? get gatewayOnline => _status?.online;
  double? get balance => _status?.balance;
  int? get sumBytes => _status?.sumBytes;
  DateTime? get lastUpdated => _lastUpdated;
  CampusConnectPhase get phase => _phase;
  bool get busy => _phase != CampusConnectPhase.idle;
  bool get refreshing => _refreshing;
  String? get error => _connectError ?? _statusError;

  String get statusLabel => switch (_phase) {
    CampusConnectPhase.wifi when !desktop => '请在系统界面连接 NEU Wi-Fi…',
    CampusConnectPhase.wifi => '正在连接 Wi-Fi…',
    CampusConnectPhase.checking => '正在检测学校网关…',
    CampusConnectPhase.login => '正在登录网关…',
    CampusConnectPhase.confirming => '正在确认网关状态…',
    CampusConnectPhase.idle when gatewayOnline == true => '已连接',
    CampusConnectPhase.idle when _statusError != null => '状态暂不可用',
    CampusConnectPhase.idle when gatewayOnline == false => '未登录网关',
    CampusConnectPhase.idle when refreshing => '正在查询…',
    CampusConnectPhase.idle when !supported => '仅支持 Windows 和 Android',
    CampusConnectPhase.idle => '未连接校园网',
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

  Future<void> refresh() async {
    if (_disposed || !supported || busy || refreshing) return;
    final generation = _generation;
    bool currentRequest() => !_disposed && generation == _generation;
    final target = ssid;
    _refreshing = true;
    notifyListeners();
    try {
      final wired = await _wiredAddress?.call();
      if (!currentRequest()) return;
      if (wired != null) {
        final status = await _probeGateway(wired);
        if (!currentRequest()) return;
        if (status != null) {
          _applyStatus(status, route: _DesktopRoute.ethernet);
          return;
        }
      }

      String? current;
      String? error;
      try {
        current = await _wifi.currentSsid(preferred: target);
        if (!currentRequest()) return;
        if (current == target) {
          final address = await _wifi.ipv4Address(target);
          if (!currentRequest()) return;
          if (address == null) {
            error = 'Wi-Fi 尚未获取 IPv4 地址。';
          } else {
            final status = await _probeGateway(address);
            if (!currentRequest()) return;
            if (status != null) {
              _applyStatus(status, wifiSsid: current);
              return;
            }
            error = _gatewayError;
          }
        }
      } on CampusWifiException catch (failure) {
        error = failure.message;
      }

      if (!currentRequest()) return;
      if (desktop) {
        final status = await _probeGateway(null);
        if (!currentRequest()) return;
        if (status != null) {
          _applyStatus(status, route: _DesktopRoute.system);
          return;
        }
      }

      _desktopRoute = wired != null && current != target
          ? _DesktopRoute.ethernet
          : null;
      _currentSsid = current;
      _setStatus(null, error: error ?? (wired != null ? _gatewayError : null));
    } catch (_) {
      if (currentRequest()) _setStatus(null, error: _gatewayError);
    } finally {
      if (currentRequest()) {
        _refreshing = false;
        notifyListeners();
      }
    }
  }

  Future<void> connectFlow(String chosenSsid) async {
    if (_disposed || !supported || busy) return;
    final target = desktop ? chosenSsid.trim() : AndroidCampusWifi.ssid;
    if (!WindowsWifi.isValidSsid(target)) {
      _connectError = '请输入有效的 Wi-Fi 名称（最多 32 字节）。';
      notifyListeners();
      return;
    }
    _generation++;
    _refreshing = false;
    _connectError = null;
    _setStatus(null);
    final detectWired = _wiredAddress;
    _updatePhase(
      detectWired == null
          ? CampusConnectPhase.wifi
          : CampusConnectPhase.checking,
    );
    try {
      if (desktop) _settings.setCampusWifiSsid(target);
      var address = await detectWired?.call();
      if (_disposed) return;
      SrunStatus? initial;
      _desktopRoute = address != null ? _DesktopRoute.ethernet : null;
      if (address != null) {
        _currentSsid = null;
        initial = await _probeGateway(address);
        if (_disposed) return;
      }
      if (initial == null && desktop) {
        final current = await _probeGateway(null);
        if (_disposed) return;
        if (current != null && current.online) {
          _applyStatus(current, route: _DesktopRoute.system);
          return;
        }
      }
      if (initial == null) {
        _desktopRoute = null;
        if (phase != CampusConnectPhase.wifi) {
          _updatePhase(CampusConnectPhase.wifi);
        }
        await _wifi.connect(target);
        if (_disposed) return;
        _updatePhase(CampusConnectPhase.checking);
        final timeout = Duration(seconds: desktop ? 8 : 15);
        address = await _waitForAddress(
          target,
          timeout,
        ).timeout(timeout, onTimeout: () => null);
        if (_disposed) return;
        if (address == null) {
          final current = await _wifi.currentSsid(preferred: target);
          if (_disposed) return;
          _currentSsid = current;
          _connectError = !desktop && !wifiConnected
              ? '请在 Android 系统设置中连接 NEU，并保持精确位置权限开启。'
              : 'Wi-Fi 尚未获取 IPv4 地址，请稍后重试。';
          return;
        }
        _currentSsid = target;
        _gateway.useSourceAddress(address);
        initial = await _gateway.status();
      }
      if (_disposed) return;
      _setStatus(initial);
      if (initial.online) return;

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
      await _gateway.login(
        username: username,
        password: password,
        clientIp: initial.clientIp ?? address,
      );
      if (_disposed) return;
      _updatePhase(CampusConnectPhase.confirming);
      var status = await _gateway.status();
      if (_disposed) return;
      if (!status.online) {
        await Future<void>.delayed(const Duration(milliseconds: 800));
        if (_disposed) return;
        status = await _gateway.status();
        if (_disposed) return;
      }
      _setStatus(status);
      if (!status.online) _connectError = '网关尚未确认上线，请刷新状态或重试。';
    } on CampusWifiException catch (error) {
      _connectError = error.message;
    } on SrunRejected catch (error) {
      _connectError = phase == CampusConnectPhase.login
          ? '网关登录失败。${error.message}'
          : '网关返回错误。${error.message}';
    } on SrunUnavailable {
      _connectError = _gatewayError;
      _setStatus(null);
    } on FormatException {
      _connectError = '学校网关返回了无法识别的响应，请确认已接入校园网。';
      _setStatus(null);
    } catch (_) {
      _connectError = switch (phase) {
        CampusConnectPhase.wifi => '无法连接 Wi-Fi，请在系统设置中检查无线网络。',
        CampusConnectPhase.login => '无法完成网关登录，请检查已保存的账号密码。',
        _ => _gatewayError,
      };
    } finally {
      if (!_disposed) _updatePhase(CampusConnectPhase.idle);
    }
  }

  static const _gatewayError = '无法访问学校网关，请确认已接入东北大学校园网。';

  Future<SrunStatus?> _probeGateway(String? address) async {
    _gateway.useSourceAddress(address);
    try {
      return await _gateway.status();
    } on SrunUnavailable {
      return null;
    } on FormatException {
      return null;
    }
  }

  void _applyStatus(
    SrunStatus status, {
    _DesktopRoute? route,
    String? wifiSsid,
  }) {
    _desktopRoute = route;
    _currentSsid = wifiSsid;
    _setStatus(status);
    if (status.online) _connectError = null;
  }

  Future<String?> _waitForAddress(String target, Duration timeout) async {
    final clock = Stopwatch()..start();
    while (!_disposed && clock.elapsed < timeout) {
      final address = await _wifi.ipv4Address(target);
      if (address != null) return address;
      await Future<void>.delayed(const Duration(milliseconds: 600));
    }
    return null;
  }

  void _setStatus(SrunStatus? status, {String? error}) {
    _status = status;
    _lastUpdated = status == null ? null : DateTime.now();
    _statusError = error;
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
