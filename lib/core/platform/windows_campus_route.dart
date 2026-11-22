import 'dart:io';

import 'package:flutter/services.dart';

import '../network/srun_portal_client.dart';

class WindowsCampusRoute {
  const WindowsCampusRoute();

  static const _channel = MethodChannel('neu_better/window');

  Future<String?> wiredAddress() async {
    if (!Platform.isWindows) return null;
    try {
      final addresses = await InternetAddress.lookup(
        SrunPortalClient.host,
        type: InternetAddressType.IPv4,
      ).timeout(const Duration(seconds: 3));
      if (addresses.isEmpty) return null;
      return await _channel.invokeMethod<String>(
        'campusWiredAddress',
        addresses.first.address,
      );
    } on Exception {
      return null;
    }
  }
}
