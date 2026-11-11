import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// 封装 NEU Better 在 Windows 桌面端需要的原生窗口能力。
///
/// 目前提供三项能力：
/// * [setTaskbarTitle]：设置窗口标题，任务栏/托盘悬浮时显示（例如寝室用电）。
/// * [setCloseBehavior]：设置点击关闭按钮时的行为（隐藏到托盘或退出）。
/// * [setTrayIconVisible]：显示或隐藏系统托盘图标。
///
/// 非 Windows 平台调用为空操作；原生通道不可用时只记录日志，不向调用方
/// 抛出异常，避免影响业务功能。
abstract final class WindowsWindow {
  static const MethodChannel _channel = MethodChannel('neu_better/window');

  /// 设置窗口标题（也用于任务栏悬浮提示）。
  static Future<void> setTaskbarTitle(String title) async {
    if (!Platform.isWindows) {
      return;
    }
    try {
      await _channel.invokeMethod<void>('setTitle', title);
    } catch (error) {
      debugPrint('WindowsWindow.setTaskbarTitle failed: $error');
    }
  }

  /// 设置关闭按钮行为。
  ///
  /// [minimizeToTaskbar] 为 true 时点击关闭按钮只隐藏窗口到系统托盘，不退出
  /// 应用；为 false 时恢复默认的关闭退出行为。
  static Future<void> setCloseBehavior({
    required bool minimizeToTaskbar,
  }) async {
    if (!Platform.isWindows) {
      return;
    }
    try {
      await _channel.invokeMethod<void>('setCloseBehavior', minimizeToTaskbar);
    } catch (error) {
      debugPrint('WindowsWindow.setCloseBehavior failed: $error');
    }
  }

  /// 显示或隐藏系统托盘图标。
  static Future<void> setTrayIconVisible(bool visible) async {
    if (!Platform.isWindows) {
      return;
    }
    try {
      await _channel.invokeMethod<void>('setTrayIconVisible', visible);
    } catch (error) {
      debugPrint('WindowsWindow.setTrayIconVisible failed: $error');
    }
  }
}
