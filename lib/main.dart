import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:local_notifier/local_notifier.dart';

import 'app/app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // 安卓端固定竖屏：手机端只有竖屏操作。
  if (Platform.isAndroid) {
    await SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.portraitUp,
    ]);
  }
  runApp(const ProviderScope(child: NeuBetterApp()));
  // 通知初始化放到首帧之后再跑：它要经过插件的 Win32 注册（本机还可能失败
  // 重试），放在 runApp 之前 await 会拖慢窗口首次显示。失败只打日志，不影响
  // 主流程；电费提醒本身还有应用内弹窗兜底。
  if (Platform.isWindows) {
    unawaited(_setupNotifications());
  }
}

Future<void> _setupNotifications() async {
  try {
    await localNotifier.setup(appName: 'neu_better_pro');
  } catch (error) {
    debugPrint('[notify] setup failed: $error');
  }
}
