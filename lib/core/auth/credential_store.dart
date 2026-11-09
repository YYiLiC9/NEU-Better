import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:win32/win32.dart';

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
    // Prefer the fallback first on Windows: it is a single encrypted file
    // read, while the plugin's AppData path can block for the full timeout
    // on locked-down accounts.
    if (Platform.isWindows) {
      return _WindowsDpapiCredentialFile.read();
    }

    try {
      final value = await _storage.read(key: _key).timeout(_timeout);
      if (value != null && value.isNotEmpty) {
        return SavedCredentials.decode(value);
      }
    } catch (error) {
      debugPrint('[credentials] secure read failed: $error');
    }

    return null;
  }

  @override
  Future<void> save(SavedCredentials credentials) async {
    // Write the DPAPI file first; this is the path that works even when the
    // Windows plugin cannot create its AppData JSON file.
    if (Platform.isWindows) {
      await _WindowsDpapiCredentialFile.save(credentials);
      return;
    }

    await _storage.write(key: _key, value: credentials.encode()).timeout(
          _timeout,
        );
  }

  @override
  Future<void> clear() async {
    if (Platform.isWindows) {
      await _WindowsDpapiCredentialFile.clear();
      return;
    }
    await _storage.delete(key: _key).timeout(_timeout);
  }
}

/// DPAPI-encrypted fallback for Windows accounts where `path_provider`'s
/// application-support directory is not writable.
class _WindowsDpapiCredentialFile {
  static const _fileName = 'credentials.dat';

  /// Candidate locations, most reliable first. The app may be launched from a
  /// shortcut with an arbitrary working directory, so never rely on a single
  /// location.
  static List<File> get _candidates {
    final files = <File>[
      // The portable release folder is writable for the current user and is
      // where the shortcut starts the app. Prefer it over %TEMP%, which can
      // be blocked by AppData ACLs on managed Windows machines.
      File(
        '${File(Platform.resolvedExecutable).parent.path}'
        '${Platform.pathSeparator}data${Platform.pathSeparator}$_fileName',
      ),
      File(
        '${Directory.current.path}${Platform.pathSeparator}data'
        '${Platform.pathSeparator}$_fileName',
      ),
      File(
        '${Directory.systemTemp.path}${Platform.pathSeparator}NEU Better'
        '${Platform.pathSeparator}$_fileName',
      ),
    ];
    final local = Platform.environment['LOCALAPPDATA'];
    if (local != null && local.isNotEmpty) {
      files.add(
        File(
          '$local${Platform.pathSeparator}NEU Better'
          '${Platform.pathSeparator}$_fileName',
        ),
      );
    }
    return files;
  }

  static Future<SavedCredentials?> read() async {
    for (final file in _candidates) {
      try {
        if (!await file.exists()) continue;
        final encrypted = await file.readAsBytes();
        final plain = _unprotect(encrypted);
        final credentials = SavedCredentials.decode(utf8.decode(plain));
        if (credentials.username.isNotEmpty) return credentials;
      } catch (error) {
        debugPrint('[credentials] file read failed at ${file.path}: $error');
      }
    }
    return null;
  }

  static Future<void> save(SavedCredentials credentials) async {
    final encrypted = _protect(utf8.encode(credentials.encode()));
    Object? lastError;
    for (final file in _candidates) {
      try {
        await file.parent.create(recursive: true);
        await file.writeAsBytes(encrypted, flush: true);
        debugPrint('[credentials] saved to ${file.path}');
        return;
      } catch (error) {
        lastError = error;
        debugPrint('[credentials] file save failed at ${file.path}: $error');
      }
    }
    if (lastError != null) {
      debugPrint('[credentials] no writable credential path: $lastError');
    }
  }

  static Future<void> clear() async {
    for (final file in _candidates) {
      try {
        if (await file.exists()) await file.delete();
      } catch (error) {
        debugPrint('[credentials] file clear failed at ${file.path}: $error');
      }
    }
  }

  static Uint8List _protect(List<int> plainText) {
    return using((alloc) {
      final pPlainText = alloc<Uint8>(plainText.length);
      pPlainText.asTypedList(plainText.length).setAll(0, plainText);

      final plainTextBlob =
          alloc.allocate<CRYPT_INTEGER_BLOB>(sizeOf<CRYPT_INTEGER_BLOB>());
      plainTextBlob.ref.cbData = plainText.length;
      plainTextBlob.ref.pbData = pPlainText;

      final encryptedTextBlob =
          alloc.allocate<CRYPT_INTEGER_BLOB>(sizeOf<CRYPT_INTEGER_BLOB>());
      final result = CryptProtectData(
        plainTextBlob,
        null,
        null,
        null,
        0,
        encryptedTextBlob,
      );
      if (!result.value) {
        throw WindowsException(
          result.error.toHRESULT(),
          message: 'CryptProtectData failed',
        );
      }

      try {
        return Uint8List.fromList(
          encryptedTextBlob.ref.pbData
              .asTypedList(encryptedTextBlob.ref.cbData),
        );
      } finally {
        if (encryptedTextBlob.ref.pbData.address != NULL) {
          LocalFree(HLOCAL(encryptedTextBlob.ref.pbData.cast()));
        }
      }
    });
  }

  static Uint8List _unprotect(Uint8List encryptedText) {
    return using((alloc) {
      final pEncryptedText = alloc<Uint8>(encryptedText.length);
      pEncryptedText.asTypedList(encryptedText.length).setAll(0, encryptedText);

      final encryptedTextBlob =
          alloc.allocate<CRYPT_INTEGER_BLOB>(sizeOf<CRYPT_INTEGER_BLOB>());
      encryptedTextBlob.ref.cbData = encryptedText.length;
      encryptedTextBlob.ref.pbData = pEncryptedText;

      final plainTextBlob =
          alloc.allocate<CRYPT_INTEGER_BLOB>(sizeOf<CRYPT_INTEGER_BLOB>());
      final result = CryptUnprotectData(
        encryptedTextBlob,
        null,
        null,
        null,
        0,
        plainTextBlob,
      );
      if (!result.value) {
        throw WindowsException(
          result.error.toHRESULT(),
          message: 'CryptUnprotectData failed',
        );
      }

      try {
        return Uint8List.fromList(
          plainTextBlob.ref.pbData.asTypedList(plainTextBlob.ref.cbData),
        );
      } finally {
        if (plainTextBlob.ref.pbData.address != NULL) {
          LocalFree(HLOCAL(plainTextBlob.ref.pbData.cast()));
        }
      }
    });
  }
}

final credentialStoreProvider = Provider<CredentialStore>((ref) {
  return const SecureCredentialStore();
});
