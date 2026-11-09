import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neu_better_pro/app/app.dart';
import 'package:neu_better_pro/core/auth/auth_session.dart';
import 'package:neu_better_pro/core/auth/session_store.dart';
import 'package:neu_better_pro/core/crypto/rsa_encryptor.dart';
import 'package:neu_better_pro/features/auth/auth_controller.dart';

class _TestSessionStore implements SessionStore {
  _TestSessionStore([this.session]);

  final AuthSession? session;

  @override
  Future<AuthSession?> read() async => session;

  @override
  Future<void> save(AuthSession session) async {}

  @override
  Future<void> clear() async {}
}

void main() {
  testWidgets('M1 gate opens on the login page without a saved session', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sessionStoreProvider.overrideWithValue(_TestSessionStore()),
        ],
        child: const NeuBetterApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('登录你的校园'), findsOneWidget);
    expect(find.text('东北大学 · 一号通'), findsOneWidget);
    expect(find.text('遇到验证码 / 二次验证？使用网页登录'), findsOneWidget);
  });

  testWidgets('M1 gate restores a saved session into the home page', (
    tester,
  ) async {
    final session = AuthSession(
      studentId: '20260001',
      displayName: '测试同学',
      cookies: const {'pass.neu.edu.cn': 'JSESSIONID=abc'},
      createdAt: DateTime.utc(2026, 11, 8, 8),
      source: 'cas',
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sessionStoreProvider.overrideWithValue(_TestSessionStore(session)),
        ],
        child: const NeuBetterApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('登录成功，会话已保存。'), findsOneWidget);
    expect(find.text('MILESTONE 1 · 登录'), findsOneWidget);
    expect(find.text('测试同学'), findsWidgets);
  });

  testWidgets('logout returns from the home page to the login page', (
    tester,
  ) async {
    final session = AuthSession(
      studentId: '20260001',
      displayName: '20260001',
      cookies: const {'pass.neu.edu.cn': 'JSESSIONID=abc'},
      createdAt: DateTime.utc(2026, 11, 8, 8),
      source: 'cas',
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sessionStoreProvider.overrideWithValue(_TestSessionStore(session)),
        ],
        child: const NeuBetterApp(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('退出登录'));
    await tester.pumpAndSettle();

    expect(find.text('登录你的校园'), findsOneWidget);
  });

  test('AuthSession survives a JSON round trip', () {
    final session = AuthSession(
      studentId: '20260001',
      displayName: '测试同学',
      cookies: const {'pass.neu.edu.cn': 'JSESSIONID=abc'},
      createdAt: DateTime.utc(2026, 11, 8, 8),
      source: 'cas',
    );

    final restored = AuthSession.decode(session.encode());

    expect(restored.studentId, '20260001');
    expect(restored.displayName, '测试同学');
    expect(restored.cookies, session.cookies);
    expect(restored.source, 'cas');
    expect(restored.hasCookies, isTrue);
  });

  test('CAS RSA encryption produces a 2048-bit ciphertext', () {
    final encrypted = NeuRsaEncryptor.encrypt('20260001password');
    expect(base64Decode(encrypted), hasLength(256));
  });
}
