import 'dart:io';

import 'package:flutter/services.dart';

/// 安装下载好的更新包。
///
/// - Android：交给系统安装器（FileProvider 授权读 apk）。
/// - Windows：因运行中 exe 无法被覆盖，改由一个脱离的批处理在进程退出后
///   解压并覆盖安装目录，再重新启动程序。
abstract final class UpdateInstaller {
  static const MethodChannel _channel = MethodChannel('neu_better/updater');

  static Future<void> installAndroid(File apk) async {
    await _channel.invokeMethod<void>('installApk', {'path': apk.path});
  }

  static Future<void> applyWindows(File zip) async {
    final exe = File(Platform.resolvedExecutable);
    final installDir = exe.parent.path;
    final temp = Directory.systemTemp.createTempSync('neubetter_upd_');
    final extractDir = '${temp.path}\\extract';
    final bat = File('${temp.path}\\apply_update.bat');

    // 批处理：等本进程退出 → 解压 zip → 找到解压出来的 neu_better_pro.exe
    // 所在目录并整体覆盖安装目录 → 重新启动程序。
    final script = <String>[
      '@echo off',
      'timeout /t 2 /nobreak >nul',
      'powershell -NoProfile -ExecutionPolicy Bypass -Command "Expand-Archive '
          "-LiteralPath '${zip.path}' -DestinationPath '$extractDir' -Force\"",
      'powershell -NoProfile -ExecutionPolicy Bypass -Command "\$src = '
          "Get-ChildItem -Path '$extractDir' -Recurse -Filter "
          "neu_better_pro.exe | Select-Object -First 1; if (\$src) { Copy-Item "
          "-Path (Join-Path \$src.DirectoryName '*') -Destination '$installDir' "
          '-Recurse -Force }"',
      'start "" "${exe.path}"',
      'exit',
    ].join('\r\n');
    bat.writeAsStringSync(script);

    await Process.start(
      'cmd',
      <String>['/c', bat.path],
      mode: ProcessStartMode.detached,
    );
    // 让出控制权后立即退出，批处理会在 exe 释放后完成替换并重启。
    exit(0);
  }
}
