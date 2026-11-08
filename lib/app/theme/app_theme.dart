import 'package:flutter/material.dart';

abstract final class AppColors {
  static const campusBlue = Color(0xFF0B4F9C);
  static const campusBlueDeep = Color(0xFF083B75);
  static const ink = Color(0xFF102A43);
  static const muted = Color(0xFF627D98);
  static const canvas = Color(0xFFF4F8FD);
  static const line = Color(0xFFDCE5F0);
}

abstract final class AppTheme {
  static ThemeData get light {
    final scheme = ColorScheme.fromSeed(
      seedColor: AppColors.campusBlue,
      brightness: Brightness.light,
      surface: Colors.white,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: AppColors.canvas,
      splashFactory: InkSparkle.splashFactory,
      textTheme: const TextTheme(
        displaySmall: TextStyle(
          color: AppColors.ink,
          fontSize: 42,
          height: 1.18,
          fontWeight: FontWeight.w700,
          letterSpacing: -1.2,
        ),
        headlineSmall: TextStyle(
          color: AppColors.ink,
          fontSize: 22,
          height: 1.3,
          fontWeight: FontWeight.w700,
        ),
        titleMedium: TextStyle(
          color: AppColors.ink,
          fontSize: 15,
          height: 1.4,
          fontWeight: FontWeight.w600,
        ),
        bodyMedium: TextStyle(
          color: AppColors.muted,
          fontSize: 14,
          height: 1.7,
        ),
        labelMedium: TextStyle(
          color: AppColors.muted,
          fontSize: 12,
          height: 1.4,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.4,
        ),
      ),
    );
  }
}
