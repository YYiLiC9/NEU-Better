import 'dart:io';

import 'package:flutter/services.dart';

/// 安装下载好的更新包。
///
/// - Android：交给系统安装器（FileProvider 授权读 apk）。
/// - Windows：因运行中 exe 无法被覆盖，改由一个脱离的批处理在进程退出后
///   解压并覆盖安装目录，再重新启动程序。
abstract final class UpdateInstaller {
  static const MethodChannel _channel = MethodChannel('neu_better/updater');

  static Future<String> installAndroid(File apk) async {
    try {
      final result = await _channel.invokeMethod<String>('installApk', {
        'path': apk.path,
      });
      return result ?? 'ok';
    } on PlatformException catch (error) {
      if (error.code == 'need_permission') return 'need_permission';
      return 'error: ${error.message}';
    } catch (error) {
      return 'error: $error';
    }
  }

  /// 当前是否已被允许「安装未知来源应用」。
  static Future<bool> canInstallPackages() async {
    if (!Platform.isAndroid) return true;
    try {
      final result = await _channel.invokeMethod<bool>('canInstallPackages');
      return result ?? false;
    } catch (_) {
      return false;
    }
  }

  /// 跳转系统「安装未知应用」授权页。
  static Future<void> openInstallPermission() async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod<void>('openInstallPermission');
    } catch (_) {}
  }

  static Future<void> applyWindows(File package) async {
    final exe = File(Platform.resolvedExecutable);
    final installDir = exe.parent.path;
    final temp = Directory.systemTemp.createTempSync('neubetter_upd_');
    final bat = File('${temp.path}\\apply_update.bat');

    final bool isSetup = package.path.toLowerCase().endsWith('.exe');
    final List<String> script;
    if (isSetup) {
      // 新版安装程序：静默安装到当前安装目录（保留用户选择的位置），再启动。
      script = <String>[
        '@echo off',
        'timeout /t 2 /nobreak >nul',
        'start "" /wait "${package.path}" /VERYSILENT /SUPPRESSMSGBOXES '
            '/NORESTART /SP- /CLOSEAPPLICATIONS /DIR="$installDir"',
        'start "" "${exe.path}"',
        'exit',
      ];
    } else {
      // 旧版 zip：等本进程退出 → 解压 → 覆盖安装目录 → 重新启动。
      final extractDir = '${temp.path}\\extract';
      script = <String>[
        '@echo off',
        'timeout /t 2 /nobreak >nul',
        'powershell -NoProfile -ExecutionPolicy Bypass -Command "Expand-Archive '
            "-LiteralPath '${package.path}' -DestinationPath '$extractDir' -Force\"",
        'powershell -NoProfile -ExecutionPolicy Bypass -Command "\$src = '
            "Get-ChildItem -Path '$extractDir' -Recurse -Filter "
            "*.exe | Select-Object -First 1; if (\$src) { Copy-Item "
            "-Path (Join-Path \$src.DirectoryName '*') -Destination '$installDir' "
            '-Recurse -Force }"',
        'start "" "${exe.path}"',
        'exit',
      ];
    }
    bat.writeAsStringSync(script.join('\r\n'));

    await Process.start(
      'cmd',
      <String>['/c', bat.path],
      mode: ProcessStartMode.detached,
    );
    // 让出控制权后立即退出，批处理会在 exe 释放后完成替换并重启。
    exit(0);
  }
}
