import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:local_notifier/local_notifier.dart';

/// 系统通知派发（Windows：local_notifier；Android：原生渠道 plugin_notify_v1）。
///
/// 所有异常都在内部吞掉并记日志：系统通知失败不应影响业务主流程。
abstract final class SystemNotification {
  static const MethodChannel _channel = MethodChannel('neu_better/notifications');

  /// [route] 仅 Android 下生效：随通知带给原生层，点击时用于决定跳转页面
  /// （如 'mail' 打开邮件页）；Windows 的 local_notifier 暂不支持点击跳转，忽略。
  static Future<void> show(String title, String body, {String? route}) async {
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
          'route': ?route,
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

/// Android「校园通知」后台轮询（15 分钟闹钟）配置：同步 personal cookie 与基线。
abstract final class NotificationBackground {
  static const MethodChannel _channel = MethodChannel('neu_better/notifications');

  static Future<void> sync({
    required bool enabled,
    required String? cookie,
    int last = 0,
  }) async {
    if (!Platform.isAndroid) return;
    try {
      if (enabled && (cookie ?? '').isNotEmpty) {
        await _channel.invokeMethod<bool>('setBackgroundNotify', {
          'cookie': cookie,
          'last': last,
        });
      } else {
        await _channel.invokeMethod<bool>('disableBackgroundNotify');
      }
    } on MissingPluginException catch (error) {
      debugPrint('[notify] background channel unavailable: $error');
    } catch (error) {
      debugPrint('[notify] background sync failed: $error');
    }
  }
}
