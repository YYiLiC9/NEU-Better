import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import 'update_manager.dart';
import 'update_service.dart';

/// 检查更新并（可选）走下载安装流程。
///
/// [manual] 为 true 表示用户主动点「检查更新」，此时即使已是最新也会提示；
/// 启动时的自动检查传 false，静默返回。
Future<void> checkForUpdates(BuildContext context, {bool manual = false}) async {
  final manager = UpdateManager.instance;
  final info = await manager.check();
  if (!context.mounted) return;
  if (info == null) {
    if (manual) {
      ScaffoldMessenger.maybeOf(
        context,
      )?.showSnackBar(const SnackBar(content: Text('当前已是最新版本')));
    }
    return;
  }
  await showUpdateAvailableDialog(context);
}

/// 有新版本时的对话框：立即更新 / 后台下载 / 稍后。
Future<void> showUpdateAvailableDialog(BuildContext context) async {
  final manager = UpdateManager.instance;
  final info = manager.info;
  if (info == null) return;
  final hasReady = manager.readyFile != null;
  final hasUrl = Platform.isAndroid
      ? info.androidUrl != null
      : (Platform.isWindows && info.windowsUrl != null);

  final choice = await showDialog<String>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text('发现新版本 ${info.tagName}'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '当前版本 ${UpdateService.currentVersion}  →  最新 ${info.version}',
              style: const TextStyle(fontSize: 13),
            ),
            if (hasReady) ...[
              const SizedBox(height: 10),
              const Text(
                '安装包已下载完成，可直接安装。',
                style: TextStyle(fontSize: 12),
              ),
            ],
            if (info.notes.isNotEmpty) ...[
              const SizedBox(height: 12),
              const Text(
                '更新说明',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 4),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 180),
                child: Text(
                  info.notes,
                  style: const TextStyle(fontSize: 12, height: 1.5),
                ),
              ),
            ],
            if (!hasUrl) ...[
              const SizedBox(height: 12),
              const Text(
                '该版本未提供适用于当前系统的安装包，可前往 GitHub 发布页手动下载。',
                style: TextStyle(fontSize: 12),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop('later'),
          child: const Text('稍后'),
        ),
        if (hasUrl && !hasReady)
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop('background'),
            child: const Text('后台下载'),
          ),
        FilledButton(
          onPressed: hasUrl
              ? () => Navigator.of(dialogContext).pop('now')
              : null,
          child: const Text('立即更新'),
        ),
      ],
    ),
  );

  if (!context.mounted) return;
  if (choice == 'background') {
    unawaited(manager.ensureDownloaded(background: true));
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      const SnackBar(content: Text('已开始后台下载，完成后会提醒你更新')),
    );
    return;
  }
  if (choice != 'now') return;
  if (manager.readyFile == null) {
    await _downloadForeground(context);
    if (!context.mounted) return;
    if (manager.readyFile == null) {
      if (manager.error != null) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(content: Text('下载失败：${manager.error}')),
        );
      }
      return;
    }
  }
  await _install(context);
}

/// 下载完成后（前台）的提醒：「立即更新 / 下次重启更新」。
Future<void> showUpdateReadyDialog(BuildContext context) async {
  final manager = UpdateManager.instance;
  final version = manager.info?.tagName ?? '';
  final choice = await showDialog<String>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('更新已下载完成'),
      content: Text('新版本 $version 安装包已就绪，是否立即更新？'),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop('later'),
          child: const Text('下次重启更新'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop('now'),
          child: const Text('立即更新'),
        ),
      ],
    ),
  );
  if (!context.mounted) return;
  if (choice == 'now') {
    await _install(context);
  }
}

Future<void> _downloadForeground(BuildContext context) async {
  final manager = UpdateManager.instance;
  final navigator = Navigator.of(context, rootNavigator: true);
  var closed = false;
  void close() {
    if (!closed && navigator.canPop()) {
      closed = true;
      navigator.pop();
    }
  }

  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => AlertDialog(
      title: const Text('正在下载更新…'),
      content: AnimatedBuilder(
        animation: manager,
        builder: (_, _) {
          final value = manager.progress;
          if (manager.readyFile != null && manager.downloading == false) {
            WidgetsBinding.instance.addPostFrameCallback((_) => close());
          }
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              LinearProgressIndicator(value: value > 0 ? value : null),
              const SizedBox(height: 10),
              Text(
                value > 0 ? '${(value * 100).toStringAsFixed(0)}%' : '连接中…',
                style: const TextStyle(fontSize: 12),
              ),
            ],
          );
        },
      ),
    ),
  );
  await manager.ensureDownloaded();
  close();
}

Future<void> _install(BuildContext context) async {
  final manager = UpdateManager.instance;
  final status = await manager.install();
  if (!context.mounted) return;
  if (status == 'ok') return;
  if (status == 'need_permission') {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('需要允许安装应用'),
        content: const Text('请在系统设置中允许「NEU Better」安装未知应用，然后返回重试。'),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('知道了'),
          ),
        ],
      ),
    );
    return;
  }
  ScaffoldMessenger.maybeOf(
    context,
  )?.showSnackBar(SnackBar(content: Text('更新失败：$status')));
}
