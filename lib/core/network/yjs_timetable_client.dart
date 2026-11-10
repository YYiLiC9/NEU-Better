import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import 'neu_cas_client.dart';

/// Native HTTP client for the new graduate platform's "培养 — 学生课程表".
///
/// The platform accepts ordinary browser cookies as long as the role is
/// selected with `changeAppRole_yjs.do`; it does not require WebView2.
class YjsTimetableClient {
  static const service =
      'https://yjs.neu.edu.cn/gsapp/sys/yjsemaphome/portal/index.do';

  Future<String?> fetch({
    required String username,
    required String password,
    String term = '20261',
  }) async {
    final cas = await NeuCasClient().login(
      username: username,
      password: password,
      service: service,
    );

    final cookies = <String, String>{};
    for (final entry in cas.cookies.entries) {
      if (entry.key != 'yjs.neu.edu.cn' &&
          !entry.key.endsWith('.yjs.neu.edu.cn')) {
        continue;
      }
      for (final part in entry.value.split(';')) {
        final trimmed = part.trim();
        final equals = trimmed.indexOf('=');
        if (equals <= 0) continue;
        final name = trimmed.substring(0, equals);
        final value = trimmed.substring(equals + 1);
        if (name.isEmpty || value.isEmpty) continue;
        cookies[name] = value;
      }
    }

    final dio = Dio(
      BaseOptions(
        baseUrl: 'https://yjs.neu.edu.cn',
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 20),
        responseType: ResponseType.plain,
        followRedirects: true,
        validateStatus: (status) => status != null && status < 500,
      ),
    );

    final headers = {
      'X-Requested-With': 'XMLHttpRequest',
      'Origin': 'https://yjs.neu.edu.cn',
      'Referer': service,
      'Content-Type': Headers.formUrlEncodedContentType,
    };

    final infoResponse = await dio.post<String>(
      '/gsapp/sys/yjsemaphome/modules/pubWork/getUserInfo.do',
      data: '',
      options: Options(headers: {...headers, 'cookie': _cookieHeader(cookies)}),
    );
    _captureCookies(cookies, infoResponse.headers);
    final userInfo = _decode(infoResponse.data);
    final data = userInfo?['data'];
    final roleId = data is Map ? _firstRoleId(data['grouplist']) : null;
    if (roleId == null || roleId.isEmpty) {
      throw const FormatException('该账号没有研究生系统身份（grouplist 为空）');
    }

    final roleResponse = await dio.post<String>(
      '/gsapp/sys/yjsemaphome/modules/pubWork/changeAppRole_yjs.do',
      data: {'_yhz': roleId},
      options: Options(headers: {...headers, 'cookie': _cookieHeader(cookies)}),
    );
    _captureCookies(cookies, roleResponse.headers);

    final appsResponse = await dio.post<String>(
      '/gsapp/sys/yjsemaphome/modules/pubWork/getCanVisitAppList.do',
      data: 'KEYWORD=',
      options: Options(headers: {...headers, 'cookie': _cookieHeader(cookies)}),
    );
    _captureCookies(cookies, appsResponse.headers);

    final appUrl =
        '/gsapp/sys/wdkbapp/*default/index.do?THEME=blue&min=1'
        '&_yhz=${Uri.encodeQueryComponent(roleId)}';
    final appPage = await dio.get<String>(
      appUrl,
      options: Options(headers: {'cookie': _cookieHeader(cookies)}),
    );
    _captureCookies(cookies, appPage.headers);

    final timetable = await dio.post<String>(
      '/gsapp/sys/wdkbapp/modules/xskcb/xspkjgcx.do',
      data: 'XNXQDM=${Uri.encodeQueryComponent(term)}&*order=-ZCBH',
      options: Options(
        headers: {
          ...headers,
          'cookie': _cookieHeader(cookies),
          'Referer': 'https://yjs.neu.edu.cn$appUrl',
        },
      ),
    );
    _captureCookies(cookies, timetable.headers);

    if (timetable.statusCode == null || timetable.statusCode! >= 400) {
      throw FormatException('研究生系统没有返回课表数据（HTTP ${timetable.statusCode}）');
    }
    return jsonEncode({
      'body': timetable.data,
      'currentWeek': _currentWeek(data),
    });
  }

  Map<String, dynamic>? _decode(Object? raw) {
    if (raw is! String || raw.trim().isEmpty) return null;
    try {
      final value = jsonDecode(raw);
      return value is Map<String, dynamic> ? value : null;
    } catch (error) {
      debugPrint('[yjs] JSON parse failed: $error');
      return null;
    }
  }

  String? _firstRoleId(Object? rawGroups) {
    dynamic groups = rawGroups;
    if (groups is String) {
      if (groups.trim().isEmpty) return null;
      try {
        groups = jsonDecode(groups);
      } catch (_) {
        return null;
      }
    }
    if (groups is! List || groups.isEmpty) return null;
    final first = groups.first;
    if (first is! Map) return null;
    for (final key in const ['ROLEID', 'roleId', 'id', 'yhzid']) {
      final value = first[key];
      if (value is String && value.trim().isNotEmpty) return value.trim();
    }
    return null;
  }

  int? _currentWeek(Object? data) {
    if (data is! Map) return null;
    final words = data['welcomeWords'];
    final match = RegExp(r'第\s*(\d+)\s*周').firstMatch('${words ?? ''}');
    return int.tryParse(match?.group(1) ?? '');
  }

  String _cookieHeader(Map<String, String> cookies) {
    return cookies.entries.map((entry) => '${entry.key}=${entry.value}').join('; ');
  }

  void _captureCookies(Map<String, String> cookies, Headers headers) {
    final rawHeaders = headers['set-cookie'];
    if (rawHeaders == null) return;
    for (final raw in rawHeaders) {
      for (final part in raw.split(RegExp(r',(?=[^;]+=)'))) {
        final first = part.split(';').first.trim();
        final equals = first.indexOf('=');
        if (equals <= 0) continue;
        final name = first.substring(0, equals).trim();
        final value = first.substring(equals + 1).trim();
        if (name.isNotEmpty && value.isNotEmpty) cookies[name] = value;
      }
    }
  }
}
