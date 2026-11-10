import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

abstract final class AppColors {
  static const campusBlue = Color(0xFF0B4F9C);
  static const campusBlueDeep = Color(0xFF083B75);
  static const ink = Color(0xFF14243B);
  static const muted = Color(0xFF5D7392);
  static const canvas = Color(0xFFF6F8FB);
  static const line = Color(0xFFD9E2EE);
  static const faint = Color(0xFF829AB1);
  static const accent = Color(0xFF2CB1BC);
  static const danger = Color(0xFFB42318);
  // 朱：只用于考试卡片与"当前时间线"，让红色在界面里始终意味着"此刻/紧要"。
  static const nowRed = Color(0xFFC2402A);

  /// 传统色课程墨色组：每门课从这一组里按稳定哈希取色，
  /// 背景为同色纸调淡染，前景为对应墨色。整组在同一色温体系内，
  /// 避免随机色相造成的花哨感。
  static const coursePigments = <(Color, Color)>[
    (Color(0xFFEDF3FA), Color(0xFF2E5E8F)), // 靛蓝
    (Color(0xFFEAF4EE), Color(0xFF31734F)), // 竹青
    (Color(0xFFF7EFE7), Color(0xFF9A5A2B)), // 赭石
    (Color(0xFFF1ECF7), Color(0xFF6E4E8E)), // 绛紫
    (Color(0xFFF8ECE8), Color(0xFFA8432F)), // 砖红
    (Color(0xFFEAF0F6), Color(0xFF34506B)), // 黛青
  ];

  /// 按课程名稳定取一组 (背景, 墨色)。
  static (Color, Color) pigmentFor(String key) =>
      coursePigments[key.hashCode.abs() % coursePigments.length];
}

abstract final class AppTheme {
  static ThemeData get light {
    final scheme = ColorScheme.fromSeed(
      seedColor: AppColors.campusBlue,
      brightness: Brightness.light,
      surface: Colors.white,
    );

    // Keep the OS font on each platform. On Windows the explicit family
    // prevents Chinese glyphs from falling back to a different typeface than
    // the Latin text, which makes headings look uneven at small sizes.
    final fontFamily = defaultTargetPlatform == TargetPlatform.windows
        ? 'Microsoft YaHei UI'
        : null;

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: AppColors.canvas,
      splashFactory: InkSparkle.splashFactory,
      fontFamily: fontFamily,
      textTheme: const TextTheme(
        displaySmall: TextStyle(
          color: AppColors.ink,
          fontSize: 42,
          height: 1.18,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.8,
        ),
        headlineSmall: TextStyle(
          color: AppColors.ink,
          fontSize: 22,
          height: 1.3,
          fontWeight: FontWeight.w600,
        ),
        titleMedium: TextStyle(
          color: AppColors.ink,
          fontSize: 15,
          height: 1.4,
          fontWeight: FontWeight.w500,
        ),
        bodyMedium: TextStyle(
          color: AppColors.muted,
          fontSize: 14,
          height: 1.7,
          fontWeight: FontWeight.w400,
        ),
        labelMedium: TextStyle(
          color: AppColors.muted,
          fontSize: 12,
          height: 1.4,
          fontWeight: FontWeight.w500,
          letterSpacing: 0.3,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 15,
          vertical: 16,
        ),
        hintStyle: const TextStyle(
          color: AppColors.faint,
          fontSize: 13,
          fontWeight: FontWeight.w400,
        ),
        labelStyle: const TextStyle(
          color: AppColors.muted,
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
        prefixIconColor: AppColors.faint,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(11),
          borderSide: const BorderSide(color: AppColors.line),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(11),
          borderSide: const BorderSide(color: AppColors.line),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(11),
          borderSide: const BorderSide(color: AppColors.campusBlue, width: 1.4),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(11),
          borderSide: const BorderSide(color: AppColors.danger),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(11),
          borderSide: const BorderSide(color: AppColors.danger, width: 1.4),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.campusBlue,
          foregroundColor: Colors.white,
          minimumSize: const Size(0, 48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(11),
          ),
          textStyle: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.2,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.campusBlue,
          textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}
