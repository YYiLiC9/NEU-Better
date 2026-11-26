import 'package:flutter/foundation.dart';

import '../../core/auth/auth_session.dart';
import '../../core/auth/credential_store.dart';
import '../../core/network/ecode_client.dart';
import '../../core/network/in_flight_request.dart';

/// Retains only a valid QR code and shares an active fetch with the page.
class EcodeFeed {
  EcodeFeed(
    this.session, {
    required this.credentials,
    EcodeClient? client,
    EcodeCookieStore? cookieStore,
  }) : _client = client ?? EcodeClient(),
       _cookieStore =
           cookieStore ?? EcodeCookieStore(studentId: session.studentId);

  final AuthSession session;
  final CredentialStore credentials;
  final EcodeClient _client;
  final EcodeCookieStore _cookieStore;
  final _request = InFlightRequest<EcodeQr>();
  EcodeQr? _cached;
  bool _disposed = false;

  EcodeQr? get current {
    final qr = _cached;
    return qr != null && DateTime.now().isBefore(qr.invalidTime) ? qr : null;
  }

  Future<EcodeQr> fetch({bool preferCached = false}) {
    final qr = current;
    if (preferCached && qr != null) return Future.value(qr);
    return _request.run(() async {
      _checkCurrent();
      final qr = await _fetchWithRetry();
      _checkCurrent();
      return _cached = qr;
    });
  }

  void dispose() {
    _disposed = true;
    _cached = null;
  }

  void _checkCurrent() {
    if (_disposed) throw StateError('The ecode session has ended');
  }

  Future<String> _ensureCookie({bool forceCredentials = false}) async {
    if (!forceCredentials) {
      final cached = await _cookieStore.read();
      if (cached != null) return cached;
    }
    String? cookie;
    final pass = passCookieOf(session);
    if (!forceCredentials && pass.isNotEmpty) {
      try {
        cookie = await _client.loginWithPassCookie(pass);
        debugPrint('[ecode-native] pass-cookie login ok');
      } catch (error) {
        debugPrint('[ecode-native] pass-cookie login failed: $error');
      }
    }
    if (cookie == null) {
      final saved = await credentials.read();
      final password = saved?.password;
      final hasSaved = saved != null &&
          saved.username.trim() == session.studentId.trim() &&
          password != null &&
          password.isNotEmpty &&
          saved.username.trim().isNotEmpty;
      debugPrint(
        '[ecode-native] credential login path: '
        'saved=${saved != null}, match=$hasSaved, '
        'hasPass=${pass.isNotEmpty}',
      );
      if (hasSaved) {
        cookie = await _client.login(
          username: saved.username.trim(),
          password: password,
        );
      }
    }
    if (cookie == null) {
      throw const EcodeAuthException('无法自动登录 e码通，请先在设置里保存账号密码或重新登录');
    }
    _checkCurrent();
    await _cookieStore.save(cookie);
    return cookie;
  }

  Future<EcodeQr> _fetchAndSave(String cookie) async {
    final qr = await _client.fetchQr(cookie);
    if (qr.refreshedCookie != null) {
      await _cookieStore.save(qr.refreshedCookie!);
    }
    return qr;
  }

  Future<EcodeQr> _fetchWithRetry() async {
    final cookie = await _ensureCookie();
    try {
      return await _fetchAndSave(cookie);
    } on EcodeAuthException {
      // 只有明确的认证失效才清 Cookie 并重新登录。
      _checkCurrent();
      await _cookieStore.clear();
      try {
        final freshCookie = await _ensureCookie();
        return await _fetchAndSave(freshCookie);
      } on EcodeAuthException {
        // pass cookie 换到的 ecode 会话仍被拒时，强制走保存的账号密码再试一次。
        _checkCurrent();
        await _cookieStore.clear();
        final credentialCookie = await _ensureCookie(forceCredentials: true);
        return _fetchAndSave(credentialCookie);
      }
    }
  }
}
