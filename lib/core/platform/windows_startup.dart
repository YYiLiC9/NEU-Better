import 'dart:io';

import 'package:flutter/foundation.dart';

/// Windows 开机自启动：写/删 `HKCU\Software\Microsoft\Windows\CurrentVersion\Run`。
///
/// 只影响当前用户（无需管理员权限）。值名固定为 [valueName]，值为带引号的
/// 当前 exe 路径。使用 `reg.exe` 且 detached 启动，避免在 GUI 程序里弹出控制台窗口。
class WindowsStartup {
  const WindowsStartup._();

  static const String _runKey =
      r'HKCU\Software\Microsoft\Windows\CurrentVersion\Run';
  static const String valueName = 'NEU Better';

  static bool get isSupported => !kIsWeb && Platform.isWindows;

  /// 写注册表（enabled=true）或删除（enabled=false）。失败只记录，不抛出。
  static Future<void> setEnabled(bool enabled) async {
    if (!isSupported) return;
    try {
      if (enabled) {
        // Run 项里路径含空格必须带引号，否则开机时会被拆成多个参数。
        final command = '"${Platform.resolvedExecutable}"';
        await Process.start(
          'reg',
          ['add', _runKey, '/v', valueName, '/t', 'REG_SZ', '/d', command, '/f'],
          mode: ProcessStartMode.detached,
        );
      } else {
        await Process.start(
          'reg',
          ['delete', _runKey, '/v', valueName, '/f'],
          mode: ProcessStartMode.detached,
        );
      }
    } catch (error) {
      debugPrint('[startup] setEnabled($enabled) failed: $error');
    }
  }

  /// 查询当前是否已在 Run 项登记本应用（用于诊断，非 UI 阻塞路径）。
  static Future<bool> isEnabled() async {
    if (!isSupported) return false;
    try {
      final result = await Process.run(
        'reg',
        ['query', _runKey, '/v', valueName],
      );
      return result.exitCode == 0 &&
          result.stdout.toString().contains(valueName);
    } catch (_) {
      return false;
    }
  }
}
