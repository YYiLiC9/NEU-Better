import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// 用系统默认浏览器打开外部链接（不使用内嵌 WebView）。
class ExternalUrl {
  const ExternalUrl._();

  static const MethodChannel _channel = MethodChannel('neu_better/notifications');

  static Future<void> open(String url) async {
    if (url.trim().isEmpty) return;
    if (kIsWeb) return;
    try {
      if (Platform.isWindows) {
        await Process.start(
          'cmd',
          <String>['/c', 'start', '', url],
          mode: ProcessStartMode.detached,
        );
        return;
      }
      if (Platform.isAndroid) {
        await _channel.invokeMethod<bool>('openUrl', <String, dynamic>{
          'url': url,
        });
        return;
      }
    } catch (error) {
      debugPrint('[url] open failed: $error');
    }
  }
}
