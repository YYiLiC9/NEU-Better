import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../auth/auth_session.dart';
import 'neu_cas_client.dart';
import 'neu_service_session.dart';

/// 网费查询异常（余额中心「网费」用）。
class NetFeeQueryException implements Exception {
  const NetFeeQueryException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// 缴费服务大厅「网费」余额查询。
///
/// 实测（2026-11-14，账号 20225767）：用 CAS 会话换到 pay.neu.edu.cn 的
/// JSESSIONID 后，`POST /queryNetAccBalance`
/// `netNo=学号&netType=0&factorycode=N005` 返回
/// `{"returncode":"SUCCESS","netaccbal":"21.4694"}`。
class NetFeeClient {
  static const payService = 'https://pay.neu.edu.cn/drCasLogin';
  static const factoryCode = 'N005';

  Future<double> queryWithSession({required AuthSession session}) async {
    if (session.studentId.trim().isEmpty) {
      throw const NetFeeQueryException('缺少学号，无法查询网费');
    }
    final login = await NeuServiceSession().establish(
      sessionCookies: session.cookies,
      service: payService,
      targetHost: 'pay.neu.edu.cn',
    );
    final payCookies = NeuServiceSession.cookieMapFor(
      NeuServiceSession.parseCookieJar(login.cookies),
      'pay.neu.edu.cn',
    );
    return _query(payCookies, session.studentId);
  }

  /// 用账号密码直接走一次 CAS(service=缴费大厅) 登录后查询；用于会话式
  /// SSO 在某些账号/节点失败时的兜底。
  Future<double> query({
    required String username,
    required String password,
    String? studentId,
  }) async {
    final cas = await NeuCasClient().login(
      username: username,
      password: password,
      service: payService,
    );
    final payCookies = <String, String>{};
    for (final entry in cas.cookies.entries) {
      if (entry.key != 'pay.neu.edu.cn' &&
          !entry.key.endsWith('.pay.neu.edu.cn')) {
        continue;
      }
      for (final part in entry.value.split(';')) {
        final trimmed = part.trim();
        final eq = trimmed.indexOf('=');
        if (eq <= 0 || eq == trimmed.length - 1) continue;
        payCookies[trimmed.substring(0, eq)] = trimmed.substring(eq + 1);
      }
    }
    final id = (studentId == null || studentId.trim().isEmpty)
        ? username.trim()
        : studentId.trim();
    return _query(payCookies, id);
  }

  Future<double> _query(
    Map<String, String> cookies,
    String studentId,
  ) async {
    final dio = Dio(
      BaseOptions(
        baseUrl: 'https://pay.neu.edu.cn',
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 20),
        responseType: ResponseType.plain,
        validateStatus: (status) => status != null && status < 500,
      ),
    );
    final header = cookies.entries
        .map((entry) => '${entry.key}=${entry.value}')
        .join('; ');
    final response = await dio.post<String>(
      '/queryNetAccBalance',
      data: 'netNo=$studentId&netType=0&factorycode=$factoryCode',
      options: Options(
        headers: {
          'Cookie': header,
          'Content-Type': 'application/x-www-form-urlencoded; charset=UTF-8',
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
      throw const NetFeeQueryException('缴费平台返回了无法解析的数据');
    }
    final code = (json['returncode'] as String? ?? '').toUpperCase();
    if (code != 'SUCCESS') {
      final message = (json['returnmsg'] as String? ?? '').trim();
      throw NetFeeQueryException(message.isEmpty ? '网费查询失败' : message);
    }
    final raw = json['netaccbal'];
    final value = raw is num
        ? raw.toDouble()
        : double.tryParse(raw?.toString().trim() ?? '');
    if (value == null) {
      debugPrint('[netfee] unexpected body: $body');
      throw const NetFeeQueryException('网费余额格式无法识别');
    }
    return value;
  }
}
