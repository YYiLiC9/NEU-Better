import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

/// 一次可用的更新信息（来自 GitHub Release）。
class UpdateInfo {
  const UpdateInfo({
    required this.version,
    required this.tagName,
    required this.notes,
    required this.pageUrl,
    this.windowsUrl,
    this.androidUrl,
    this.windowsSize,
    this.windowsFileName,
    this.androidSize,
  });

  /// 纯版本号，如 `0.2.0`（已去掉前缀 v 与 +build）。
  final String version;

  /// 原始 tag，如 `v0.2.0`。
  final String tagName;
  final String notes;
  final String pageUrl;

  /// Windows 安装包（zip）下载地址；无则 null。
  final String? windowsUrl;

  /// Android 安装包（apk）下载地址；无则 null。
  final String? androidUrl;

  /// 安装包字节大小（用于校验已下载文件是否完整）；未知为 null。
  final int? windowsSize;

  /// Windows 安装包真实文件名（setup.exe 或旧版 zip）；用于下载到对应扩展名。
  final String? windowsFileName;
  final int? androidSize;

  bool get hasAnyAsset => windowsUrl != null || androidUrl != null;

  /// 安装包下载目录（设置页展示、断点续传都基于它）。
  ///
  /// Android：`Directory.systemTemp` 实际指向 code_cache，而 FileProvider 的
  /// `<cache-path>` 只覆盖 cache/；下载到 code_cache 会导致安装时报
  /// "Failed to find configured root that contains .../code_cache/..."。
  /// 因此 Android 统一放到 cache/neu_better_updates（与 file_paths 的
  /// `<cache-path>` 匹配），Windows 仍用系统临时目录。
  static Directory downloadDirectory({required bool android}) {
    final sep = Platform.pathSeparator;
    final base = android
        ? '${Directory.systemTemp.parent.path}${sep}cache$sep'
              'neu_better_updates'
        : '${Directory.systemTemp.path}${sep}neu_better_updates';
    return Directory(base);
  }

  /// 存放已下载安装包的稳定路径（按版本命名，便于命中复用）。
  static File packageFile(
    String version, {
    required bool android,
    String? windowsFileName,
  }) {
    final sep = Platform.pathSeparator;
    final String name;
    if (android) {
      name = 'NEU-Better-$version.apk';
    } else if (windowsFileName != null && windowsFileName.isNotEmpty) {
      name = windowsFileName;
    } else {
      name = 'NEU-Better-$version-windows-x64-setup.exe';
    }
    return File('${downloadDirectory(android: android).path}$sep$name');
  }

  /// 判断本地安装包是否完整可用：[expected] 已知时按字节数比对，否则按扩展名
  /// 宽松校验（.exe 需 MZ 头，.zip/.apk 需 PK 头）。
  static bool isCompletePackage(File file, int? expected) {
    try {
      if (!file.existsSync()) return false;
      final length = file.lengthSync();
      if (expected != null && expected > 0) {
        return length == expected;
      }
      if (length < 1024 * 1024) return false;
      final raf = file.openSync();
      final head = raf.readSync(2);
      raf.closeSync();
      if (head.length != 2) return false;
      final isExe = file.path.toLowerCase().endsWith('.exe');
      if (isExe) {
        // PE 可执行文件（安装程序）以 "MZ" 开头。
        return head[0] == 0x4D && head[1] == 0x5A;
      }
      return head[0] == 0x50 && head[1] == 0x4B;
    } catch (_) {
      return false;
    }
  }
}

/// 检查并下载 GitHub Release 更新。
///
/// 仓库公开，走 GitHub REST API（未认证限流约 60 次/小时，足够启动时检查）。
class UpdateService {
  UpdateService({Dio? dio})
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              baseUrl: 'https://api.github.com',
              connectTimeout: const Duration(seconds: 15),
              receiveTimeout: const Duration(seconds: 20),
              responseType: ResponseType.plain,
              headers: {
                'Accept': 'application/vnd.github+json',
                'User-Agent': 'NEU-Better-Updater',
              },
            ),
          );

  final Dio _dio;

  static const String repo = 'YYiLiC9/NEU-Better';

  /// 当前应用版本（与 pubspec 的 version 保持一致，发布新版本时同步更新）。
  static const String currentVersion = '0.4.1';

  /// 返回比当前版本更新的 Release；已是最新或网络异常时返回 null。
  Future<UpdateInfo?> check() async {
    for (final url in _githubCandidates(
      'https://api.github.com/repos/$repo/releases/latest',
    )) {
      try {
        final response = await _dio.get<String>(url);
        if (response.statusCode != 200 || response.data == null) continue;
        final decoded = jsonDecode(response.data!);
        if (decoded is! Map) continue;
        final info = UpdateInfoParser.fromRelease(
          Map<String, dynamic>.from(decoded),
        );
        if (info == null) continue;
        if (compareVersions(info.version, currentVersion) <= 0) return null;
        return info;
      } catch (error) {
        debugPrint('[update] check failed at $url: $error');
      }
    }
    return null;
  }

  /// GitHub 直连在部分地区不稳定：追加公共镜像前缀作为兜底（按顺序尝试）。
  static List<String> _githubCandidates(String url) {
    final list = <String>[url];
    if (url.contains('github.com') || url.contains('githubusercontent.com')) {
      list.add('https://ghfast.top/$url');
      list.add('https://gh-proxy.com/$url');
    }
    return list;
  }

  /// 下载 [url] 到 [target]，支持断点续传：已存在部分文件时用 HTTP Range
  /// 从已有字节处继续；若服务器忽略 Range（返回 200）则从头覆盖。
  ///
  /// 进程中断后 [target] 会保留半包，下次启动再次调用即可续传；下载完整
  /// 与否由调用方用 [UpdateInfo.isCompletePackage] 校验。
  Future<void> download(
    String url,
    File target, {
    void Function(int received, int total)? onProgress,
    int? expectedSize,
    Dio? dio,
  }) async {
    final client =
        dio ??
        Dio(
          BaseOptions(
            connectTimeout: const Duration(seconds: 20),
            receiveTimeout: const Duration(minutes: 10),
            headers: {'User-Agent': 'NEU-Better-Updater'},
          ),
        );
    await target.parent.create(recursive: true);
    Object? lastError;
    for (final candidate in _githubCandidates(url)) {
      try {
        var existing = await target.exists() ? await target.length() : 0;
        if (expectedSize != null && expectedSize > 0 && existing > expectedSize) {
          try {
            await target.delete();
          } catch (_) {}
          existing = 0;
        }
        final headers = <String, Object>{
          'User-Agent': 'NEU-Better-Updater',
        };
        if (existing > 0) {
          headers['Range'] = 'bytes=$existing-';
        }
        final response = await client.get<ResponseBody>(
          candidate,
          options: Options(
            responseType: ResponseType.stream,
            headers: headers,
            followRedirects: true,
            validateStatus: (status) => status != null && status < 500,
          ),
        );
        final status = response.statusCode ?? 0;
        final body = response.data;
        if (body == null) {
          lastError = Exception('HTTP $status (empty body)');
          continue;
        }
        final contentLength =
            int.tryParse(
              response.headers.value(Headers.contentLengthHeader) ?? '',
            ) ??
            -1;
        if (existing > 0 && status == 206) {
          final total = expectedSize ??
              (contentLength > 0 ? existing + contentLength : -1);
          final raf = target.openSync(mode: FileMode.append);
          var received = existing;
          try {
            await for (final chunk in body.stream) {
              raf.writeFromSync(chunk);
              received += chunk.length;
              onProgress?.call(received, total > 0 ? total : received);
            }
          } finally {
            raf.closeSync();
          }
          if (contentLength > 0 && received < existing + contentLength) {
            throw Exception('连接中断（已接收 $received 字节）');
          }
          if (expectedSize != null && expectedSize > 0 &&
              received < expectedSize) {
            throw Exception('安装包未下载完整（$received/$expectedSize）');
          }
          if (received > 0) return;
        } else if (status == 200) {
          final total =
              expectedSize ?? (contentLength > 0 ? contentLength : -1);
          final raf = target.openSync(mode: FileMode.write);
          var received = 0;
          try {
            await for (final chunk in body.stream) {
              raf.writeFromSync(chunk);
              received += chunk.length;
              onProgress?.call(received, total > 0 ? total : received);
            }
          } finally {
            raf.closeSync();
          }
          if (expectedSize != null && expectedSize > 0 &&
              received < expectedSize) {
            throw Exception('安装包未下载完整（$received/$expectedSize）');
          }
          if (received > 0) return;
        } else {
          lastError = Exception('HTTP $status');
          debugPrint('[update] download got HTTP $status at $candidate');
        }
      } catch (error) {
        lastError = error;
        debugPrint('[update] download failed at $candidate: $error');
      }
    }
    if (lastError != null) {
      throw Exception('$lastError');
    }
  }
}

/// 把 GitHub release JSON 解析成 [UpdateInfo]（独立出来便于单测）。
abstract final class UpdateInfoParser {
  static UpdateInfo? fromRelease(Map<String, dynamic> release) {
    final tag = (release['tag_name'] as String?)?.trim();
    if (tag == null || tag.isEmpty) return null;
    final version = normalizeVersion(tag);
    if (version.isEmpty) return null;

    final assets = release['assets'];
    String? windowsUrl;
    String? androidUrl;
    int? windowsSize;
    int? androidSize;
    String? windowsFileName;
    String? windowsZipUrl;
    int? windowsZipSize;
    String? windowsZipName;
    if (assets is List) {
      for (final raw in assets) {
        if (raw is! Map) continue;
        final name = (raw['name'] as String? ?? '').toLowerCase();
        final url = raw['browser_download_url'] as String?;
        if (url == null || url.isEmpty) continue;
        final size = raw['size'];
        final sizeValue = size is int ? size : null;
        if (name.endsWith('.apk')) {
          androidUrl = url;
          androidSize = sizeValue;
        } else if (name.endsWith('.exe') &&
            (name.contains('windows') ||
                name.contains('win') ||
                name.contains('setup'))) {
          // 优先使用安装程序 setup.exe。
          windowsUrl = url;
          windowsSize = sizeValue;
          windowsFileName = raw['name'] as String?;
        } else if (name.endsWith('.zip') &&
            (name.contains('windows') || name.contains('win'))) {
          // 旧版仍用 zip；仅在没有 setup.exe 时回退。
          windowsZipUrl = url;
          windowsZipSize = sizeValue;
          windowsZipName = raw['name'] as String?;
        }
      }
    }
    windowsUrl ??= windowsZipUrl;
    windowsSize ??= windowsZipSize;
    windowsFileName ??= windowsZipName;

    return UpdateInfo(
      version: version,
      tagName: tag,
      notes: (release['body'] as String? ?? '').trim(),
      pageUrl: (release['html_url'] as String? ??
              'https://github.com/${UpdateService.repo}/releases')
          .trim(),
      windowsUrl: windowsUrl,
      androidUrl: androidUrl,
      windowsSize: windowsSize,
      windowsFileName: windowsFileName,
      androidSize: androidSize,
    );
  }

  /// 归一化版本号：去 v 前缀、去 +build、去 -pre 后缀。
  static String normalizeVersion(String raw) {
    var v = raw.trim().toLowerCase();
    if (v.startsWith('v')) v = v.substring(1);
    final plus = v.indexOf('+');
    if (plus >= 0) v = v.substring(0, plus);
    final dash = v.indexOf('-');
    if (dash >= 0) v = v.substring(0, dash);
    return v;
  }
}

String normalizeVersion(String raw) => UpdateInfoParser.normalizeVersion(raw);

/// 语义化版本比较：a>b 返回正数，a<b 返回负数，相等 0。缺位按 0 补齐。
int compareVersions(String a, String b) {
  final pa = _versionParts(a);
  final pb = _versionParts(b);
  final len = pa.length > pb.length ? pa.length : pb.length;
  for (var i = 0; i < len; i++) {
    final va = i < pa.length ? pa[i] : 0;
    final vb = i < pb.length ? pb[i] : 0;
    if (va != vb) return va.compareTo(vb);
  }
  return 0;
}

List<int> _versionParts(String version) {
  final v = normalizeVersion(version);
  if (v.isEmpty) return const [0];
  return v
      .split('.')
      .map((e) => int.tryParse(e.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0)
      .toList();
}
