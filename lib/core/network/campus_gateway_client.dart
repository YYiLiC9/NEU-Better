import 'dart:convert';

import 'package:dio/dio.dart';

class CampusGatewayStatus {
  const CampusGatewayStatus.offline()
    : online = false,
      connectionKey = null,
      balance = null,
      usedBytes = null;

  const CampusGatewayStatus.online({
    required this.connectionKey,
    this.balance,
    this.usedBytes,
  }) : online = true;

  final bool online;
  final String? connectionKey;
  final double? balance;
  final int? usedBytes;
}

class CampusGatewayClient {
  CampusGatewayClient({Dio? dio})
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              connectTimeout: const Duration(seconds: 6),
              receiveTimeout: const Duration(seconds: 6),
              responseType: ResponseType.plain,
              followRedirects: false,
            ),
          );

  static const host = 'ipgw.neu.edu.cn';
  static final portal = Uri.https(host, '/');
  static final accountPortal = Uri.https('$host:8800', '/');
  static const _callback = 'neuBetterStatus';
  final Dio _dio;

  Future<CampusGatewayStatus> readStatus() async {
    final response = await _dio.getUri<String>(
      Uri.https(host, '/cgi-bin/rad_user_info', {
        'callback': _callback,
        '_': DateTime.now().millisecondsSinceEpoch.toString(),
      }),
    );
    return parseStatus(response.data ?? '');
  }

  void close() => _dio.close(force: true);

  static CampusGatewayStatus parseStatus(String body) {
    if (body.length > 64 * 1024) throw const FormatException('网关响应过大');
    var payload = body.trim();
    final jsonp = RegExp(
      '^$_callback\\s*\\((.*)\\)\\s*;?\$',
      dotAll: true,
    ).firstMatch(payload);
    if (jsonp != null) payload = jsonp.group(1)!;
    final data = jsonDecode(payload);
    if (data is! Map) throw const FormatException('网关返回了未知格式');

    final status = data['error'] ?? data['res'];
    if (status == 'not_online_error') {
      return const CampusGatewayStatus.offline();
    }
    if (status != 'ok') throw const FormatException('网关未返回有效状态');

    // The gateway's cumulative billed usage is independent of the PC counter.
    final balance = double.tryParse('${data['user_balance']}'.trim());
    final usedBytes = int.tryParse('${data['sum_bytes']}'.trim());
    return CampusGatewayStatus.online(
      connectionKey: jsonEncode([
        data['user_name'],
        data['domain'],
        data['online_ip'] ?? data['client_ip'],
        data['add_time'],
      ]),
      balance: balance?.isFinite == true ? balance : null,
      usedBytes: usedBytes != null && usedBytes >= 0 ? usedBytes : null,
    );
  }
}
