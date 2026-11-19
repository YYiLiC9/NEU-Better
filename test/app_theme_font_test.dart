import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neu_better_pro/app/theme/app_theme.dart';
import 'package:neu_better_pro/app/theme/windows_font_library.dart';
import 'package:neu_better_pro/core/settings/app_font.dart';
import 'package:neu_better_pro/core/settings/app_settings.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'imported TrueType remains loadable after removing the original',
    () async {
      final folder = await Directory.systemTemp.createTemp('neu_font_test_');
      addTearDown(() => folder.delete(recursive: true));
      final source = await File('assets/fonts/noto-sans-sc/NotoSansSC-VF.ttf')
          .copy('${folder.path}/Example.TTF');
      List<File> storedFiles(String id) => [
        File('${folder.path}/saved/$id.font'),
      ];
      final library = WindowsFontLibrary(files: storedFiles);
      final font = await library.importFile(source);
      await source.delete();
      expect(font.name, 'Example.TTF');

      final userSettings = AppSettings(
        fontPreference: AppFontPreference.imported,
        importedFont: font,
      );
      final restored = AppSettings.fromJson(userSettings.toJson());
      expect(restored.fontPreference, AppFontPreference.imported);
      final newLibrary = WindowsFontLibrary(files: storedFiles);
      expect(
        await newLibrary.load(restored.importedFont!.id),
        'NEU Imported ${font.id}',
      );
      final damaged = await File('${folder.path}/Broken.otf')
          .writeAsString('Not a font');
      await expectLater(library.importFile(damaged), throwsFormatException);
      expect(
        AppSettings.fromJson({
          'fontPreference': 'imported',
          'importedFont': {'id': '../x', 'name': 'x.otf'},
        }).fontPreference,
        AppFontPreference.bundled,
      );
    },
  );

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
