import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// 浅色 / 深色两套令牌值。界面只通过 [AppColors] 取色，
/// 由 `AppColors.setDark` 在应用根部统一切换。
@immutable
class _Palette {
  const _Palette({
    required this.campusBlue,
    required this.campusBlueDeep,
    required this.ink,
    required this.muted,
    required this.faint,
    required this.canvas,
    required this.line,
    required this.surface,
    required this.accent,
    required this.danger,
    required this.nowRed,
  });

  final Color campusBlue;
  final Color campusBlueDeep;
  final Color ink;
  final Color muted;
  final Color faint;
  final Color canvas;
  final Color line;
  final Color surface;
  final Color accent;
  final Color danger;
  final Color nowRed;
}

const _lightPalette = _Palette(
  campusBlue: Color(0xFF0B4F9C),
  campusBlueDeep: Color(0xFF083B75),
  ink: Color(0xFF14243B),
  muted: Color(0xFF5D7392),
  faint: Color(0xFF829AB1),
  canvas: Color(0xFFF6F8FB),
  line: Color(0xFFD9E2EE),
  surface: Colors.white,
  accent: Color(0xFF2CB1BC),
  danger: Color(0xFFB42318),
  nowRed: Color(0xFFC2402A),
);

/// 深色令牌：深蓝灰底 + 克制的亮蓝强调色。
/// 文字使用近白而不是纯白，减少长时间阅读的眩光。
const _darkPalette = _Palette(
  campusBlue: Color(0xFF5A97D6),
  campusBlueDeep: Color(0xFF2F6BA8),
  ink: Color(0xFFE6EDF6),
  muted: Color(0xFF9CAFC6),
  faint: Color(0xFF7589A2),
  canvas: Color(0xFF0D1520),
  line: Color(0xFF2A3A4E),
  surface: Color(0xFF161F2C),
  accent: Color(0xFF4CC8D1),
  danger: Color(0xFFF08A80),
  nowRed: Color(0xFFE46A52),
);

abstract final class AppColors {
  static bool _isDark = false;

  /// 当前是否处于深色模式。由 [AppColors.setDark] 在应用根组件中维护。
  static bool get isDark => _isDark;

  static void setDark(bool value) {
    _isDark = value;
  }

  static _Palette get _palette => _isDark ? _darkPalette : _lightPalette;

  static Color get campusBlue => _palette.campusBlue;
  static Color get campusBlueDeep => _palette.campusBlueDeep;
  static Color get ink => _palette.ink;
  static Color get muted => _palette.muted;
  static Color get canvas => _palette.canvas;
  static Color get line => _palette.line;
  static Color get faint => _palette.faint;
  static Color get accent => _palette.accent;
  static Color get danger => _palette.danger;

  /// 朱：只用于考试卡片与"当前时间线"，让红色在界面里始终意味着"此刻/紧要"。
  static Color get nowRed => _palette.nowRed;

  /// 卡片 / 侧栏 / 输入框等"抬升面"底色：浅色为白，深色为深色卡片面。
  static Color get surface => _palette.surface;

  /// 传统色课程墨色组：每门课从这一组里按稳定哈希取色，
  /// 背景为同色纸调淡染，前景为对应墨色。整组在同一色温体系内，
  /// 避免随机色相造成的花哨感。
  static const _lightCoursePigments = <(Color, Color)>[
    (Color(0xFFEDF3FA), Color(0xFF2E5E8F)), // 靛蓝
    (Color(0xFFEAF4EE), Color(0xFF31734F)), // 竹青
    (Color(0xFFF7EFE7), Color(0xFF9A5A2B)), // 赭石
    (Color(0xFFF1ECF7), Color(0xFF6E4E8E)), // 绛紫
    (Color(0xFFF8ECE8), Color(0xFFA8432F)), // 砖红
    (Color(0xFFEAF0F6), Color(0xFF34506B)), // 黛青
  ];

  /// 深色课程卡：深色低饱和底 + 同色系浅墨字，保持六组色的辨识度。
  static const _darkCoursePigments = <(Color, Color)>[
    (Color(0xFF1E2F45), Color(0xFFA8C8F0)), // 靛蓝
    (Color(0xFF1C3328), Color(0xFF8FD0AB)), // 竹青
    (Color(0xFF362A1F), Color(0xFFE0B27C)), // 赭石
    (Color(0xFF2C2438), Color(0xFFC3A8E8)), // 绛紫
    (Color(0xFF382322), Color(0xFFE89A8A)), // 砖红
    (Color(0xFF222F3D), Color(0xFFA7BDD4)), // 黛青
  ];

  /// 当前模式下的课程色组。
  static List<(Color, Color)> get coursePigments =>
      _isDark ? _darkCoursePigments : _lightCoursePigments;

  /// 按课程名稳定取一组 (背景, 墨色)。
  static (Color, Color) pigmentFor(String key) {
    final pigments = coursePigments;
    return pigments[(key.hashCode & 0x7fffffff) % pigments.length];
  }
}

abstract final class AppTheme {
  static ThemeData get light => _build(_lightPalette, Brightness.light);

  static ThemeData get dark => _build(_darkPalette, Brightness.dark);

  static ThemeData _build(_Palette palette, Brightness brightness) {
    final scheme = ColorScheme.fromSeed(
      seedColor: palette.campusBlue,
      brightness: brightness,
      surface: palette.surface,
    );

    // Windows 优先 Segoe UI Variable Text（Win11 系统字体，数字等宽观感更
    // 整齐），缺省时逐级回落到 Segoe UI 与雅黑；明确列出 fallback 避免中文
    // 与拉丁字符落到不同字体上。
    const windowsFontStack = <String>[
      'Segoe UI Variable Text',
      'Segoe UI',
      'Microsoft YaHei UI',
      'Microsoft YaHei',
    ];
    final fontFamily = defaultTargetPlatform == TargetPlatform.windows
        ? windowsFontStack.first
        : null;
    final List<String> fontFamilyFallback = defaultTargetPlatform ==
            TargetPlatform.windows
        ? windowsFontStack.skip(1).toList()
        : const <String>[];
    final isDark = brightness == Brightness.dark;
    final onPrimary = isDark ? const Color(0xFF08131F) : Colors.white;
    // 数字统一等宽（tabular figures）：时间、周次、电量等数值在卡片里
    // 不会因比例数字宽度抖动。
    const numericFeatures = <FontFeature>[FontFeature.tabularFigures()];

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: palette.canvas,
      splashFactory: InkSparkle.splashFactory,
      fontFamily: fontFamily,
      fontFamilyFallback: fontFamilyFallback,
      textTheme: TextTheme(
        displaySmall: TextStyle(
          color: palette.ink,
          fontSize: 42,
          height: 1.18,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.8,
          fontFeatures: numericFeatures,
        ),
        headlineSmall: TextStyle(
          color: palette.ink,
          fontSize: 22,
          height: 1.3,
          fontWeight: FontWeight.w600,
          fontFeatures: numericFeatures,
        ),
        titleMedium: TextStyle(
          color: palette.ink,
          fontSize: 15,
          height: 1.4,
          fontWeight: FontWeight.w500,
          fontFeatures: numericFeatures,
        ),
        bodyMedium: TextStyle(
          color: palette.muted,
          fontSize: 14,
          height: 1.7,
          fontWeight: FontWeight.w400,
          fontFeatures: numericFeatures,
        ),
        labelMedium: TextStyle(
          color: palette.muted,
          fontSize: 12,
          height: 1.4,
          fontWeight: FontWeight.w500,
          letterSpacing: 0.3,
          fontFeatures: numericFeatures,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: palette.surface,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 15,
          vertical: 16,
        ),
        hintStyle: TextStyle(
          color: palette.faint,
          fontSize: 13,
          fontWeight: FontWeight.w400,
        ),
        labelStyle: TextStyle(
          color: palette.muted,
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
        prefixIconColor: palette.faint,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(11),
          borderSide: BorderSide(color: palette.line),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(11),
          borderSide: BorderSide(color: palette.line),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(11),
          borderSide: BorderSide(color: palette.campusBlue, width: 1.4),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(11),
          borderSide: BorderSide(color: palette.danger),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(11),
          borderSide: BorderSide(color: palette.danger, width: 1.4),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: palette.campusBlue,
          foregroundColor: onPrimary,
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
          foregroundColor: palette.campusBlue,
          textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
        ),
      ),
      dividerTheme: DividerThemeData(color: palette.line, thickness: 1),
    );
  }
}
