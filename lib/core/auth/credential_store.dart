import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'saved_credentials.dart';

/// Small abstraction around the platform secure store.
///
/// Reads and writes are bounded by a short timeout: on a few locked-down
/// Windows accounts the underlying plugin can block on an ACL error. A failed
/// credentials read must never prevent the login page from being usable.
abstract interface class CredentialStore {
  Future<SavedCredentials?> read();
  Future<void> save(SavedCredentials credentials);
  Future<void> clear();
}

class SecureCredentialStore implements CredentialStore {
  const SecureCredentialStore();

  static const _storage = FlutterSecureStorage();
  static const _key = 'neu_better.credentials.v1';
  static const _timeout = Duration(seconds: 3);

  @override
  Future<SavedCredentials?> read() async {
    try {
      final value = await _storage.read(key: _key).timeout(_timeout);
      if (value == null || value.isEmpty) return null;
      return SavedCredentials.decode(value);
    } catch (error) {
      debugPrint('[credentials] read failed: $error');
      return null;
    }
  }

  @override
  Future<void> save(SavedCredentials credentials) async {
    try {
      await _storage
          .write(key: _key, value: credentials.encode())
          .timeout(_timeout);
    } catch (error) {
      debugPrint('[credentials] save failed: $error');
    }
  }

  @override
  Future<void> clear() async {
    try {
      await _storage.delete(key: _key).timeout(_timeout);
    } catch (error) {
      debugPrint('[credentials] clear failed: $error');
    }
  }
}

final credentialStoreProvider = Provider<CredentialStore>((ref) {
  return const SecureCredentialStore();
});
