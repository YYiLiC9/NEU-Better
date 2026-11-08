import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'auth_session.dart';

abstract interface class SessionStore {
  Future<AuthSession?> read();

  Future<void> save(AuthSession session);

  Future<void> clear();
}

class SecureSessionStore implements SessionStore {
  const SecureSessionStore([this._storage = const FlutterSecureStorage()]);

  static const _sessionKey = 'neu_better.session.v1';

  final FlutterSecureStorage _storage;

  @override
  Future<AuthSession?> read() async {
    final raw = await _storage.read(key: _sessionKey);
    if (raw == null || raw.isEmpty) return null;
    try {
      return AuthSession.decode(raw);
    } on FormatException {
      await clear();
      return null;
    }
  }

  @override
  Future<void> save(AuthSession session) {
    return _storage.write(key: _sessionKey, value: session.encode());
  }

  @override
  Future<void> clear() {
    return _storage.delete(key: _sessionKey);
  }
}
