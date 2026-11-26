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

  /// 安卓「已下载待安装」的包：用户在系统授权页允许安装后回到 App 时，
  /// 由 [onAppResumed] 自动继续拉起安装器。
  File? pendingInstall;

  /// 本次会话是否已经弹过「下载完成」提醒，避免重复打扰。
  bool promptedReady = false;

  bool get hasUpdate => info != null;

  /// 已下载的部分字节数（用于「下载未完成」提示）。
  int get partialBytes {
    final current = info;
    if (current == null) return 0;
    try {
      final file = UpdateInfo.packageFile(
        current.version,
        android: Platform.isAndroid,
        windowsFileName: current.windowsFileName,
      );
      return file.existsSync() ? file.lengthSync() : 0;
    } catch (_) {
      return 0;
    }
  }

  void clearError() {
    if (error == null) return;
    error = null;
    notifyListeners();
  }

  void _log(String message) {
    debugPrint('[update] $message');
    try {
      final sep = Platform.pathSeparator;
      final base = Platform.environment['LOCALAPPDATA'];
      if (base == null || base.isEmpty) return;
      final dir = Directory('$base${sep}NEU Better');
      if (!dir.existsSync()) dir.createSync(recursive: true);
      final file = File('${dir.path}${sep}update.log');
      file.writeAsStringSync(
        '${DateTime.now().toIso8601String()} $message\n',
        mode: FileMode.append,
        flush: true,
      );
    } catch (_) {}
  }

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
    final installMode = Platform.isWindows
        ? (UpdateInstaller.isSetupInstalled ? 'setup' : 'portable')
        : 'android';
    _log('check start mode=$installMode');
    info = await _service.check(
      preferWindowsSetup: UpdateInstaller.isSetupInstalled,
    );
    readyFile = null;
    final current = info;
    if (current != null && _downloadUrl != null) {
      final file = UpdateInfo.packageFile(
        current.version,
        android: Platform.isAndroid,
        windowsFileName: current.windowsFileName,
      );
      if (UpdateInfo.isCompletePackage(file, _expectedSize)) {
        readyFile = file;
      }
    }
    _log(
      'check result version=${current?.version} windowsFile=${current?.windowsFileName} ready=${readyFile?.path}',
    );
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
      windowsFileName: current.windowsFileName,
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
      _log('download start ${_downloadUrl!} -> ${target.path}');
      await _service.download(
        _downloadUrl!,
        target,
        expectedSize: _expectedSize,
        onProgress: (received, total) {
          if (total > 0) {
            progress = received / total;
            notifyListeners();
          }
        },
      );
      if (UpdateInfo.isCompletePackage(target, _expectedSize)) {
        readyFile = target;
        _log('download complete ${target.path}');
      } else {
        error = '安装包下载不完整';
        _log('download incomplete ${target.path} bytes=$partialBytes');
      }
    } catch (e) {
      error = '$e';
      _log('download failed bytes=$partialBytes error=$e');
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
      final status = await UpdateInstaller.installAndroid(file);
      if (status == 'need_permission') {
        // 记录待安装包；用户去系统设置授权后回到 App 会自动继续安装。
        pendingInstall = file;
      } else if (status == 'ok') {
        pendingInstall = null;
      }
      return status;
    }
    if (Platform.isWindows) {
      await UpdateInstaller.applyWindows(file);
      return 'ok';
    }
    return 'error';
  }

  /// App 回到前台时调用：若存在待安装包且已获得安装权限，则自动继续安装。
  Future<void> onAppResumed() async {
    final file = pendingInstall;
    if (file == null || !Platform.isAndroid) return;
    if (!await UpdateInstaller.canInstallPackages()) return;
    final status = await UpdateInstaller.installAndroid(file);
    if (status == 'ok') {
      pendingInstall = null;
    } else if (status == 'need_permission') {
      pendingInstall = file;
    }
    notifyListeners();
  }
}
