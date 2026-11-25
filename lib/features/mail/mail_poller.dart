import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/network/mail_client.dart';
import 'mail_poll_state.dart';

/// 邮件新邮件轮询：仅在 App 进程存活期间（前台 / Windows 托盘）由
/// [Timer.periodic] 调用 [checkOnce]，**不做后台任务、不做应用被杀后的推送**。
///
/// 规则：
/// - 首次检查（`initialized == false`）只记录现有邮件 id 作为基线，不发通知；
/// - 之后发现「未读且此前未见过」的邮件才发通知，同一封只通知一次；
/// - fetch 失败保持基线不动，下次再试；
/// - [enabled] 为 false（设置里关闭邮件通知）时不 fetch、不通知。
class MailPoller {
  MailPoller({
    required this.fetch,
    required this.notify,
    required this.state,
    this.enabled,
    this.now = DateTime.now,
    this.interval = const Duration(minutes: 3),
  });

  /// 拉取邮件列表（通常为最新 N 封）。
  final Future<List<MailSummary>> Function() fetch;

  /// 发出系统通知（标题、正文）。
  final void Function(String title, String body) notify;

  /// 持久化状态（基线 / 已知 id / 上次检查时间）。
  final MailPollState state;

  /// 是否允许轮询；为空表示始终允许。
  final bool Function()? enabled;

  /// 当前时间注入（便于测试）。
  final DateTime Function() now;

  /// 轮询周期，默认 3 分钟。
  final Duration interval;

  Timer? _timer;
  bool _busy = false;

  bool get isRunning => _timer != null;

  /// 启动定时轮询（幂等）。首次检查由调用方在加载状态后显式触发。
  void start() {
    if (_timer != null) return;
    _timer = Timer.periodic(interval, (_) {
      unawaited(checkOnce());
    });
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  /// 立即检查一次。
  Future<void> checkOnce() async {
    final isEnabled = enabled;
    if (isEnabled != null && !isEnabled()) return;
    if (_busy) return;
    _busy = true;
    try {
      List<MailSummary> fetched;
      try {
        fetched = await fetch();
      } catch (error) {
        // fetch 失败：不更新基线，避免把「拉取失败」误判为「邮件全没了」。
        debugPrint('[mail] poll fetch failed: $error');
        return;
      }
      if (isEnabled != null && !isEnabled()) return;
      state.setLastCheckAt(now());

      if (!state.initialized) {
        // 首次：只建立基线，不通知旧邮件。
        state.setBaseline(fetched.map((m) => m.id));
        await state.save();
        return;
      }

      final known = state.knownIds;
      final fresh = <MailSummary>[
        for (final item in fetched)
          if (!item.read && !known.contains(item.id)) item,
      ];

      // 无论是否有新邮件，都把本次见过的 id 记入 knownIds（避免下次重复判断）。
      state.takeNew(fetched.map((m) => m.id));
      await state.save();

      if (fresh.isEmpty || isEnabled?.call() == false) return;

      final String title;
      final String body;
      if (fresh.length == 1) {
        final one = fresh.first;
        title = '新邮件 · ${one.from.isEmpty ? '未知发件人' : one.from}';
        body = one.subject.isEmpty ? '(无主题)' : one.subject;
      } else {
        title = '你有 ${fresh.length} 封新邮件';
        body = fresh
            .take(3)
            .map((m) => '· ${m.subject.isEmpty ? '(无主题)' : m.subject}')
            .join('\n');
      }
      notify(title, body);
    } finally {
      _busy = false;
    }
  }
}
