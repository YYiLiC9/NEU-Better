import 'package:flutter/foundation.dart';

import '../../core/auth/auth_session.dart';
import '../../core/auth/credential_store.dart';
import '../../core/network/ecode_client.dart';
import '../../core/network/in_flight_request.dart';

/// Retains only a valid QR code and shares an active fetch with the page.
class EcodeFeed {
  EcodeFeed(this.session, {required this.credentials})
    : _cookieStore = EcodeCookieStore(studentId: session.studentId);

  final AuthSession session;
  final CredentialStore credentials;
  final _client = EcodeClient();
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

  Future<String> _ensureCookie() async {
    final cached = await _cookieStore.read();
    if (cached != null) return cached;
    String? cookie;
    final pass = passCookieOf(session);
    if (pass.isNotEmpty) {
      try {
        cookie = await _client.loginWithPassCookie(pass);
      } catch (error) {
        debugPrint('[ecode-native] pass-cookie login failed: $error');
      }
    }
    if (cookie == null) {
      final saved = await credentials.read();
      final password = saved?.password;
      if (saved != null &&
          saved.username.trim() == session.studentId.trim() &&
          password != null &&
          password.isNotEmpty &&
          saved.username.trim().isNotEmpty) {
        cookie = await _client.login(
          username: saved.username.trim(),
          password: password,
        );
      }
    }
    if (cookie == null) {
      throw const EcodeException('无法自动登录 e码通，请先在设置里保存账号密码或重新登录');
    }
    _checkCurrent();
    await _cookieStore.save(cookie);
    return cookie;
  }

  Future<EcodeQr> _fetchWithRetry() async {
    try {
      final cookie = await _ensureCookie();
      return await _client.fetchQr(cookie);
    } on EcodeException {
      _checkCurrent();
      await _cookieStore.clear();
      final cookie = await _ensureCookie();
      return _client.fetchQr(cookie);
    }
  }
}
