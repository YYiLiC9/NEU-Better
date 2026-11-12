import 'dart:io';

import 'package:flutter/material.dart';

import 'update_installer.dart';
import 'update_service.dart';

/// 检查更新并（可选）走下载安装流程。
///
/// [manual] 为 true 表示用户主动点「检查更新」，此时即使已是最新也会提示；
/// 启动时的自动检查传 false，静默返回。
Future<void> checkForUpdates(BuildContext context, {bool manual = false}) async {
  final service = UpdateService();
  final info = await service.check();
  if (!context.mounted) return;

  if (info == null) {
    if (manual) {
      ScaffoldMessenger.maybeOf(
        context,
      )?.showSnackBar(const SnackBar(content: Text('当前已是最新版本')));
    }
    return;
  }
  await _showAvailable(context, service, info);
}

Future<void> _showAvailable(
  BuildContext context,
  UpdateService service,
  UpdateInfo info,
) async {
  final url = _downloadUrlFor(info);
  final update = await showDialog<bool>(
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
            if (url == null) ...[
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
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('稍后'),
        ),
        FilledButton(
          onPressed: url == null
              ? null
              : () => Navigator.of(dialogContext).pop(true),
          child: const Text('立即更新'),
        ),
      ],
    ),
  );

  if (update != true || url == null || !context.mounted) return;
  await _downloadAndInstall(context, service, info, url);
}

String? _downloadUrlFor(UpdateInfo info) {
  if (Platform.isAndroid) return info.androidUrl;
  if (Platform.isWindows) return info.windowsUrl;
  return null;
}

Future<void> _downloadAndInstall(
  BuildContext context,
  UpdateService service,
  UpdateInfo info,
  String url,
) async {
  final navigator = Navigator.of(context, rootNavigator: true);
  final progress = ValueNotifier<double>(0);
  final isAndroid = Platform.isAndroid;
  final target = File(
    '${Directory.systemTemp.path}${Platform.pathSeparator}'
    'neu_better_update.${isAndroid ? 'apk' : 'zip'}',
  );

  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => AlertDialog(
      title: const Text('正在下载更新…'),
      content: ValueListenableBuilder<double>(
        valueListenable: progress,
        builder: (_, value, _) => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            LinearProgressIndicator(value: value > 0 ? value : null),
            const SizedBox(height: 10),
            Text(
              value > 0 ? '${(value * 100).toStringAsFixed(0)}%' : '连接中…',
              style: const TextStyle(fontSize: 12),
            ),
          ],
        ),
      ),
    ),
  );

  try {
    await service.download(
      url,
      target,
      onProgress: (received, total) {
        if (total > 0) progress.value = received / total;
      },
    );
    if (navigator.canPop()) navigator.pop();
    if (isAndroid) {
      await UpdateInstaller.installAndroid(target);
    } else {
      await UpdateInstaller.applyWindows(target);
    }
  } catch (error) {
    if (navigator.canPop()) navigator.pop();
    if (context.mounted) {
      ScaffoldMessenger.maybeOf(
        context,
      )?.showSnackBar(SnackBar(content: Text('更新失败：$error')));
    }
  } finally {
    progress.dispose();
  }
}
