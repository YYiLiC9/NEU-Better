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
  if (Platform.isWindows) {
    try {
      await localNotifier.setup(appName: 'neu_better_pro');
    } catch (error) {
      debugPrint('[notify] setup failed: $error');
    }
  }
  runApp(const ProviderScope(child: NeuBetterApp()));
}
