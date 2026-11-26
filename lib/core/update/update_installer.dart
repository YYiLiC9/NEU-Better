import 'dart:io';

import 'package:flutter/services.dart';

/// 安装下载好的更新包。
///
/// - Android：交给系统安装器（FileProvider 授权读 apk）。
/// - Windows：因运行中 exe 无法被覆盖，改由一个脱离的批处理在进程退出后
///   解压并覆盖安装目录，再重新启动程序。
abstract final class UpdateInstaller {
  static const MethodChannel _channel = MethodChannel('neu_better/updater');

  /// 当前是否由 Inno Setup 安装（安装目录存在 unins000.exe）。
  ///
  /// 便携版（zip 解压）没有卸载器；自动更新必须下载 zip 并覆盖当前目录，
  /// 不能下载 installer.exe，否则会打开安装向导而不是更新便携目录。
  static bool get isSetupInstalled {
    if (!Platform.isWindows) return false;
    final dir = File(Platform.resolvedExecutable).parent;
    return isSetupInstalledIn(dir.path);
  }

  /// 纯目录判断，便于单测（Windows 便携版 / 安装版）。
  static bool isSetupInstalledIn(String directory) {
    if (!Platform.isWindows) return false;
    return File(
      '$directory${Platform.pathSeparator}unins000.exe',
    ).existsSync();
  }

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
      // 安装版：静默安装到当前安装目录（保留用户选择的位置），再启动。
      script = <String>[
        '@echo off',
        'chcp 65001 >nul',
        'setlocal',
        'set "LOG=%TEMP%\\neu_better_update.log"',
        'echo [%date% %time%] start setup update>>"%LOG%"',
        'set /a tries=0',
        ':waitloop',
        'tasklist /FI "IMAGENAME eq NEUBetterPro.exe" 2>nul | find /I '
            '"NEUBetterPro.exe" >nul',
        'if errorlevel 1 goto proceed',
        'set /a tries+=1',
        'if %tries% GEQ 15 goto proceed',
        'timeout /t 1 /nobreak >nul',
        'goto waitloop',
        ':proceed',
        'echo [%date% %time%] running installer>>"%LOG%"',
        'start "" /wait "${package.path}" /VERYSILENT /SUPPRESSMSGBOXES '
            '/NORESTART /SP- /CLOSEAPPLICATIONS /DIR="$installDir" '
            '/LOG="%TEMP%\\neu_better_setup.log"',
        'set "RC=%errorlevel%"',
        'echo [%date% %time%] installer exit=%RC%>>"%LOG%"',
        'if not "%RC%"=="0" echo [%date% %time%] installer failed rc=%RC%>>'
            '"%TEMP%\\neu_better_update_failed.txt"',
        'start "" "${exe.path}"',
        'exit /b',
      ];
    } else {
      // zip 便携版：等本进程退出 → 解压 → 覆盖安装目录 → 重新启动。
      final extractDir = '${temp.path}\\extract';
      script = <String>[
        '@echo off',
        'chcp 65001 >nul',
        'setlocal',
        'set "LOG=%TEMP%\\neu_better_update.log"',
        'echo [%date% %time%] start zip update>>"%LOG%"',
        'set /a tries=0',
        ':waitloop',
        'tasklist /FI "IMAGENAME eq NEUBetterPro.exe" 2>nul | find /I '
            '"NEUBetterPro.exe" >nul',
        'if errorlevel 1 goto proceed',
        'set /a tries+=1',
        'if %tries% GEQ 15 goto proceed',
        'timeout /t 1 /nobreak >nul',
        'goto waitloop',
        ':proceed',
        'echo [%date% %time%] extracting>>"%LOG%"',
        'powershell -NoProfile -ExecutionPolicy Bypass -Command "Expand-Archive '
            "-LiteralPath '${package.path}' -DestinationPath '$extractDir' "
            '-Force" >>"%LOG%" 2>&1',
        'if errorlevel 1 goto zipfail',
        'echo [%date% %time%] copying to $installDir>>"%LOG%"',
        'powershell -NoProfile -ExecutionPolicy Bypass -Command "\$src = '
            "Get-ChildItem -Path '$extractDir' -Recurse -Filter "
            "'NEUBetterPro.exe' | Select-Object -First 1; if (-not \$src) "
            "{ exit 2 }; robocopy \$src.DirectoryName '$installDir' /E /R:2 "
            '/W:1 /NFL /NDL /NJH /NJS; exit \$LASTEXITCODE" >>"%LOG%" 2>&1',
        'set "RC=%errorlevel%"',
        'echo [%date% %time%] copy exit=%RC%>>"%LOG%"',
        'if %RC% GEQ 8 goto zipfail',
        'start "" "${exe.path}"',
        'exit /b',
        ':zipfail',
        'echo [%date% %time%] zip update failed rc=%RC%>>'
            '"%TEMP%\\neu_better_update_failed.txt"',
        'start "" "${exe.path}"',
        'exit /b',
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
