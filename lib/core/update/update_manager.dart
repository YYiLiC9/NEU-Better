import 'dart:io';

import 'package:flutter/foundation.dart';

import 'update_installer.dart';
import 'update_service.dart';

/// 全局更新状态机：检查、后台下载、复用已下载安装包、安装。
///
/// 下载不绑定任何对话框，界面关闭后仍在后台继续；下载完成后由根组件在
/// 应用处于前台时弹窗提醒「立即更新 / 下次重启更新」。
class UpdateManager extends ChangeNotifier {
  UpdateManager._();

  static final UpdateManager instance = UpdateManager._();

  final UpdateService _service = UpdateService();

  UpdateInfo? info;
  File? readyFile;
  bool downloading = false;
  bool background = false;
  double progress = 0;
  String? error;

  /// 本次会话是否已经弹过「下载完成」提醒，避免重复打扰。
  bool promptedReady = false;

  bool get hasUpdate => info != null;

  String? get _downloadUrl {
    final current = info;
    if (current == null) return null;
    if (Platform.isAndroid) return current.androidUrl;
    if (Platform.isWindows) return current.windowsUrl;
    return null;
  }

  int? get _expectedSize {
    final current = info;
    if (current == null) return null;
    if (Platform.isAndroid) return current.androidSize;
    if (Platform.isWindows) return current.windowsSize;
    return null;
  }

  /// 检查是否有新版本，并顺带探测本地是否已有完整安装包可直接复用。
  Future<UpdateInfo?> check() async {
    info = await _service.check();
    readyFile = null;
    final current = info;
    if (current != null && _downloadUrl != null) {
      final file = UpdateInfo.packageFile(
        current.version,
        android: Platform.isAndroid,
      );
      if (UpdateInfo.isCompletePackage(file, _expectedSize)) {
        readyFile = file;
      }
    }
    notifyListeners();
    return info;
  }

  /// 直接复用已下载的完整安装包；若没有则下载。
  Future<void> ensureDownloaded({bool background = false}) async {
    final current = info;
    if (current == null || _downloadUrl == null) return;
    final target = UpdateInfo.packageFile(
      current.version,
      android: Platform.isAndroid,
    );
    if (UpdateInfo.isCompletePackage(target, _expectedSize)) {
      readyFile = target;
      notifyListeners();
      return;
    }
    downloading = true;
    this.background = background;
    progress = 0;
    error = null;
    notifyListeners();
    try {
      await _service.download(
        _downloadUrl!,
        target,
        onProgress: (received, total) {
          if (total > 0) {
            progress = received / total;
            notifyListeners();
          }
        },
      );
      if (UpdateInfo.isCompletePackage(target, _expectedSize)) {
        readyFile = target;
      } else {
        error = '安装包下载不完整';
      }
    } catch (e) {
      error = '$e';
    } finally {
      downloading = false;
      notifyListeners();
    }
  }

  /// 安装已下载的包。返回 'ok' / 'need_permission' / 'error'。
  Future<String> install() async {
    final file = readyFile;
    if (file == null) return 'error';
    if (Platform.isAndroid) {
      return UpdateInstaller.installAndroid(file);
    }
    if (Platform.isWindows) {
      await UpdateInstaller.applyWindows(file);
      return 'ok';
    }
    return 'error';
  }
}
