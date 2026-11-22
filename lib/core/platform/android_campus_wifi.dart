import 'package:flutter/services.dart';

import '../network/srun_portal_client.dart';
import 'campus_wifi.dart';

class AndroidCampusWifi implements CampusWifi {
  const AndroidCampusWifi();

  static const _channel = MethodChannel('neu_better/campus_wifi');
  static const ssid = 'NEU';

  @override
  Future<String?> currentSsid({String? preferred}) =>
      _invoke<String>('currentSsid');

  @override
  Future<String?> ipv4Address(String ssid) => _invoke<String>('ipv4Address');

  @override
  Future<void> connect(String ssid) => _invoke<void>('connect');

  Future<String> readGateway(Uri uri) async {
    try {
      final body = await _channel.invokeMethod<String>(
        'readGateway',
        uri.toString(),
      );
      if (body != null) return body;
    } on PlatformException {
      // Suppress transport diagnostics that may contain the signed URL.
    } on MissingPluginException {
      // The platform bridge is unavailable.
    }
    throw const SrunUnavailable();
  }

  Future<T?> _invoke<T>(String method) async {
    try {
      return await _channel.invokeMethod<T>(method);
    } on PlatformException catch (error) {
      throw CampusWifiException(error.message ?? '无法读取 Android Wi-Fi 状态。');
    } on MissingPluginException {
      throw const CampusWifiException('Android Wi-Fi 服务暂不可用。');
    }
  }
}
