import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neu_better_pro/app/app.dart';
import 'package:neu_better_pro/app/theme/app_theme.dart';
import 'package:neu_better_pro/core/auth/auth_session.dart';
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
