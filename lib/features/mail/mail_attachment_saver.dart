import 'dart:io';

import 'package:flutter/services.dart';

/// 附件保存：Android 走 `neu_better/files` 的 MediaStore.Downloads；
/// Windows 直接写入 `%USERPROFILE%\Downloads`（同名自动加 (1)）。
const MethodChannel _filesChannel = MethodChannel('neu_better/files');

/// 清洗文件名中的非法字符（Windows/Android 通用），并裁剪过长名称。
String sanitizeFileName(String input) {
  var name = input.trim();
  // 控制字符 + 路径/保留字符统一替换为下划线。
  name = name.replaceAll(RegExp(r'[\x00-\x1F\x7F]'), '');
  name = name.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_');
  name = name.replaceAll(RegExp(r'\s+'), ' ').trim();
  // 以点结尾在 Windows 上非法。
  name = name.replaceAll(RegExp(r'[. ]+$'), '');
  if (name.isEmpty) name = '附件';
  if (name.length > 150) {
    final dot = name.lastIndexOf('.');
    if (dot > 0 && name.length - dot <= 12) {
      final ext = name.substring(dot);
      name = '${name.substring(0, 150 - ext.length)}$ext';
    } else {
      name = name.substring(0, 150);
    }
  }
  return name;
}

/// 根据文件名后缀推断 MIME（Coremail 的 contentType 常是 text/plain，不可信）。
String mimeForFileName(String fileName, {String? declared}) {
  final dot = fileName.lastIndexOf('.');
  final ext = dot >= 0 ? fileName.substring(dot + 1).toLowerCase() : '';
  const map = <String, String>{
    'pdf': 'application/pdf',
    'doc': 'application/msword',
    'docx': 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    'xls': 'application/vnd.ms-excel',
    'xlsx': 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    'ppt': 'application/vnd.ms-powerpoint',
    'pptx': 'application/vnd.openxmlformats-officedocument.presentationml.presentation',
    'zip': 'application/zip',
    'rar': 'application/vnd.rar',
    '7z': 'application/x-7z-compressed',
    'txt': 'text/plain',
    'csv': 'text/csv',
    'png': 'image/png',
    'jpg': 'image/jpeg',
    'jpeg': 'image/jpeg',
    'gif': 'image/gif',
    'webp': 'image/webp',
    'mp3': 'audio/mpeg',
    'mp4': 'video/mp4',
    'ofd': 'application/ofd',
  };
  final known = map[ext];
  if (known != null) return known;
  if (declared != null &&
      declared.isNotEmpty &&
      !declared.toLowerCase().startsWith('text/plain')) {
    return declared;
  }
  return 'application/octet-stream';
}

/// 保存附件到系统下载目录，返回最终绝对路径。
/// [windowsDownloadsDir] 仅用于测试时重定向 Windows 下载目录。
Future<String> saveAttachmentToDownloads({
  required String fileName,
  required Uint8List bytes,
  String? mimeType,
  Directory? windowsDownloadsDir,
}) => saveAttachmentStreamToDownloads(
  fileName: fileName,
  chunks: Stream.value(bytes),
  mimeType: mimeType,
  windowsDownloadsDir: windowsDownloadsDir,
);

Future<String> saveAttachmentStreamToDownloads({
  required String fileName,
  required Stream<List<int>> chunks,
  String? mimeType,
  Directory? windowsDownloadsDir,
}) async {
  final safeName = sanitizeFileName(fileName);
  final targetDir = windowsDownloadsDir ?? _downloadDirectory();
  await targetDir.create(recursive: true);
  final scratch = await targetDir.createTemp('.neu-attachment-');
  final temporary = File('${scratch.path}${Platform.pathSeparator}attachment');
  try {
    final output = await temporary.open(mode: FileMode.writeOnly);
    try {
      await for (final chunk in chunks) {
        await output.writeFrom(chunk);
      }
      await output.flush();
    } finally {
      await output.close();
    }
    if (Platform.isAndroid && windowsDownloadsDir == null) {
      final result = await _filesChannel.invokeMethod<String>(
        'publishAttachment',
        {
          'fileName': safeName,
          'mime': mimeForFileName(safeName, declared: mimeType),
          'path': temporary.path,
        },
      );
      if (result == null || result.isEmpty) {
        throw const MailAttachmentSaveException('无法保存到系统下载目录');
      }
      return result;
    }
    final destination = await _reserveDestination(targetDir, safeName);
    try {
      return (await temporary.rename(destination.path)).path;
    } catch (_) {
      await destination.delete();
      rethrow;
    }
  } finally {
    if (await temporary.exists()) await temporary.delete();
    await scratch.delete();
  }
}

Directory _downloadDirectory() {
  if (!Platform.isWindows) return Directory.systemTemp;
  final home =
      Platform.environment['USERPROFILE'] ?? Platform.environment['HOME'];
  if (home == null || home.isEmpty) {
    throw const MailAttachmentSaveException('找不到用户下载目录');
  }
  return Directory('$home\\Downloads');
}

Future<File> _reserveDestination(Directory directory, String name) async {
  final dot = name.lastIndexOf('.');
  for (var index = 0; ; index++) {
    final candidate = index == 0
        ? name
        : dot > 0
        ? '${name.substring(0, dot)}($index)${name.substring(dot)}'
        : '$name($index)';
    final destination = File(
      '${directory.path}${Platform.pathSeparator}$candidate',
    );
    try {
      return await destination.create(exclusive: true);
    } on PathExistsException {
      // Another download reserved this name.
    }
  }
}

class MailAttachmentSaveException implements Exception {
  const MailAttachmentSaveException(this.message);

  final String message;

  @override
  String toString() => message;
}
