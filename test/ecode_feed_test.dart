import 'package:flutter_test/flutter_test.dart';

import 'package:neu_better_pro/core/auth/auth_session.dart';
import 'package:neu_better_pro/core/auth/credential_store.dart';
import 'package:neu_better_pro/core/auth/saved_credentials.dart';
import 'package:neu_better_pro/core/network/ecode_client.dart';
import 'package:neu_better_pro/features/ecode/ecode_feed.dart';

class _FakeCredentialStore implements CredentialStore {
  SavedCredentials? value;

  @override
  Future<SavedCredentials?> read() async => value;

  @override
  Future<void> save(SavedCredentials credentials) async {
    value = credentials;
  }

  @override
  Future<void> clear() async {
    value = null;
  }
}

class _FakeCookieStore extends EcodeCookieStore {
  _FakeCookieStore(this.value) : super(studentId: '20225767');

  String? value;

  @override
  Future<String?> read() async => value;

  @override
  Future<void> save(String cookie) async {
    value = cookie;
  }

  @override
  Future<void> clear() async {
    value = null;
  }
}

class _FakeEcodeClient extends EcodeClient {
  _FakeEcodeClient(this.fetch);

  final Future<EcodeQr> Function(String cookie) fetch;
  int fetchCount = 0;
  int passLoginCount = 0;

  @override
  Future<String> loginWithPassCookie(String passCookies) async {
    passLoginCount++;
    return 'pass=$passCookies';
  }

  @override
  Future<EcodeQr> fetchQr(String cookie) {
    fetchCount++;
    return fetch(cookie);
  }
}

EcodeQr _qr({String? refreshedCookie}) => EcodeQr(
  code: 'NEU-TEST',
  createTime: DateTime.now(),
  invalidTime: DateTime.now().add(const Duration(minutes: 1)),
  refreshedCookie: refreshedCookie,
);

AuthSession _session() => AuthSession(
  studentId: '20225767',
  cookies: const {'pass.neu.edu.cn': 'CASTGC=test'},
  createdAt: DateTime.now(),
);

void main() {
  test('transient failure never clears cookie or re-logs in', () async {
    final cookieStore = _FakeCookieStore('old-session');
    final client = _FakeEcodeClient(
      (_) async => throw const EcodeTransientException('HTTP 502'),
    );
    final feed = EcodeFeed(
      _session(),
      credentials: _FakeCredentialStore(),
      client: client,
      cookieStore: cookieStore,
    );

    await expectLater(
      feed.fetch(),
      throwsA(isA<EcodeTransientException>()),
    );
    expect(client.passLoginCount, 0);
    expect(cookieStore.value, 'old-session');
  });

  test('auth failure clears cookie and retries once with pass cookie', () async {
    final cookieStore = _FakeCookieStore('old-session');
    var first = true;
    final client = _FakeEcodeClient((cookie) async {
      if (first) {
        first = false;
        throw const EcodeAuthException('session expired');
      }
      return _qr(refreshedCookie: 'new-session');
    });
    final feed = EcodeFeed(
      _session(),
      credentials: _FakeCredentialStore(),
      client: client,
      cookieStore: cookieStore,
    );

    final qr = await feed.fetch();
    expect(qr.code, 'NEU-TEST');
    expect(client.passLoginCount, 1);
    expect(cookieStore.value, 'new-session');
  });

  test('missing pass cookie and password gives auth error', () async {
    final cookieStore = _FakeCookieStore(null);
    final client = _FakeEcodeClient((_) async => _qr());
    final feed = EcodeFeed(
      AuthSession(
        studentId: '20225767',
        cookies: const {},
        createdAt: DateTime.now(),
      ),
      credentials: _FakeCredentialStore(),
      client: client,
      cookieStore: cookieStore,
    );

    await expectLater(feed.fetch(), throwsA(isA<EcodeAuthException>()));
    expect(client.fetchCount, 0);
  });
}
