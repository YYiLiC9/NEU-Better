import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:local_notifier/local_notifier.dart';

import 'app/app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (Platform.isWindows) {
    try {
      await localNotifier.setup(appName: 'neu_better_pro');
    } catch (error) {
      debugPrint('[notify] setup failed: $error');
    }
  }
  runApp(const ProviderScope(child: NeuBetterApp()));
}
