import 'package:flutter/material.dart';

/// 「东大校刊 · 号外」主题令牌（新闻插件专用，不外泄到其它模块）。
class NewsPalette {
  const NewsPalette._();

  /// 纸白。
  static const Color paper = Color(0xFFFAFAF7);

  /// 墨黑（主文字）。
  static const Color ink = Color(0xFF1A1D21);

  /// 次级墨。
  static const Color inkSoft = Color(0xFF5B626B);

  /// 细线。
  static const Color hairline = Color(0xFFE4E6E9);

  /// 版面主蓝。
  static const Color blue = Color(0xFF0B4F9C);

  /// 号外红（仅「校内通知」标签 / 未读点）。
  static const Color red = Color(0xFFB5332D);

  /// 衬线字体族（详情大标题、头条标题）。
  static const String serifFamily = 'Songti SC';
  static const List<String> serifFallback = <String>[
    'Noto Serif CJK SC',
    'Noto Serif SC',
    'SimSun',
    'serif',
  ];

  static const List<String> sansFallback = <String>[
    'Microsoft YaHei UI',
    'Microsoft YaHei',
    'Noto Sans CJK SC',
    'Noto Sans SC',
  ];
}

/// 衬线标题样式。
TextStyle newsSerif({
  double fontSize = 22,
  FontWeight fontWeight = FontWeight.w700,
  Color color = NewsPalette.ink,
  double height = 1.35,
}) {
  return TextStyle(
    fontFamily: NewsPalette.serifFamily,
    fontFamilyFallback: NewsPalette.serifFallback,
    fontSize: fontSize,
    fontWeight: fontWeight,
    color: color,
    height: height,
  );
}

/// 正文/列表无衬线样式。
TextStyle newsSans({
  double fontSize = 14,
  FontWeight fontWeight = FontWeight.w400,
  Color color = NewsPalette.ink,
  double height = 1.5,
}) {
  return TextStyle(
    fontFamilyFallback: NewsPalette.sansFallback,
    fontSize: fontSize,
    fontWeight: fontWeight,
    color: color,
    height: height,
  );
}
