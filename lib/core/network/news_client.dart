import 'dart:convert';

import 'package:dio/dio.dart';

import '../models/news_models.dart';

/// 新闻接口异常（网络 / 业务错误）。
class NewsException implements Exception {
  const NewsException(this.message, {this.code});

  final String message;
  final int? code;

  @override
  String toString() => message;
}

/// 校园新闻只读客户端：匿名 GET `personal.neu.edu.cn/portal/news/frontend`。
///
/// 接口（已实测匿名可读）：
/// - 栏目 `default/module?system=news`
/// - 列表 `default/news-list?system=news&cid=<cid>&page=1&pageSize=20`
/// - 详情 `default/<id>?system=news`
/// - 标记已读 `POST default/read-article/<id>`（可选，失败忽略）
class NewsClient {
  NewsClient({Dio? dio})
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              baseUrl: baseUrl,
              connectTimeout: const Duration(seconds: 8),
              receiveTimeout: const Duration(seconds: 8),
              sendTimeout: const Duration(seconds: 8),
              headers: const <String, dynamic>{
                'User-Agent':
                    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36',
                'Accept': 'application/json, text/plain, */*',
              },
            ),
          );

  static const String baseUrl = 'https://personal.neu.edu.cn/portal/news/frontend';
  static const String system = 'news';

  final Dio _dio;

  /// 栏目列表（失败抛 [NewsException]）。
  Future<List<NewsSection>> sections() async {
    final data = await _getJson('/default/module', <String, dynamic>{
      'system': system,
    });
    return parseNewsSections(data);
  }

  /// 某栏目某页新闻。
  Future<NewsListResult> list(
    String cid, {
    int page = 1,
    int pageSize = 20,
  }) async {
    final data = await _getJson('/default/news-list', <String, dynamic>{
      'system': system,
      'cid': cid,
      'page': page,
      'pageSize': pageSize,
    });
    return parseNewsList(data);
  }

  /// 详情。
  Future<NewsDetail> detail(String id) async {
    final data = await _getJson('/default/$id', <String, dynamic>{
      'system': system,
    });
    final detail = parseNewsDetail(data);
    if (detail == null) {
      throw const NewsException('新闻详情为空');
    }
    return detail;
  }

  /// 标记已读：best-effort，失败忽略（未登录时服务端会报错）。
  Future<void> markRead(String id) async {
    try {
      await _dio.post<Object?>(
        '$baseUrl/default/read-article/$id',
        data: <String, dynamic>{'system': system},
        options: Options(
          contentType: Headers.formUrlEncodedContentType,
          followRedirects: false,
          validateStatus: (code) => code != null && code < 500,
        ),
      );
    } catch (_) {
      // 忽略：仅用于减少未读角标，不影响阅读。
    }
  }

  Future<Object?> _getJson(
    String path,
    Map<String, dynamic> query,
  ) async {
    Response<Object?> response;
    try {
      response = await _dio.get<Object?>(
        '$baseUrl$path',
        queryParameters: query,
        options: Options(
          responseType: ResponseType.json,
          followRedirects: false,
          validateStatus: (code) => code != null && code < 500,
        ),
      );
    } on DioException catch (error) {
      throw NewsException('网络请求失败：${error.message ?? error.type.name}');
    }
    final data = response.data;
    if (data is! Map) {
      throw const NewsException('接口返回格式异常');
    }
    final code = data['e'];
    if (code is int && code != 0) {
      throw NewsException(
        (data['m'] ?? '接口返回错误').toString(),
        code: code,
      );
    }
    return data;
  }

  /// 测试辅助：允许用纯 JSON 字符串手工构造响应。
  static Object? decodeJson(String source) => jsonDecode(source);
}
