import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:win32/win32.dart';

/// A small DPAPI-encrypted text file used as a fallback on Windows.
///
/// The `flutter_secure_storage` plugin stores its JSON under
/// `getApplicationSupportDirectory()`, which some managed Windows accounts
/// (including the current test environment) cannot write to. This file uses
/// the same Windows DPAPI protection but lives next to the executable (or in
/// the repository `data/` folder during development), so it is writable for
/// the current user without requiring administrator privileges.
class WindowsDpapiFile {
  const WindowsDpapiFile(this.fileName);

  final String fileName;

  List<File> get _candidates {
    final separator = Platform.pathSeparator;
    final files = <File>[
      File(
        '${File(Platform.resolvedExecutable).parent.path}$separator'
        'data$separator$fileName',
      ),
      File(
        '${Directory.current.path}$separator'
        'data$separator$fileName',
      ),
      File(
        '${Directory.systemTemp.path}$separator'
        'NEU Better$separator$fileName',
      ),
    ];
    final local = Platform.environment['LOCALAPPDATA'];
    if (local != null && local.isNotEmpty) {
      files.add(File('$local$separator' 'NEU Better$separator$fileName'));
    }
    return files;
  }

  Future<String?> read() async {
    for (final file in _candidates) {
      try {
        if (!await file.exists()) continue;
        final encrypted = await file.readAsBytes();
        final plain = _unprotect(encrypted);
        return utf8.decode(plain);
      } catch (error) {
        debugPrint('[storage] file read failed at ${file.path}: $error');
      }
    }
    return null;
  }

  Future<void> save(String value) async {
    final encrypted = _protect(utf8.encode(value));
    Object? lastError;
    for (final file in _candidates) {
      try {
        await file.parent.create(recursive: true);
        await file.writeAsBytes(encrypted, flush: true);
        debugPrint('[storage] saved to ${file.path}');
        return;
      } catch (error) {
        lastError = error;
        debugPrint('[storage] file save failed at ${file.path}: $error');
      }
    }
    if (lastError != null) {
      debugPrint('[storage] no writable path: $lastError');
    }
  }

  Future<void> clear() async {
    for (final file in _candidates) {
      try {
        if (await file.exists()) await file.delete();
      } catch (error) {
        debugPrint('[storage] file clear failed at ${file.path}: $error');
      }
    }
  }

  Uint8List _protect(List<int> plainText) {
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

  Uint8List _unprotect(Uint8List encryptedText) {
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
