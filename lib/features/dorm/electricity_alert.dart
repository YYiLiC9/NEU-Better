import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:local_notifier/local_notifier.dart';

import '../../app/theme/app_theme.dart';
import 'electricity_models.dart';

/// 寝室电量提醒的唯一出口：系统通知 + 应用内弹窗。
///
/// 每日检查和“测试通知”按钮都走这里，保证两条路径完全一致。
abstract final class DormAlertPresenter {
  static Future<void> present(
    BuildContext context, {
    required ElectricityReading reading,
    required DormPrefs prefs,
    VoidCallback? onView,
  }) async {
    if (Platform.isWindows) {
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
        debugPrint('[elec] notification failed: $error');
      }
    }
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
