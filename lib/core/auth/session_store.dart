import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../storage/windows_dpapi_file.dart';
import 'auth_session.dart';

abstract interface class SessionStore {
  Future<AuthSession?> read();

  Future<void> save(AuthSession session);

  Future<void> clear();
}

class SecureSessionStore implements SessionStore {
  const SecureSessionStore([this._storage = const FlutterSecureStorage()]);

  static const _sessionKey = 'neu_better.session.v1';
  static const _fallback = WindowsDpapiFile('session.dat');

  final FlutterSecureStorage _storage;

  @override
  Future<AuthSession?> read() async {
    // Prefer the DPAPI fallback on Windows; the plugin's AppData location is
    // not writable for some managed accounts.
    if (Platform.isWindows) {
      final fallback = await _fallback.read();
      if (fallback != null && fallback.isNotEmpty) {
        try {
          return AuthSession.decode(fallback);
        } on FormatException {
          await _fallback.clear();
        }
      }
      return null;
    }

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
  Future<void> save(AuthSession session) async {
    if (Platform.isWindows) {
      await _fallback.save(session.encode());
      return;
    }
    await _storage.write(key: _sessionKey, value: session.encode());
  }

  @override
  Future<void> clear() async {
    if (Platform.isWindows) {
      await _fallback.clear();
      return;
    }
    await _storage.delete(key: _sessionKey);
  }
}
