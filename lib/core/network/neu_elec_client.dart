import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../../features/dorm/electricity_models.dart';
import 'neu_cas_client.dart';
import 'neu_service_session.dart';

class ElectricityQueryException implements Exception {
  const ElectricityQueryException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Native client for the 缴费服务大厅 electricity query
/// (https://pay.neu.edu.cn, 电费 project id 414 / factorycode E039).
///
/// Flow (verified live 2026-11-10):
/// 1. CAS login with the self-referential service `https://pay.neu.edu.cn/drCasLogin`.
///    `login()` may stop on the final 302 hop (finalUri still carrying
///    `?ticket=`), so we explicitly follow `finalUri` until the portal page
///    (…/openPortal) returns 200 before calling any API — otherwise APIs
///    answer 200 with empty bodies.
/// 2. POST /queryRommInfo (note the platform's spelling "Romm") with
///    `elecroomno=<房间码>&factorycode=E039`.
class NeuElecClient {
  NeuElecClient({
    Dio? dio,
    NeuCasClient? cas,
    NeuServiceSession? serviceSession,
  }) : _dio = dio ?? _buildDio(),
       _cas = cas ?? NeuCasClient(),
       _serviceSession = serviceSession ?? NeuServiceSession();

  static const payService = 'https://pay.neu.edu.cn/drCasLogin';
  static const payOrigin = 'https://pay.neu.edu.cn';
  static const factoryCode = 'E039';

  final Dio _dio;
  final NeuCasClient _cas;
  final NeuServiceSession _serviceSession;
  final Map<String, String> _jar = {};

  static Dio _buildDio() {
    return Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 20),
        sendTimeout: const Duration(seconds: 15),
        responseType: ResponseType.plain,
        followRedirects: false,
        validateStatus: (status) => status != null && status < 400,
        headers: {
          'User-Agent':
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
              'AppleWebKit/537.36 (KHTML, like Gecko) '
              'Chrome/157.0.0.0 Safari/537.36 Edg/157.0.0.0',
          'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.6',
        },
      ),
    );
  }

  /// Queries the remaining electricity (度) for [roomCode].
  Future<ElectricityReading> query({
    required String username,
    required String password,
    required String roomCode,
  }) async {
    _jar.clear();
    final login = await _cas.login(
      username: username,
      password: password,
      service: payService,
    );
    final payCookies = login.cookies[payOrigin.replaceFirst('https://', '')];
    if (payCookies != null && payCookies.isNotEmpty) {
      _absorb(payCookies);
    } else {
      // Fall back to every captured host so the pay domain still gets the
      // shared CAS session cookies (TGC etc.).
      for (final header in login.cookies.values) {
        _absorb(header);
      }
    }
    await _establishPortal(login.finalUri);
    return _queryRoom(roomCode);
  }

  /// Queries with the CAS session saved at login time (CASTGC / TGT), so no
  /// plain-text password is needed. This is the path used by both the dorm page
  /// and the daily background check.
  Future<ElectricityReading> queryWithSession({
    required Map<String, String> sessionCookies,
    required String roomCode,
  }) async {
    _jar.clear();
    final result = await _serviceSession.establish(
      sessionCookies: sessionCookies,
      service: payService,
      targetHost: 'pay.neu.edu.cn',
    );
    final payCookies = NeuServiceSession.cookieMapFor(
      NeuServiceSession.parseCookieJar(result.cookies),
      'pay.neu.edu.cn',
    );
    _jar.addAll(payCookies);
    await _establishPortal(result.finalUri);
    return _queryRoom(roomCode);
  }

  /// Follows the CAS redirect chain one hop at a time (capturing every
  /// Set-Cookie) until we land on the open portal page.
  Future<void> _establishPortal(Uri start) async {
    var uri = start;
    for (var hop = 0; hop < 10; hop++) {
      if (uri.path.contains('openPortal') && (uri.host == 'pay.neu.edu.cn')) {
        debugPrint('[elec] portal session established at ${uri.path}');
        return;
      }
      final response = await _dio.getUri<void>(
        uri,
        options: Options(headers: {'Cookie': _cookieHeader()}),
      );
      _absorbAll(response);
      final location = response.headers.value('location');
      if (location == null || location.isEmpty) {
        debugPrint('[elec] portal chain settled at ${uri.path}');
        return;
      }
      uri = uri.resolve(location);
    }
    debugPrint('[elec] portal chain did not reach openPortal; continuing');
  }

  Future<ElectricityReading> _queryRoom(String roomCode) async {
    final response = await _dio.post<String>(
      '$payOrigin/queryRommInfo',
      data: 'elecroomno=$roomCode&factorycode=$factoryCode',
      options: Options(
        headers: {
          'Cookie': _cookieHeader(),
          'Content-Type': 'application/x-www-form-urlencoded; charset=UTF-8',
          'Referer': '$payOrigin/openPayElecPagesDbdx51414E039.html',
          'X-Requested-With': 'XMLHttpRequest',
          'Accept': 'application/json, text/javascript, */*; q=0.01',
        },
      ),
    );
    final body = response.data ?? '';
    Map<String, dynamic> json;
    try {
      json = Map<String, dynamic>.from(
        jsonDecode(body.isEmpty ? '{}' : body) as Map,
      );
    } on FormatException {
      throw const ElectricityQueryException('缴费平台返回了无法解析的数据');
    }
    final returnCode = (json['returncode'] as String? ?? '').toUpperCase();
    if (returnCode != 'SUCCESS') {
      final message = (json['returnmsg'] as String? ?? '').trim();
      throw ElectricityQueryException(message.isEmpty ? '电费查询失败' : message);
    }
    return ElectricityReading.fromPayResponse(roomCode: roomCode, json: json);
  }

  String _cookieHeader() =>
      _jar.entries.map((e) => '${e.key}=${e.value}').join('; ');

  void _absorb(String header) {
    for (final part in header.split(';')) {
      final pair = part.trim();
      if (pair.isEmpty || !pair.contains('=')) continue;
      final index = pair.indexOf('=');
      final name = pair.substring(0, index).trim();
      final value = pair.substring(index + 1).trim();
      if (name.isEmpty ||
          name == 'Path' ||
          name == 'Domain' ||
          name == 'Expires' ||
          name == 'Max-Age' ||
          name == 'HttpOnly' ||
          name == 'Secure' ||
          name == 'SameSite') {
        continue;
      }
      _jar[name] = value;
    }
  }

  void _absorbAll(Response response) {
    final setCookies = response.headers.map['set-cookie'];
    if (setCookies == null) return;
    for (final cookie in setCookies) {
      _absorb(cookie);
    }
  }
}
