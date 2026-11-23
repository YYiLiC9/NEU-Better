import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';

class SrunStatus {
  const SrunStatus({
    required this.online,
    this.balance,
    this.sumBytes,
    this.clientIp,
    this.username,
    this.connectionKey,
  });

  final bool online;
  final double? balance;
  final int? sumBytes;
  final String? clientIp;
  final String? username;
  final String? connectionKey;
}

class SrunUnavailable implements Exception {
  const SrunUnavailable();
}

class SrunRejected implements Exception {
  const SrunRejected(this.message);

  final String message;
}

class SrunPortalClient {
  SrunPortalClient({Dio? dio, Future<String> Function(Uri)? readResponse})
    : _dio = dio ?? _transport(),
      _usesOwnTransport = dio == null && readResponse == null,
      _readResponse = readResponse;

  static const host = 'ipgw.neu.edu.cn';
  static const _ssoPage = '/srun_portal_sso';
  static const _ssoApi = '/v1/srun_portal_sso';
  static const ssoPageUrl = 'https://$host$_ssoPage?ac_id=$_acId';
  // CAS registers the HTTP service identifier even though the ticket itself
  // is captured at the CAS redirect and redeemed over HTTPS.
  static final ssoService = Uri.http(host, _ssoPage, {'ac_id': _acId});
  static const _timeout = Duration(seconds: 8);
  static const _callback = 'neuBetterStatus';
  static const _acId = '1';
  final bool _usesOwnTransport;
  final Future<String> Function(Uri)? _readResponse;
  Dio _dio;
  String? _sourceIp;

  /// A null address restores the system's current routing.
  void useSourceAddress(String? ip) {
    if (!_usesOwnTransport || ip == _sourceIp) return;
    _dio.close(force: true);
    _sourceIp = ip;
    _dio = _transport(ip);
  }

  static Dio _transport([String? sourceIp]) {
    final dio = Dio(
      BaseOptions(
        connectTimeout: _timeout,
        receiveTimeout: _timeout,
        sendTimeout: _timeout,
      ),
    );
    final source = sourceIp == null ? null : InternetAddress(sourceIp);
    dio.httpClientAdapter = IOHttpClientAdapter(
      createHttpClient: () {
        final client = HttpClient();
        client.findProxy = (_) => 'DIRECT';
        client.connectionFactory = (uri, _, _) async {
          // Use IPv4 for this portal even when Clash routes the system's
          // other traffic through a dual-stack proxy.
          final addresses = await InternetAddress.lookup(
            uri.host,
            type: InternetAddressType.IPv4,
          );
          final socketTask = await Socket.startConnect(
            addresses.first,
            uri.port,
            sourceAddress: source,
          );
          // The custom socket keeps the gateway hostname for TLS validation.
          Socket? rawSocket;
          final secure = socketTask.socket.then((socket) {
            rawSocket = socket;
            return SecureSocket.secure(socket, host: uri.host);
          });
          return ConnectionTask.fromSocket(secure, () {
            socketTask.cancel();
            rawSocket?.destroy();
          });
        };
        return client;
      },
    );
    return dio;
  }

  Future<SrunStatus> status() async =>
      parseStatus(await _get('/cgi-bin/rad_user_info'));

  Future<void> loginWithTicket(String ticket) async {
    final result = _decode(
      await _read(Uri.https(host, _ssoApi, {'ac_id': _acId, 'ticket': ticket})),
    );
    if (!_ok(result)) {
      throw SrunRejected(_errorMessage(result, '学校网关拒绝了统一身份认证。'));
    }
    if (_text(result['Redirect']) != null) {
      throw const SrunRejected('学校网关要求重新进行统一身份认证。');
    }
  }

  Future<void> logout(SrunStatus session) async {
    final username = session.username;
    final ip = session.clientIp;
    if (!session.online || username == null || ip == null) {
      throw const SrunRejected('学校网关未返回完整的在线会话，请刷新后再试。');
    }
    final result = _decode(
      await _get('/cgi-bin/srun_portal', {
        'action': 'logout',
        'username': username,
        'ip': ip,
        'ac_id': _acId,
      }),
    );
    if (!_ok(result) &&
        !_offline(result) &&
        !const {'E6503', 'E6504'}.contains(result['ecode'])) {
      throw SrunRejected(_errorMessage(result, '学校网关拒绝注销。'));
    }
  }

  Future<String> _get(String path, [Map<String, String> params = const {}]) =>
      _read(
        Uri.https(host, path, {
          ...params,
          'callback': _callback,
          '_': DateTime.now().millisecondsSinceEpoch.toString(),
        }),
      );

  Future<String> _read(Uri url) async {
    final readResponse = _readResponse;
    if (readResponse != null) {
      return readResponse(url).timeout(
        _timeout,
        onTimeout: () {
          throw const SrunUnavailable();
        },
      );
    }
    final cancel = CancelToken();
    try {
      final response = await _dio
          .getUri<String>(
            url,
            cancelToken: cancel,
            options: Options(
              responseType: ResponseType.plain,
              followRedirects: false,
              headers: {
                HttpHeaders.refererHeader:
                    url.queryParameters['action'] == 'logout'
                    ? 'https://$host/srun_portal_success?ac_id=$_acId'
                    : ssoPageUrl,
              },
            ),
          )
          .timeout(
            _timeout,
            onTimeout: () {
              cancel.cancel();
              throw const SrunUnavailable();
            },
          );
      return response.data ?? '';
    } on DioException catch (error) {
      if (error.type == DioExceptionType.badResponse) {
        throw const SrunRejected('学校网关返回了 HTTP 错误。');
      }
      // Dio's exception can contain the CAS ticket.
      throw const SrunUnavailable();
    }
  }

  void close() => _dio.close(force: true);

  static SrunStatus parseStatus(String body) {
    final data = _decode(body);
    final ip = _ipv4(data['online_ip']) ?? _ipv4(data['client_ip']);
    if (_offline(data)) {
      return SrunStatus(online: false, clientIp: ip);
    }
    if (!_ok(data)) {
      throw SrunRejected(_errorMessage(data, '网关未返回有效状态。'));
    }
    final balance = double.tryParse(data['user_balance'].toString().trim());
    final sumBytes = int.tryParse(data['sum_bytes'].toString().trim());
    final name = _text(data['user_name']);
    final domain = _text(data['domain']);
    final username = name != null && !name.contains('@') && domain != null
        ? (domain.startsWith('@') ? name + domain : '$name@$domain')
        : name;
    return SrunStatus(
      online: true,
      balance: balance?.isFinite == true ? balance : null,
      sumBytes: sumBytes != null && sumBytes >= 0 ? sumBytes : null,
      clientIp: ip,
      username: username,
      connectionKey: jsonEncode([username, ip, data['add_time']]),
    );
  }

  static Map<String, dynamic> _decode(String body) {
    if (body.length > 64 * 1024) throw const FormatException('网关响应过大。');
    final text = body.trim();
    final jsonp = RegExp(
      '^$_callback'
      r'\s*\((.*)\)\s*;?$',
      dotAll: true,
    ).firstMatch(text);
    try {
      final data = jsonDecode(jsonp?.group(1) ?? text);
      if (data is Map<String, dynamic>) return data;
    } on FormatException {
      // Do not retain the original response in an error.
    }
    throw const FormatException('网关返回了未知格式。');
  }

  static bool _ok(Map<String, dynamic> data) {
    if (data['error'] case final error?) return error == 'ok';
    if (data['code'] case final code?) return code == 0 || code == '0';
    return data['res'] == 'ok';
  }

  static bool _offline(Map<String, dynamic> data) => const [
    'error',
    'res',
    'error_msg',
  ].any((key) => data[key] == 'not_online_error');

  static String? _text(Object? raw) =>
      raw is String && raw.trim().isNotEmpty ? raw.trim() : null;

  static String _errorMessage(Map<String, dynamic> response, String fallback) {
    const messages = {
      'E2531': '校园网账号不存在。',
      'E2532': '认证间隔太短，请等 10 秒后重试。',
      'E2533': '密码错误次数超过限制，请等 5 分钟后重试。',
      'E2534': '学校网关报告账号因代理行为暂时受限。',
      'E2553': '校园网账号或密码错误。',
      'E2615': '校园网 IP 地址绑定错误。',
      'E2616': '校园网账号已欠费。',
      'E2620': '校园网账号已在线，请刷新状态。',
      'E2833': '网关未识别当前 IPv4，请检查校园网线路。',
      'E2841': '校园网 IP 地址绑定错误。',
      'E2843': '网关未识别当前 IPv4，请检查校园网线路。',
      'E6506': '校园网账号或密码错误。',
    };
    final code = _text(response['ecode']);
    final policy = _text(response['ploy_msg']);
    final detail =
        _text(response['error_msg']) ??
        _text(response['message']) ??
        _text(response['msg']);
    final message =
        (policy != null && !policy.startsWith('E0000') ? policy : null) ??
        messages[code] ??
        detail ??
        _text(response['suc_msg']);
    if (message != null) {
      final readable = String.fromCharCodes(message.runes.take(200));
      return code != null && RegExp(r'^E\d{4}$').hasMatch(code)
          ? '$readable（$code）'
          : readable;
    }
    final reason = code ?? _text(response['error']) ?? _text(response['res']);
    if (reason != null &&
        reason != 'fail' &&
        RegExp(r'^[\w-]{1,48}$').hasMatch(reason)) {
      return '$fallback（$reason）';
    }
    if (response['code'] case final int resultCode) {
      return '$fallback（code=$resultCode）';
    }
    return fallback;
  }

  static String? _ipv4(Object? raw) {
    if (raw is! String) return null;
    final address = InternetAddress.tryParse(raw);
    if (address == null ||
        address.type != InternetAddressType.IPv4 ||
        address.isLoopback ||
        address.isLinkLocal ||
        address.address == '0.0.0.0') {
      return null;
    }
    return address.address;
  }
}
