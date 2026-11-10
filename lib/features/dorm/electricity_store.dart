import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'electricity_models.dart';

/// Persists dorm electricity prefs (room code, threshold, last query) so the
/// app can check daily-once and show the last reading without re-entering the
/// room code. Same fallback-path strategy as [TimetableStore].
class ElectricityStore {
  const ElectricityStore();

  static const _fileName = 'electricity.json';

  List<File> get _candidates {
    final separator = Platform.pathSeparator;
    final files = <File>[
      File(
        '${File(Platform.resolvedExecutable).parent.path}$separator'
        'data$separator$_fileName',
      ),
      File(
        '${Directory.current.path}$separator'
        'data$separator$_fileName',
      ),
      File(
        '${Directory.systemTemp.path}$separator'
        'NEU Better$separator$_fileName',
      ),
    ];
    final local = Platform.environment['LOCALAPPDATA'];
    if (local != null && local.isNotEmpty) {
      files.add(File('$local$separator' 'NEU Better$separator$_fileName'));
    }
    return files;
  }

  Future<DormPrefs> read() async {
    for (final file in _candidates) {
      try {
        if (!await file.exists()) continue;
        final decoded = jsonDecode(await file.readAsString());
        if (decoded is Map) {
          return DormPrefs.fromJson(Map<String, dynamic>.from(decoded));
        }
      } catch (error) {
        debugPrint('[elec] prefs read failed at ${file.path}: $error');
      }
    }
    return const DormPrefs();
  }

  Future<void> save(DormPrefs prefs) async {
    final payload = jsonEncode(prefs.toJson());
    Object? lastError;
    for (final file in _candidates) {
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
