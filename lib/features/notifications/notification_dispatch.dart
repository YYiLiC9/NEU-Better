import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:local_notifier/local_notifier.dart';

/// 系统通知派发（Windows：local_notifier；Android：原生渠道 plugin_notify_v1）。
///
/// 所有异常都在内部吞掉并记日志：系统通知失败不应影响业务主流程。
abstract final class SystemNotification {
  static const MethodChannel _channel = MethodChannel('neu_better/notifications');

  static Future<void> show(String title, String body) async {
    if (Platform.isWindows) {
      try {
        final notification = LocalNotification(title: title, body: body);
        await notification.show().timeout(
          const Duration(seconds: 3),
          onTimeout: () {},
        );
      } catch (error) {
        debugPrint('[notify] windows system notification failed: $error');
      }
      return;
    }
    if (Platform.isAndroid) {
      try {
        await _channel.invokeMethod<bool>('showPluginNotification', {
          'title': title,
          'body': body,
        });
      } on MissingPluginException catch (error) {
        debugPrint('[notify] android channel unavailable: $error');
      } on PlatformException catch (error) {
        debugPrint('[notify] android system notification failed: $error');
      } catch (error) {
        debugPrint('[notify] android system notification failed: $error');
      }
      return;
    }
    debugPrint('[notify] system notification not supported on this platform');
  }
}
