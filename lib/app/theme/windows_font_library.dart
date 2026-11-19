import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pointycastle/digests/sha256.dart';

import '../../core/settings/app_font.dart';
import '../../core/storage/account_scope.dart';

final windowsFontLibraryProvider = Provider<WindowsFontLibrary>(
  (ref) => WindowsFontLibrary(),
);

final importedFontFamilyProvider = FutureProvider.family<String, String>(
  (ref, id) => ref.watch(windowsFontLibraryProvider).load(id),
  retry: (count, error) => null,
);

class WindowsFontLibrary {
  WindowsFontLibrary({List<File> Function(String id)? files})
    : _files = files ?? _storedFiles;

  static const _window = MethodChannel('neu_better/window');
  static const _maxBytes = 64 * 1024 * 1024;
  final List<File> Function(String id) _files;
  final Map<String, Future<String>> _loads = {};

  static List<File> _storedFiles(String id) =>
      AccountScope.legacyFiles('fonts/$id.font');

  Future<ImportedAppFont?> pickAndImport() async {
    final path = await _window.invokeMethod<String>('pickFontFile');
    return path == null ? null : importFile(File(path));
  }

  Future<ImportedAppFont> importFile(File source) async {
    final name = source.uri.pathSegments.last;
    final lowerName = name.toLowerCase();
    if (!lowerName.endsWith('.ttf') && !lowerName.endsWith('.otf')) {
      throw const FormatException('请选择 .ttf 或 .otf 字体文件。');
    }
    final bytes = await _readFont(source);
    final id = _digest(bytes);
    for (final file in _files(id)) {
      try {
        if (await file.exists() && _digest(await _readFont(file)) == id) {
          return ImportedAppFont(id: id, name: name);
        }
      } on Exception {
        // Repair a missing or damaged copy below.
      }
      try {
        await file.parent.create(recursive: true);
        final scratch = await file.parent.createTemp('font-import-');
        final pending = File('${scratch.path}${Platform.pathSeparator}font');
        try {
          await pending.writeAsBytes(bytes, flush: true);
          await pending.rename(file.path);
        } finally {
          if (await pending.exists()) await pending.delete();
          await scratch.delete();
        }
        return ImportedAppFont(id: id, name: name);
      } on FileSystemException {
        // Try the next application data directory.
      }
    }
    throw const FileSystemException('无法保存字体文件。');
  }

  Future<String> load(String id) {
    if (!ImportedAppFont.isValidId(id)) {
      return Future.error(const FormatException('无效的字体编号。'));
    }
    return _loads.putIfAbsent(id, () async {
      try {
        final family = 'NEU Imported $id';
        for (final file in _files(id)) {
          final Uint8List bytes;
          try {
            bytes = await _readFont(file);
          } on Exception {
            continue;
          }
          if (_digest(bytes) != id) continue;
          final loader = FontLoader(family)
            ..addFont(Future.value(ByteData.sublistView(bytes)));
          await loader.load();
          return family;
        }
        throw const FileSystemException('找不到可用的字体副本。');
      } catch (_) {
        _loads.remove(id);
        rethrow;
      }
    });
  }

  static String _digest(Uint8List bytes) => SHA256Digest()
      .process(bytes)
      .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
      .join();

  static Future<Uint8List> _readFont(File file) async {
    final input = await file.open();
    try {
      final length = await input.length();
      if (length > _maxBytes) {
        throw const FormatException('字体文件不能超过 64 MiB。');
      }
      final bytes = await input.read(length);
      _validateFont(bytes);
      return bytes;
    } finally {
      await input.close();
    }
  }

  static void _validateFont(Uint8List bytes) {
    const invalid = FormatException('字体文件损坏或格式不受支持。');
    if (bytes.length < 12) throw invalid;
    final data = ByteData.sublistView(bytes);
    final signature = data.getUint32(0);
    const openType = 0x4f54544f; // OTTO
    if (signature != 0x00010000 &&
        signature != 0x74727565 &&
        signature != openType) {
      throw invalid;
    }
    final count = data.getUint16(4);
    final tableEnd = 12 + count * 16;
    if (count == 0 || tableEnd > bytes.length) throw invalid;
    final tables = <String>{};
    for (var entry = 12; entry < tableEnd; entry += 16) {
      final tag = String.fromCharCodes(bytes, entry, entry + 4);
      final offset = data.getUint32(entry + 8);
      final length = data.getUint32(entry + 12);
      if (offset < tableEnd || offset + length > bytes.length) throw invalid;
      if (length > 0) tables.add(tag);
    }
    final hasOutlines = signature == openType
        ? tables.contains('CFF ') || tables.contains('CFF2')
        : tables.containsAll(['glyf', 'loca']);
    if (!hasOutlines ||
        !tables.containsAll(['cmap', 'head', 'maxp', 'hhea', 'hmtx', 'name'])) {
      throw invalid;
    }
  }
}
