import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/network/notification_client.dart';
import 'notification_dispatch.dart';
import 'notification_models.dart';
import 'notification_store.dart';

/// 前台/托盘轮询：按固定间隔拉取未读统计与最新列表，出现新增未读时发系统通知。
///
/// 说明：Android 后台常驻轮询本期未实现（AlarmManager 成本/风险较高），
/// 仅在进程存活（前台或托盘）时轮询。详见任务回报的“已知限制”。
class NotificationPoller {
  NotificationPoller({
    required this.client,
    required this.store,
    required this.notifyEnabled,
    this.isCurrent,
    this.interval = const Duration(seconds: 90),
    Future<void> Function(String title, String body)? notifier,
  }) : _notifier = notifier ?? SystemNotification.show;

  final NotificationClient client;
  final NotificationStore store;
  final bool Function(String sourceKey) notifyEnabled;
  final Future<void> Function(String title, String body) _notifier;
  final Duration interval;
  final bool Function()? isCurrent;

  bool get _active => isCurrent?.call() != false;

  Timer? _timer;
  bool _busy = false;

  bool get isRunning => _timer != null;

  /// 立即检查一次。返回本次是否发出了系统通知。
  Future<bool> checkOnce() async {
    if (_busy || !_active) return false;
    _busy = true;
    try {
      if (!notifyEnabled('campus')) {
        // 关闭来源时仍同步 baseline，避免重新打开后一次涌入历史未读。
        final counts = await client.counts();
        if (!_active) return false;
        store.setBaseline(counts.noRead);
        await store.save();
        return false;
      }
      final counts = await client.counts();
      if (!_active) return false;
      if (counts.noRead <= store.lastNoRead) {
        store.setBaseline(counts.noRead);
        await store.save();
        return false;
      }
      final items = await client.list(page: 1);
      if (!_active) return false;
      final unread = items.where((item) => !item.read).toList(growable: false);
      final freshIds = store.takeNewUnnotified(unread.map((e) => e.logId));
      final fresh = <AppNotification>[
        for (final id in freshIds)
          for (final item in unread)
            if (item.logId == id) item,
      ];
      store.setBaseline(counts.noRead);
      await store.save();
      if (fresh.isEmpty || !_active) return false;
      final latest = fresh.take(2).toList(growable: false);
      final title = latest.length == 1
          ? '新通知：${latest.first.title}'
          : '你有 ${counts.noRead} 条未读通知';
      final body = latest.length == 1
          ? (latest.first.preview.isEmpty ? '点开查看详情' : latest.first.preview)
          : latest.map((e) => '· ${e.title}').join('\n');
      await _notifier(title, body);
      return true;
    } catch (error) {
      debugPrint('[notify] poll failed: $error');
      return false;
    } finally {
      _busy = false;
    }
  }

  void startForegroundPolling() {
    if (_timer != null) return;
    // 启动后先跑一次，之后按固定间隔。
    unawaited(checkOnce());
    _timer = Timer.periodic(interval, (_) {
      unawaited(checkOnce());
    });
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }
}
