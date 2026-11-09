import 'dart:convert';
import 'dart:io';

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
import 'package:neu_better_pro/core/network/neu_cas_client.dart';
import 'package:neu_better_pro/core/network/portal_identity_client.dart';
import 'package:neu_better_pro/features/auth/auth_controller.dart';
import 'package:neu_better_pro/features/timetable/timetable_import.dart';

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

class _TestPortalIdentityClient implements PortalIdentityClient {
  _TestPortalIdentityClient(this.identity);

  final StudentIdentity? identity;

  @override
  Future<StudentIdentity?> fetch(Map<String, String> cookies) async => identity;
}

class _TestCasClient implements CasClient {
  @override
  Future<CasLoginResult> login({
    required String username,
    required String password,
  }) async {
    return CasLoginResult(
      cookies: {'personal.neu.edu.cn': 'SESS_ID=abc'},
      finalUri: Uri.parse('https://personal.neu.edu.cn/portal'),
    );
  }
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

    expect(find.text('我的课表'), findsOneWidget);
    expect(find.text('2026–2027 秋季学期 · 第 8 周'), findsOneWidget);
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
    const value = SavedCredentials(
      username: '20260001',
      displayName: '张三',
    );
    final restored = SavedCredentials.decode(value.encode());
    expect(restored.username, '20260001');
    expect(restored.password, isNull);
    expect(restored.displayName, '张三');
  });

  test('StudentIdentity extracts id and real name', () {
    final identity = StudentIdentity.fromText('学号：20260001\n姓名：张三');
    expect(identity.studentId, '20260001');
    expect(identity.displayName, '张三');
  });

  test('StudentIdentity ignores bare dates and course codes', () {
    final identity = StudentIdentity.fromText('2025-09-01 课程 20250001');
    expect(identity.studentId, isNull);
    expect(identity.displayName, isNull);
  });

  test('StudentIdentity reads structured portal userInfo', () {
    final identity = StudentIdentity.fromUserInfo({
      'user_number': '20260001',
      'user_name': '张三',
      'user_depart': '信息科学与工程学院',
    });
    expect(identity.studentId, '20260001');
    expect(identity.displayName, '张三');
    expect(identity.hasStudentId, isTrue);
  });

  test('StudentIdentity rejects a date as a student id', () {
    final identity = StudentIdentity.fromUserInfo({
      'user_number': '2025-09-01',
      'user_name': '张三',
    });
    expect(identity.studentId, isNull);
    expect(identity.displayName, '张三');
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

  test('web login refreshes missing identity from the portal', () async {
    final credentials = _TestCredentialStore();
    final forceRefresh = _TestPortalIdentityClient(
      const StudentIdentity(studentId: '20260001', displayName: '张三'),
    );
    final container = ProviderContainer(
      overrides: [
        sessionStoreProvider.overrideWithValue(_TestSessionStore()),
        credentialStoreProvider.overrideWithValue(credentials),
        portalIdentityClientProvider.overrideWithValue(forceRefresh),
      ],
    );
    addTearDown(container.dispose);
    await Future<void>.delayed(const Duration(milliseconds: 20));

    await container
        .read(authControllerProvider.notifier)
        .loginWithCookies(
          result: const WebViewLoginResult(
            cookies: {'personal.neu.edu.cn': 'SESS_ID=abc'},
            studentId: '',
            displayName: '',
          ),
          saveCredentials: true,
        );

    // The shell must become authenticated immediately, before the portal
    // identity lookup or secure-storage write completes.
    final immediate = container.read(authControllerProvider);
    expect(immediate, isA<AuthAuthenticated>());

    await Future<void>.delayed(const Duration(milliseconds: 50));
    final refreshed = container.read(authControllerProvider);
    expect(refreshed, isA<AuthAuthenticated>());
    final session = (refreshed as AuthAuthenticated).session;
    expect(session.studentId, '20260001');
    expect(session.displayName, '张三');
    expect(session.accountLabel, '张三');
    expect(credentials.credentials?.username, '20260001');
  });

  test('saved credentials auto-login on cold start', () async {
    final credentials = _TestCredentialStore(
      const SavedCredentials(
        username: '20260001',
        password: 'saved-password',
      ),
    );
    final identity = _TestPortalIdentityClient(
      const StudentIdentity(studentId: '20260001', displayName: '张三'),
    );
    final container = ProviderContainer(
      overrides: [
        sessionStoreProvider.overrideWithValue(_TestSessionStore()),
        credentialStoreProvider.overrideWithValue(credentials),
        casClientProvider.overrideWithValue(_TestCasClient()),
        portalIdentityClientProvider.overrideWithValue(identity),
      ],
    );
    addTearDown(container.dispose);
    container.read(authControllerProvider);

    await Future<void>.delayed(const Duration(milliseconds: 120));
    final state = container.read(authControllerProvider);
    expect(state, isA<AuthAuthenticated>());
    expect((state as AuthAuthenticated).session.studentId, '20260001');
    expect(state.session.displayName, '张三');
  });

  test('native login refreshes the real name from the portal', () async {
    final credentials = _TestCredentialStore();
    final identity = _TestPortalIdentityClient(
      const StudentIdentity(studentId: '20260001', displayName: '张三'),
    );
    final container = ProviderContainer(
      overrides: [
        sessionStoreProvider.overrideWithValue(_TestSessionStore()),
        credentialStoreProvider.overrideWithValue(credentials),
        casClientProvider.overrideWithValue(_TestCasClient()),
        portalIdentityClientProvider.overrideWithValue(identity),
      ],
    );
    addTearDown(container.dispose);
    await Future<void>.delayed(const Duration(milliseconds: 20));

    await container
        .read(authControllerProvider.notifier)
        .login(
          username: '20260001',
          password: 'pw',
          saveCredentials: true,
        );

    final immediate = container.read(authControllerProvider);
    expect(immediate, isA<AuthAuthenticated>());
    expect((immediate as AuthAuthenticated).session.studentId, '20260001');

    await Future<void>.delayed(const Duration(milliseconds: 50));
    final refreshed = container.read(authControllerProvider);
    expect(refreshed, isA<AuthAuthenticated>());
    final session = (refreshed as AuthAuthenticated).session;
    expect(session.displayName, '张三');
    expect(session.accountLabel, '张三');
    expect(credentials.credentials?.username, '20260001');
    expect(credentials.credentials?.password, 'pw');
  });

  test(
    'secure credential store round-trips on Windows',
    () async {
      final store = SecureCredentialStore();
      const credentials = SavedCredentials(
        username: '20260001',
        password: 'probe-password',
      );
      await store.clear();
      await store.save(credentials);
      final loaded = await store.read();
      expect(loaded?.username, credentials.username);
      expect(loaded?.password, credentials.password);
      await store.clear();
    },
    skip: !Platform.isWindows,
  );

  test('parses yjsxk weeks and course rows', () {
    final data = YjsxkTimetableParser.parse(
      jsonEncode({
        'results': [
          {
            'WID': 'w1',
            'BJDM': 'b1',
            'BJMC': '计算机硕 1 班',
            'KCMC': '机器学习',
            'JSXM': '李老师',
            'JASMC': '浑南 2-305',
            'ZCMC': '1-8,10-16周',
            'XQ': '2',
            'KSJCDM': '3',
            'JSJCDM': '4',
          },
        ],
        'xkjgList': [
          {'XNXQMC': '2026-2027 秋季学期'},
        ],
      }),
    );

    expect(data.isSample, isFalse);
    expect(data.totalWeeks, 16);
    expect(data.sessions.single.name, '机器学习');
    expect(data.sessions.single.day, 2);
    expect(data.sessions.single.startPeriod, 3);
    expect(data.sessions.single.weeks.contains(9), isFalse);
    expect(data.sessions.single.weeks.contains(10), isTrue);
  });

  test('timetable week parser handles single and ranged weeks', () {
    expect(YjsxkTimetableParser.parseWeeks('第1-4周'), {1, 2, 3, 4});
    expect(YjsxkTimetableParser.parseWeeks('2,6,8-9周'), {2, 6, 8, 9});
  });
}
