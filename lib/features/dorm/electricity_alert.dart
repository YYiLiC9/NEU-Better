import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:local_notifier/local_notifier.dart';

import '../../app/theme/app_theme.dart';
import '../../core/electricity/electricity_models.dart';

/// 通知渠道的抽象接口。
///
/// 用电提醒的“系统通知”部分被抽成可插拔渠道：调用方（[DormAlertPresenter]）
/// 只依赖该接口，具体用 Windows toast、桌面右下角应用内弹窗，还是别的实现，
/// 都由渠道自身决定。后续接入新的提醒方式时，只需新增一个实现，不必改动
/// [DormAlertPresenter] 的公开签名。
abstract class ElectricityAlertChannel {
  const ElectricityAlertChannel();

  /// 发出一次用电提醒通知。
  ///
  /// 返回值只表示“通知已尽力发出”，渠道内部应自行吞掉可恢复的错误，
  /// 不应向外抛出，以免影响随后必然出现的应用内弹窗兜底。
  Future<void> show({
    required ElectricityReading reading,
    required DormPrefs prefs,
    VoidCallback? onView,
  });
}

/// Windows 系统 toast 通知渠道（基于 local_notifier / WinToast）。
class WindowsToastChannel implements ElectricityAlertChannel {
  const WindowsToastChannel();

  @override
  Future<void> show({
    required ElectricityReading reading,
    required DormPrefs prefs,
    VoidCallback? onView,
  }) async {
    try {
      final notification = LocalNotification(
        title: '寝室电量不足',
        body:
            '${reading.roomInfo} · 剩余 ${reading.rawRemain}，低于提醒线'
            '（${prefs.alertThreshold.truncate()} 度）',
      );
      await notification.show().timeout(
        const Duration(seconds: 3),
        onTimeout: () {},
      );
    } catch (error) {
      debugPrint('[elec] toast channel failed: $error');
    }
  }
}

/// Android 系统悬浮通知（heads-up）渠道。
///
/// 通过原生 MethodChannel 桥 `neu_better/notifications` 调用 [MainActivity] 里的
/// `showElectricityAlert(title, body)`：原生侧用 IMPORTANCE_HIGH 的通知渠道 +
/// NotificationCompat(PRIORITY_HIGH / DEFAULT_ALL) 发出横幅悬浮通知。Android 13+
/// 的 POST_NOTIFICATIONS 运行时权限由原生侧在 onCreate 申请，Dart 侧无需处理。
class AndroidHeadsUpChannel implements ElectricityAlertChannel {
  const AndroidHeadsUpChannel();

  /// 与 [MainActivity] 中注册的 MethodChannel 名称保持一致。
  static const MethodChannel channel =
      MethodChannel('neu_better/notifications');

  @override
  Future<void> show({
    required ElectricityReading reading,
    required DormPrefs prefs,
    VoidCallback? onView,
  }) async {
    try {
      await channel.invokeMethod<bool>('showElectricityAlert', <String, String>{
        'title': '寝室电量不足',
        'body':
            '${reading.roomInfo}：剩余 ${reading.rawRemain}'
            '（低于提醒线 ${prefs.alertThreshold.truncate()} 度）',
      });
    } on MissingPluginException catch (error) {
      // 非 Android 引擎（如单测/桌面）没有该原生实现，忽略即可。
      debugPrint('[elec] android heads-up channel unavailable: $error');
    } on PlatformException catch (error) {
      debugPrint('[elec] android heads-up channel failed: $error');
    } catch (error) {
      debugPrint('[elec] android heads-up channel failed: $error');
    }
  }
}

/// 通知点击路由：用户点击系统「用电提醒」通知后，把应用带到「寝室用电」页。
///
/// 原生 [MainActivity] 在通知上挂了 PendingIntent（extra `openDorm=true`），点击后
/// 复用 MainActivity，并通过同一 MethodChannel `neu_better/notifications` 回调
/// `openDorm`。此处集中注册唯一的 MethodCallHandler（与 [AndroidHeadsUpChannel]
/// 共用同一通道名，避免重复设置 handler 互相覆盖），用 [openDormSignal] 通知界面。
class NotificationRouter {
  NotificationRouter._();

  /// 每次收到「打开寝室用电」请求时自增，界面侧监听即可切 tab。
  static final ValueNotifier<int> openDormSignal = ValueNotifier<int>(0);

  static bool _handlerInstalled = false;

  /// 安装 MethodChannel 回调（幂等，只装一次）。
  static void ensureHandlerInstalled() {
    if (_handlerInstalled) return;
    _handlerInstalled = true;
    AndroidHeadsUpChannel.channel.setMethodCallHandler((call) async {
      if (call.method == 'openDorm') {
        openDormSignal.value++;
      }
      return null;
    });
  }

  /// 冷启动兜底：应用因点击通知而被拉起时，`openDorm` 回调可能早于界面监听，
  /// 主动向原生查询是否有待处理的请求；有则触发一次路由信号。
  static Future<void> consumePending() async {
    try {
      final pending = await AndroidHeadsUpChannel.channel
          .invokeMethod<bool>('getPendingOpenDorm');
      if (pending == true) {
        openDormSignal.value++;
      }
    } catch (_) {
      // 非 Android 引擎无此实现（MissingPluginException 等），忽略。
    }
  }
}

/// 预留：桌面右下角应用内弹窗渠道（当前为占位实现，no-op + 记日志）。
///
/// 设计意图：在不依赖系统通知中心、或以应用内浮层为主的场景下，由 Flutter
/// 侧在窗口右下角绘制一个轻量提醒卡片。当前仅保留接口与参数，不实际绘制。
class DesktopCornerPopupChannel implements ElectricityAlertChannel {
  const DesktopCornerPopupChannel();

  /// 预留：弹窗在屏幕上的停留时长。
  static const Duration dwell = Duration(seconds: 6);

  /// 预留：弹窗距屏幕右下角的边距。
  static const EdgeInsets margin = EdgeInsets.all(24);

  /// 预留：入场/退场动画时长。
  static const Duration animation = Duration(milliseconds: 200);

  @override
  Future<void> show({
    required ElectricityReading reading,
    required DormPrefs prefs,
    VoidCallback? onView,
  }) async {
    // 占位：暂不绘制弹窗，仅记录，便于后续接入。
    debugPrint(
      '[elec] desktop-corner popup channel reserved (no-op): '
      '${reading.roomInfo}',
    );
  }
}

/// 寝室电量提醒的唯一出口：系统通知 + 应用内弹窗。
///
/// 每日检查和“测试通知”按钮都走这里，保证两条路径完全一致。
abstract final class DormAlertPresenter {
  /// 可选的通知渠道覆盖。为空时按平台自动选择：
  /// Windows 用 [WindowsToastChannel]，Android 用 [AndroidHeadsUpChannel]，
  /// 其余平台用占位的 [DesktopCornerPopupChannel]。预留给未来“设置里切换通知
  /// 方式”等配置。
  static ElectricityAlertChannel? channelOverride;

  /// 依据平台 / 配置选择通知渠道。
  static ElectricityAlertChannel selectChannel() {
    final override = channelOverride;
    if (override != null) {
      return override;
    }
    if (Platform.isWindows) {
      return const WindowsToastChannel();
    }
    if (Platform.isAndroid) {
      return const AndroidHeadsUpChannel();
    }
    return const DesktopCornerPopupChannel();
  }

  static Future<void> present(
    BuildContext context, {
    required ElectricityReading reading,
    required DormPrefs prefs,
    VoidCallback? onView,
  }) async {
    // 先尝试系统通知渠道（可插拔）；渠道内部自行兜底，不抛出。
    await selectChannel().show(reading: reading, prefs: prefs, onView: onView);

    // 应用内弹窗始终作为兜底保留。
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: AppColors.line),
        ),
        title: Row(
          children: [
            Icon(Icons.bolt_rounded, size: 22, color: AppColors.nowRed),
            const SizedBox(width: 8),
            Text(
              '寝室电量不足',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AppColors.ink,
              ),
            ),
          ],
        ),
        content: Text(
          '${reading.roomInfo}\n剩余 ${reading.rawRemain}，'
          '已低于提醒线 ${prefs.alertThreshold.truncate()} 度，建议尽快充值。',
          style: TextStyle(
            fontSize: 12,
            height: 1.6,
            color: AppColors.muted,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('知道了'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.campusBlue,
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              Navigator.of(dialogContext).pop();
              onView?.call();
            },
            child: const Text('查看电量'),
          ),
        ],
      ),
    );
  }
}
