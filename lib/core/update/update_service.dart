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

  bool get hasAnyAsset => windowsUrl != null || androidUrl != null;
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
  static const String currentVersion = '0.1.0';

  /// 返回比当前版本更新的 Release；已是最新或网络异常时返回 null。
  Future<UpdateInfo?> check() async {
    try {
      final response = await _dio.get<String>('/repos/$repo/releases/latest');
      if (response.statusCode != 200 || response.data == null) return null;
      final decoded = jsonDecode(response.data!);
      if (decoded is! Map) return null;
      final info = UpdateInfoParser.fromRelease(
        Map<String, dynamic>.from(decoded),
      );
      if (info == null) return null;
      if (compareVersions(info.version, currentVersion) <= 0) return null;
      return info;
    } catch (error) {
      debugPrint('[update] check failed: $error');
      return null;
    }
  }

  /// 下载 [url] 到 [target]。下载地址为大文件，单独用一个长超时 Dio。
  Future<void> download(
    String url,
    File target, {
    void Function(int received, int total)? onProgress,
  }) async {
    final dio = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 20),
        receiveTimeout: const Duration(minutes: 10),
        headers: {'User-Agent': 'NEU-Better-Updater'},
      ),
    );
    await target.parent.create(recursive: true);
    await dio.download(url, target.path, onReceiveProgress: onProgress);
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
    if (assets is List) {
      for (final raw in assets) {
        if (raw is! Map) continue;
        final name = (raw['name'] as String? ?? '').toLowerCase();
        final url = raw['browser_download_url'] as String?;
        if (url == null || url.isEmpty) continue;
        if (name.endsWith('.apk')) {
          androidUrl = url;
        } else if (name.endsWith('.zip') &&
            (name.contains('windows') || name.contains('win'))) {
          windowsUrl = url;
        }
      }
    }

    return UpdateInfo(
      version: version,
      tagName: tag,
      notes: (release['body'] as String? ?? '').trim(),
      pageUrl: (release['html_url'] as String? ??
              'https://github.com/${UpdateService.repo}/releases')
          .trim(),
      windowsUrl: windowsUrl,
      androidUrl: androidUrl,
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
