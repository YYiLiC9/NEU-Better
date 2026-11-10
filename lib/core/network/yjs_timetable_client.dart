import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../auth/auth_session.dart';
import 'neu_cas_client.dart';
import 'neu_service_session.dart';

/// Native HTTP client for the new graduate platform's "培养 — 学生课程表".
///
/// The platform accepts ordinary browser cookies as long as the role is
/// selected with `changeAppRole_yjs.do`; it does not require WebView2.
class YjsTimetableClient {
  static const service =
      'https://yjs.neu.edu.cn/gsapp/sys/yjsemaphome/portal/index.do';

  /// Syncs with a restored [AuthSession] using passwordless CAS SSO.
  ///
  /// This is the preferred path for users who signed in through the webview and
  /// have no saved password. [SessionExpiredException] is thrown when the saved
  /// CAS ticket is no longer valid, so callers can ask the user to sign in
  /// again (or fall back to [fetch] when a password is still available).
  Future<String?> fetchWithSession({
    required AuthSession session,
    String term = '20261',
  }) async {
    final login = await NeuServiceSession().establish(
      sessionCookies: session.cookies,
      service: service,
      targetHost: 'yjs.neu.edu.cn',
    );
    final cookies = NeuServiceSession.cookieMapFor(
      NeuServiceSession.parseCookieJar(login.cookies),
      'yjs.neu.edu.cn',
    );
    return fetchWithCookies(cookies: cookies, term: term);
  }

  /// Syncs using an already established yjs cookie jar. Split out from
  /// [fetchWithSession] so tests and probes can inject a real jar.
  Future<String?> fetchWithCookies({
    required Map<String, String> cookies,
    String term = '20261',
  }) async {
    final dio = Dio(
      BaseOptions(
        baseUrl: 'https://yjs.neu.edu.cn',
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 20),
        responseType: ResponseType.plain,
        followRedirects: true,
        validateStatus: (status) => status != null && status < 500,
        headers: {
          'User-Agent':
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
              'AppleWebKit/537.36 (KHTML, like Gecko) '
              'Chrome/157.0.0.0 Safari/537.36 Edg/157.0.0.0',
          'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.6',
        },
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
    final examAppIndex = _findAppIndex(_decode(appsResponse.data), 'wdkwapp');

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

    // `wdkwapp` is the new "我的考试" app. The API only answers after the app
    // shell has been opened (it sets `wdkwapp_XNXQDM` and refreshes `_WEU`),
    // so fetch the shell first and carry every Set-Cookie forward.
    final examBody = await _fetchExamBody(
      dio: dio,
      headers: headers,
      cookies: cookies,
      roleId: roleId,
      appIndex: examAppIndex,
      term: term,
    );

    return jsonEncode({
      'body': timetable.data,
      'currentWeek': _currentWeek(data),
      'termStartDate': _termStartDate(data, term)?.toIso8601String(),
      'examBody': examBody,
    });
  }

  /// Keeps the old username/password entry point working for callers that have
  /// no stored session (and as a fallback after [SessionExpiredException]).
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
    return fetchWithCookies(cookies: cookies, term: term);
  }

  /// New "我的考试" data API, verified against the real system on 2026-11-10.
  static const _examApi =
      '/gsapp/sys/wdkwapp/api/wdks/queryMyExamArrangeMent.do';

  /// Old wdkbapp guesses kept as a last-resort fallback for older semesters.
  static const _legacyExamEndpoints = [
    '/gsapp/sys/wdkbapp/modules/xskbcx/getKsxxList.do',
    '/gsapp/sys/wdkbapp/modules/xskksap/xskksapcx.do',
    '/gsapp/sys/wdkbapp/modules/ksxxcx/xskscx.do',
    '/gsapp/sys/xskbcxapp/modules/xskbcx/getKsxxList.do',
  ];

  Future<String?> _fetchExamBody({
    required Dio dio,
    required Map<String, String> headers,
    required Map<String, String> cookies,
    required String roleId,
    required String? appIndex,
    required String term,
  }) async {
    final shell = StringBuffer(
      '/gsapp/sys/wdkwapp/*default/index.do?min=1'
      '&_yhz=${Uri.encodeQueryComponent(roleId)}',
    );
    if (appIndex != null && appIndex.isNotEmpty) {
      shell.write('&gid_=${Uri.encodeQueryComponent(appIndex)}');
    }
    final shellUrl = shell.toString();
    try {
      final shellResponse = await dio.get<String>(
        shellUrl,
        options: Options(
          headers: {
            ...headers,
            'cookie': _cookieHeader(cookies),
            'Accept': 'text/html, */*; q=0.01',
            'Referer': service,
          },
        ),
      );
      _captureCookies(cookies, shellResponse.headers);
      // The browser-side module sets this cookie; the API rejects requests
      // without it even when the CAS cookies are otherwise valid.
      cookies.putIfAbsent('EMAP_LANG', () => 'zh');

      final response = await dio.post<String>(
        _examApi,
        data: 'XNXQDM=${Uri.encodeQueryComponent(term)}',
        options: Options(
          headers: {
            ...headers,
            'cookie': _cookieHeader(cookies),
            'Accept': 'application/json, text/javascript, */*; q=0.01',
            'Content-Type': 'application/x-www-form-urlencoded; charset=UTF-8',
            'Referer': 'https://yjs.neu.edu.cn$shellUrl',
          },
        ),
      );
      _captureCookies(cookies, response.headers);
      final body = response.data ?? '';
      final status = response.statusCode ?? 0;
      if (status < 400 && body.contains('queryMyExamArrangeMent')) {
        debugPrint('[yjs] exam api ok (${body.length} bytes)');
        return body;
      }
      debugPrint(
        '[yjs] exam api unusable (HTTP $status, ${body.length} bytes)',
      );
    } catch (error) {
      debugPrint('[yjs] exam api failed: $error');
    }

    return _fetchLegacyExamBody(
      dio: dio,
      headers: headers,
      cookies: cookies,
      roleId: roleId,
      term: term,
    );
  }

  Future<String?> _fetchLegacyExamBody({
    required Dio dio,
    required Map<String, String> headers,
    required Map<String, String> cookies,
    required String roleId,
    required String term,
  }) async {
    final appUrl =
        '/gsapp/sys/wdkbapp/*default/index.do?THEME=blue&min=1'
        '&_yhz=${Uri.encodeQueryComponent(roleId)}';
    for (final path in _legacyExamEndpoints) {
      try {
        final response = await dio.post<String>(
          path,
          data: 'XNXQDM=${Uri.encodeQueryComponent(term)}',
          options: Options(
            headers: {
              ...headers,
              'cookie': _cookieHeader(cookies),
              'Referer': 'https://yjs.neu.edu.cn$appUrl',
            },
          ),
        );
        _captureCookies(cookies, response.headers);
        final body = response.data ?? '';
        final status = response.statusCode ?? 0;
        final looksLikeData =
            status < 400 &&
            body.length > 20 &&
            !body.contains('"code":"404"') &&
            !body.contains('<html');
        if (looksLikeData) {
          debugPrint(
            '[yjs] legacy exam endpoint $path ok (${body.length} bytes)',
          );
          return body;
        }
        debugPrint('[yjs] legacy exam endpoint $path unusable (HTTP $status)');
      } catch (error) {
        debugPrint('[yjs] legacy exam endpoint $path failed: $error');
      }
    }
    return null;
  }

  /// Finds the menu index (`gid_`) of an app in `getCanVisitAppList.do`.
  String? _findAppIndex(Object? root, String appCode) {
    if (root is Map) {
      if (root['YYDM'] == appCode) {
        final menus = root['caidanList'];
        if (menus is List && menus.isNotEmpty && menus.first is Map) {
          final index = (menus.first as Map)['index'];
          if (index is String && index.trim().isNotEmpty) return index.trim();
        }
      }
      for (final value in root.values) {
        final found = _findAppIndex(value, appCode);
        if (found != null) return found;
      }
    } else if (root is List) {
      for (final value in root) {
        final found = _findAppIndex(value, appCode);
        if (found != null) return found;
      }
    }
    return null;
  }

  /// Derives Monday of teaching week 1 from the portal welcome message,
  /// which reads like "今天是11月10日 星期二,2026-2027秋季学期 第11周".
  DateTime? _termStartDate(Object? data, String term) {
    if (data is! Map) return null;
    final words = '${data['welcomeWords'] ?? ''}';
    final weekMatch = RegExp(r'第\s*(\d+)\s*周').firstMatch(words);
    final dateMatch = RegExp(r'(\d{1,2})月(\d{1,2})日').firstMatch(words);
    if (weekMatch == null || dateMatch == null) return null;
    final week = int.tryParse(weekMatch.group(1)!);
    if (week == null || week < 1 || week > 40) return null;
    final year =
        int.tryParse(term.length >= 4 ? term.substring(0, 4) : '') ??
        DateTime.now().year;
    final DateTime today;
    try {
      today = DateTime(
        year,
        int.parse(dateMatch.group(1)!),
        int.parse(dateMatch.group(2)!),
      );
    } catch (_) {
      return null;
    }
    // Monday of the current week, shifted back by (week - 1) weeks.
    return today.subtract(Duration(days: today.weekday - 1 + (week - 1) * 7));
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
    return cookies.entries
        .map((entry) => '${entry.key}=${entry.value}')
        .join('; ');
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
