import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neu_better_pro/app/theme/app_theme.dart';

void main() {
  testWidgets('Windows theme renders Chinese and Latin in the bundled font', (
    tester,
  ) async {
    await tester.runAsync(AppTheme.loadWindowsFont);

    const label = '课表 NEU 12:34';
    for (final theme in [AppTheme.light, AppTheme.dark]) {
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: const Scaffold(body: Text(label)),
        ),
      );
      final paragraph = tester.renderObject<RenderParagraph>(find.text(label));
      expect(paragraph.text.style?.fontFamily, 'NEU Noto Sans SC');
      // Ahem assigns an em to every character. Noto Sans SC uses narrower
      // Latin letters, digits and spaces, so this also checks the font loaded.
      expect(
        paragraph.getMaxIntrinsicWidth(double.infinity),
        lessThan(label.length * theme.textTheme.bodyMedium!.fontSize!),
      );
    }
  }, variant: const TargetPlatformVariant({TargetPlatform.windows}));

  testWidgets('Android theme uses its platform font', (tester) async {
    expect(
      AppTheme.light.textTheme.bodyMedium!.fontFamily,
      ThemeData().textTheme.bodyMedium!.fontFamily,
    );
  }, variant: const TargetPlatformVariant({TargetPlatform.android}));
}
