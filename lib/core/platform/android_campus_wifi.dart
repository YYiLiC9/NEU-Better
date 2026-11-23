import 'package:flutter/services.dart';

import '../network/srun_portal_client.dart';
import 'campus_wifi.dart';

class AndroidCampusWifi implements CampusWifi {
  const AndroidCampusWifi();

  static const _channel = MethodChannel('neu_better/campus_wifi');

  static bool isCampusSsid(String? ssid) => const {
    'neu',
    'neu-mobile',
    'neu2.4g',
  }.contains(ssid?.trim().toLowerCase().replaceAll('－', '-'));

  @override
  Future<String?> currentSsid() => _invoke<String>('currentSsid');

  @override
  Future<String?> ipv4Address(String ssid) =>
      _invoke<String>('ipv4Address', ssid);

  Future<void> requestLocationPermission() =>
      _invoke<void>('requestLocationPermission');

  Future<String> readGateway(Uri uri) async {
    try {
      final body = await _channel.invokeMethod<String>(
        'readGateway',
        uri.toString(),
      );
      if (body != null) return body;
    } on PlatformException catch (error) {
      if (error.code == 'gateway_http_error') {
        throw const SrunRejected('学校网关返回了 HTTP 错误。');
      }
      // Suppress transport diagnostics that may contain the signed URL.
    } on MissingPluginException {
      // The platform bridge is unavailable.
    }
    throw const SrunUnavailable();
  }

  Future<T?> _invoke<T>(String method, [String? argument]) async {
    try {
      return await _channel.invokeMethod<T>(method, argument);
    } on PlatformException catch (error) {
      if (error.code == 'location_required') {
        throw const CampusWifiPermissionRequired('请允许精确位置权限，以识别当前 Wi-Fi。');
      }
      throw CampusWifiException(error.message ?? '无法读取 Android Wi-Fi 状态。');
    } on MissingPluginException {
      throw const CampusWifiException('Android Wi-Fi 服务暂不可用。');
    }
  }
}
