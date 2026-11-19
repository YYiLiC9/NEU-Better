import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neu_better_pro/app/app.dart';
import 'package:neu_better_pro/app/theme/app_theme.dart';
import 'package:neu_better_pro/app/theme/windows_font_library.dart';
import 'package:neu_better_pro/core/auth/auth_session.dart';
import 'package:neu_better_pro/core/settings/app_font.dart';
import 'package:neu_better_pro/core/settings/app_settings.dart';
import 'package:neu_better_pro/features/auth/auth_controller.dart';
import 'package:neu_better_pro/features/timetable/timetable_models.dart';
import 'package:neu_better_pro/features/timetable/timetable_page.dart';

class _MemorySettingsStore extends AppSettingsStore {
  Map<String, dynamic> data = {'autoUpdate': false};

  @override
  Future<AppSettings> read() async => AppSettings.fromJson(data);

  @override
  Future<void> save(AppSettings settings) async {
    data = settings.toJson();
  }
}

class _SignedIn extends AuthController {
  @override
  AuthState build() => AuthAuthenticated(
    AuthSession(
      studentId: 'font-size-test',
      displayName: '测试同学',
      cookies: const {},
      createdAt: DateTime.utc(2026),
      source: 'cas',
    ),
  );
}

class _TestFontLibrary extends WindowsFontLibrary {
  static final font = ImportedAppFont(id: 'a' * 64, name: 'Custom.otf');
  bool invalid = false;

  @override
  Future<ImportedAppFont> pickAndImport() async {
    if (invalid) throw const FormatException('无效字体');
    return font;
  }

  @override
  Future<String> load(String id) async => 'Test font $id';
}

void main() {
  test('Missing and invalid font sizes use medium', () {
    for (final json in <Map<String, dynamic>>[
      {},
      {'fontSizePreference': 'unknown'},
      {'fontSizePreference': 125},
    ]) {
      expect(
        AppSettings.fromJson(json).fontSizePreference,
        FontSizePreference.medium,
      );
    }
  });

  testWidgets('Windows changes and restores the whole app font', (
    tester,
  ) async {
    final store = _MemorySettingsStore();
    final library = _TestFontLibrary();

    Future<AppSettingsController> startApp() async {
      final controller = AppSettingsController(
        store: store,
        initial: await store.read(),
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appSettingsProvider.overrideWith((_) => controller),
            authControllerProvider.overrideWith(_SignedIn.new),
            windowsFontLibraryProvider.overrideWithValue(library),
          ],
          child: const NeuBetterApp(),
        ),
      );
      await tester.pumpAndSettle();
      return controller;
    }

    String? homeFont() =>
        Theme.of(tester.element(find.text('首页', skipOffstage: false)))
            .textTheme
            .bodyMedium!
            .fontFamily;

    final controller = await startApp();
    expect(homeFont(), AppTheme.windowsBundledFontFamily);
    await tester.tap(find.byTooltip('设置'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('系统默认'));
    await tester.pumpAndSettle();
    expect(homeFont(), AppTheme.windowsSystemFontFamily);

    library.invalid = true;
    await tester.tap(find.text('从文件导入'));
    await tester.pumpAndSettle();
    expect(find.text('无效字体'), findsOneWidget);
    expect(homeFont(), AppTheme.windowsSystemFontFamily);

    library.invalid = false;
    await tester.tap(find.text('从文件导入'));
    await tester.pumpAndSettle();
    final importedFamily = 'Test font ${_TestFontLibrary.font.id}';
    expect(homeFont(), importedFamily);
    expect(find.text('Custom.otf'), findsOneWidget);
    await tester.tap(find.text('内置字体'));
    await tester.pumpAndSettle();
    expect(homeFont(), AppTheme.windowsBundledFontFamily);
    await tester.tap(find.text('已导入'));
    await tester.pumpAndSettle();
    expect(homeFont(), importedFamily);
    await controller.flush();

    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    await startApp();
    expect(homeFont(), importedFamily);
  }, variant: const TargetPlatformVariant({TargetPlatform.windows}));

  testWidgets('Windows font slider scales the app and saves each stop', (
    tester,
  ) async {
    await tester.runAsync(AppTheme.loadWindowsFont);
    tester.view.physicalSize = const Size(780, 520);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 1.1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    final store = _MemorySettingsStore();
    final controller = AppSettingsController(
      store: store,
      initial: await store.read(),
    );
    const course = CourseSession(
      id: 'long-title',
      name: '中国式现代化的理论与实践',
      teacher: '王老师',
      room: '浑南校区一号教学楼 101',
      className: '研究生课程',
      day: 1,
      startPeriod: 1,
      endPeriod: 1,
      weeks: {1},
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appSettingsProvider.overrideWith((_) => controller),
          authControllerProvider.overrideWith(_SignedIn.new),
          timetableDataProvider.overrideWith(
            (_) => const TimetableData(
              termName: '测试学期',
              totalWeeks: 16,
              currentWeek: 1,
              sessions: [course],
            ),
          ),
        ],
        child: const NeuBetterApp(),
      ),
    );
    await tester.pumpAndSettle();
    final home = find.text('首页');
    expect(
      MediaQuery.textScalerOf(tester.element(home)).scale(14),
      closeTo(15.4, 0.01),
    );
    await tester.tap(find.byTooltip('设置'));
    await tester.pumpAndSettle();
    expect(find.text('字体大小'), findsOneWidget);
    expect(find.text('小'), findsOneWidget);
    expect(find.text('大'), findsOneWidget);
    expect(find.text('中'), findsNothing);
    expect(find.text('特大'), findsNothing);

    final slider = find.byType(Slider);
    expect(tester.widget<Slider>(slider).divisions, 3);
    expect(tester.widget<Slider>(slider).value, 1);
    const presets = FontSizePreference.values;
    for (final preference in presets) {
      final rect = tester.getRect(slider);
      final progress = (preference.index + 0.5) / presets.length;
      await tester.tapAt(
        Offset(rect.left + rect.width * progress, rect.center.dy),
      );
      await tester.pumpAndSettle();
      expect(tester.widget<Slider>(slider).value, preference.index.toDouble());
      final textScaler = MediaQuery.textScalerOf(tester.element(slider));
      expect(textScaler.scale(14), closeTo(15.4 * preference.scale, 0.01));
      await controller.flush();
      expect((await store.read()).fontSizePreference, preference);
      expect(tester.takeException(), isNull);
    }

    await tester.tap(find.byTooltip('关闭'));
    await tester.pumpAndSettle();
    expect(
      MediaQuery.textScalerOf(tester.element(home)).scale(14),
      closeTo(19.25, 0.01),
    );
    await tester.tap(find.text('课表'));
    await tester.pumpAndSettle();
    expect(find.text('我的课表'), findsOneWidget);
    expect(find.text(course.name), findsOneWidget);
    expect(tester.takeException(), isNull);
  }, variant: const TargetPlatformVariant({TargetPlatform.windows}));
}
