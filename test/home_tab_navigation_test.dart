import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neu_better_pro/app/app.dart';
import 'package:neu_better_pro/core/auth/auth_session.dart';
import 'package:neu_better_pro/core/auth/credential_store.dart';
import 'package:neu_better_pro/core/auth/saved_credentials.dart';
import 'package:neu_better_pro/core/auth/session_store.dart';
import 'package:neu_better_pro/features/auth/auth_controller.dart';
import 'package:neu_better_pro/core/plugins/plugin_models.dart';
import 'package:neu_better_pro/core/plugins/plugin_service.dart';
import 'package:neu_better_pro/features/home/home_page.dart';

class _TestSessionStore implements SessionStore {
  _TestSessionStore(this.session);

  final AuthSession? session;

  @override
  Future<AuthSession?> read() async => session;

  @override
  Future<void> save(AuthSession session) async {}

  @override
  Future<void> clear() async {}
}

class _TestCredentialStore implements CredentialStore {
  @override
  Future<SavedCredentials?> read() async => null;

  @override
  Future<void> save(SavedCredentials value) async {}

  @override
  Future<void> clear() async {}
}

class _LocalPluginService extends PluginService {
  @override
  Future<PluginCatalog> fetchCatalog({bool force = false}) async =>
      const PluginCatalog(version: 1, plugins: []);
}

AuthSession _session() => AuthSession(
  studentId: '20260001',
  displayName: '测试同学',
  cookies: const {'pass.neu.edu.cn': 'JSESSIONID=abc'},
  createdAt: DateTime.utc(2026, 11, 8, 8),
  source: 'cas',
);

Future<void> _pumpHome(WidgetTester tester) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        homePluginServiceProvider.overrideWithValue(_LocalPluginService()),
        sessionStoreProvider.overrideWithValue(_TestSessionStore(_session())),
        credentialStoreProvider.overrideWithValue(_TestCredentialStore()),
      ],
      child: const NeuBetterApp(),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'switching to the timetable and back to home restores the overview',
    (tester) async {
      await _pumpHome(tester);
      // 默认落在首页根，可见卡片。
      expect(find.text('余额中心'), findsOneWidget);

      await tester.tap(find.text('课表'));
      await tester.pumpAndSettle();
      expect(find.text('我的课表'), findsOneWidget);

      await tester.tap(find.text('首页'));
      await tester.pumpAndSettle();
      // 修复后：点「首页」不再残留课表，而是回到首页概览。
      expect(find.text('我的课表'), findsNothing);
      expect(find.text('余额中心'), findsOneWidget);
    },
    variant: const TargetPlatformVariant({
      TargetPlatform.windows,
      TargetPlatform.android,
    }),
  );

  testWidgets(
    'returning from the timetable keeps the last home sub-page',
    (tester) async {
      await _pumpHome(tester);

      // 打开首页二级页「插件库」。
      await tester.tap(find.byTooltip('添加卡片'));
      await tester.pumpAndSettle();
      expect(find.text('插件库'), findsOneWidget);

      await tester.tap(find.text('课表'));
      await tester.pumpAndSettle();
      expect(find.text('我的课表'), findsOneWidget);

      // 从课表点「首页」应回到上次的「插件库」二级页，而不是课表。
      await tester.tap(find.text('首页').first);
      await tester.pumpAndSettle();
      expect(find.text('我的课表'), findsNothing);
      expect(find.text('插件库'), findsOneWidget);

      // 已在首页二级页再次点「首页」→ 回到概览根。
      await tester.tap(find.text('首页').first);
      await tester.pumpAndSettle();
      expect(find.text('余额中心'), findsOneWidget);
      expect(find.text('插件库'), findsNothing);
    },
    variant: const TargetPlatformVariant({
      TargetPlatform.windows,
      TargetPlatform.android,
    }),
  );
}
