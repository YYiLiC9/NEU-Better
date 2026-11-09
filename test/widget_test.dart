import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neu_better_pro/app/app.dart';
import 'package:neu_better_pro/core/auth/auth_session.dart';
import 'package:neu_better_pro/core/auth/credential_store.dart';
import 'package:neu_better_pro/core/auth/saved_credentials.dart';
import 'package:neu_better_pro/core/auth/session_store.dart';
import 'package:neu_better_pro/core/auth/student_identity.dart';
import 'package:neu_better_pro/core/auth/webview_login_result.dart';
import 'package:neu_better_pro/core/crypto/rsa_encryptor.dart';
import 'package:neu_better_pro/features/auth/auth_controller.dart';

class _TestCredentialStore implements CredentialStore {
  _TestCredentialStore([this.credentials]);

  SavedCredentials? credentials;

  @override
  Future<SavedCredentials?> read() async => credentials;

  @override
  Future<void> save(SavedCredentials value) async {
    credentials = value;
  }

  @override
  Future<void> clear() async {
    credentials = null;
  }
}

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
          credentialStoreProvider.overrideWithValue(_TestCredentialStore()),
        ],
        child: const NeuBetterApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('登录你的校园'), findsOneWidget);
    expect(find.text('东北大学 · 一号通'), findsOneWidget);
    expect(find.text('使用学校网页登录（验证码 / 二次验证）'), findsOneWidget);
  });

  testWidgets('login page prefills saved credentials', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sessionStoreProvider.overrideWithValue(_TestSessionStore()),
          credentialStoreProvider.overrideWithValue(
            _TestCredentialStore(
              const SavedCredentials(
                username: '20260001',
                password: 'saved-secret',
              ),
            ),
          ),
        ],
        child: const NeuBetterApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('20260001'), findsOneWidget);
    expect(find.text('saved-secret'), findsOneWidget);
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
          credentialStoreProvider.overrideWithValue(_TestCredentialStore()),
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
          credentialStoreProvider.overrideWithValue(_TestCredentialStore()),
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

  test('SavedCredentials round-trips without a password', () {
    const value = SavedCredentials(username: '20260001');
    expect(SavedCredentials.decode(value.encode()).username, '20260001');
    expect(SavedCredentials.decode(value.encode()).password, isNull);
  });

  test('StudentIdentity extracts id and real name', () {
    final identity = StudentIdentity.fromText('学号：20260001\n姓名：张三');
    expect(identity.studentId, '20260001');
    expect(identity.displayName, '张三');
  });

  test('StudentIdentity falls back to an unlabeled 20-prefixed id', () {
    final identity = StudentIdentity.fromText('欢迎 20260001 同学');
    expect(identity.studentId, '20260001');
    expect(identity.displayName, isNull);
  });

  test('web login can authenticate without a typed username', () async {
    final credentials = _TestCredentialStore();
    final container = ProviderContainer(
      overrides: [
        sessionStoreProvider.overrideWithValue(_TestSessionStore()),
        credentialStoreProvider.overrideWithValue(credentials),
      ],
    );
    addTearDown(container.dispose);
    await Future<void>.delayed(const Duration(milliseconds: 20));

    await container
        .read(authControllerProvider.notifier)
        .loginWithCookies(
          result: const WebViewLoginResult(
            cookies: {'personal.neu.edu.cn': 'SESS_ID=abc'},
            studentId: '20260001',
            displayName: '测试同学',
          ),
          saveCredentials: true,
        );

    final state = container.read(authControllerProvider);
    expect(state, isA<AuthAuthenticated>());
    expect((state as AuthAuthenticated).session.studentId, '20260001');
    expect((state).session.displayName, '测试同学');
    expect(credentials.credentials?.username, '20260001');
    expect(credentials.credentials?.password, isNull);
  });
}
