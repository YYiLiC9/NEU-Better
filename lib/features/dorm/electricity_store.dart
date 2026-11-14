import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../core/electricity/electricity_models.dart';
import '../../core/storage/account_scope.dart';

/// Persists dorm electricity prefs (room code, threshold, last query) so the
/// app can check daily-once and show the last reading without re-entering the
/// room code. Files are scoped per account and stored in a persistent dir on
/// Android so they survive an overwrite install.
class ElectricityStore {
  const ElectricityStore();

  static const _fileName = 'electricity.json';

  List<File> get _primary => AccountScope.scopedFiles(_fileName);

  List<File> get _legacy => AccountScope.legacyFiles(_fileName);

  Future<DormPrefs> read() async {
    for (final file in _primary) {
      final prefs = await _tryRead(file);
      if (prefs != null) return prefs;
    }
    // 兼容旧版本未加账号后缀的文件：读到后迁移到当前账号文件。
    for (final file in _legacy) {
      final prefs = await _tryRead(file);
      if (prefs != null) {
        await save(prefs);
        return prefs;
      }
    }
    return const DormPrefs();
  }

  Future<DormPrefs?> _tryRead(File file) async {
    try {
      if (!await file.exists()) return null;
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is Map) {
        final prefs = DormPrefs.fromJson(Map<String, dynamic>.from(decoded));
        if (prefs.hasRoom || prefs.lastReading != null) return prefs;
      }
    } catch (error) {
      debugPrint('[elec] prefs read failed at ${file.path}: $error');
    }
    return null;
  }

  Future<void> save(DormPrefs prefs) async {
    final payload = jsonEncode(prefs.toJson());
    Object? lastError;
    for (final file in _primary) {
      try {
        await file.parent.create(recursive: true);
        await file.writeAsString(payload, flush: true);
        debugPrint('[elec] saved to ${file.path}');
        return;
      } catch (error) {
        lastError = error;
        debugPrint('[elec] save failed at ${file.path}: $error');
      }
    }
    if (lastError != null) {
      debugPrint('[elec] no writable path: $lastError');
    }
  }
}
