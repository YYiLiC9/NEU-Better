import 'package:flutter/material.dart';

import '../features/landing/m0_landing_page.dart';
import 'theme/app_theme.dart';

class NeuBetterApp extends StatelessWidget {
  const NeuBetterApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'NEU Better',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      home: const M0LandingPage(),
    );
  }
}
