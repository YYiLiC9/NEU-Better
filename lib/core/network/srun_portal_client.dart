import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:pointycastle/api.dart' show KeyParameter;
import 'package:pointycastle/digests/md5.dart';
import 'package:pointycastle/digests/sha1.dart';
import 'package:pointycastle/macs/hmac.dart';

class SrunStatus {
  const SrunStatus({
    required this.online,
    this.balance,
    this.sumBytes,
    this.clientIp,
    this.connectionKey,
  });

  final bool online;
  final double? balance;
  final int? sumBytes;
  final String? clientIp;
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
  SrunPortalClient({
    Dio? dio,
    Future<String> Function(Uri)? readResponse,
    this._deviceName = 'Windows',
  }) : _dio = dio ?? _transport(),
       _usesOwnTransport = dio == null && readResponse == null,
       _readResponse = readResponse;

  static const host = 'ipgw.neu.edu.cn';
  static const _timeout = Duration(seconds: 8);
  static const _callback = 'neuBetterStatus';
  static const _acId = '1';
  static const _n = '200';
  static const _type = '1';
  final bool _usesOwnTransport;
  final Future<String> Function(Uri)? _readResponse;
  final String _deviceName;
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
    if (sourceIp != null) {
      final source = InternetAddress(sourceIp);
      dio.httpClientAdapter = IOHttpClientAdapter(
        createHttpClient: () {
          final client = HttpClient();
          client.findProxy = (_) => 'DIRECT';
          client.connectionFactory = (uri, _, _) async {
            final addresses = await InternetAddress.lookup(
              uri.host,
              type: InternetAddressType.IPv4,
            );
            final socketTask = await Socket.startConnect(
              addresses.first,
              uri.port,
              sourceAddress: source,
            );
            // A custom HttpClient connection factory supplies the TLS socket,
            // including the gateway hostname for certificate verification.
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
    }
    return dio;
  }

  Future<SrunStatus> status() async =>
      parseStatus(await _get('/cgi-bin/rad_user_info'));

  Future<void> login({
    required String username,
    required String password,
    String? clientIp,
  }) async {
    final challenge = _decode(
      await _get('/cgi-bin/get_challenge', {
        'username': username,
        'ip': clientIp ?? '',
      }),
    );
    final token = challenge['challenge'];
    final ip = _ipv4(challenge['client_ip']) ?? _ipv4(clientIp);
    if (!_ok(challenge) || token is! String || token.isEmpty || ip == null) {
      throw SrunRejected(_errorMessage(challenge, '无法获取网关登录令牌。'));
    }
    final result = _decode(
      await _get(
        '/cgi-bin/srun_portal',
        loginParameters(
          username: username,
          password: password,
          ip: ip,
          token: token,
          deviceName: _deviceName,
        ),
      ),
    );
    if (!_ok(result)) {
      throw SrunRejected(_errorMessage(result, '学校网关拒绝登录。'));
    }
  }

  Future<String> _get(
    String path, [
    Map<String, String> params = const {},
  ]) async {
    final url = Uri.https(host, path, {
      ...params,
      'callback': _callback,
      '_': DateTime.now().millisecondsSinceEpoch.toString(),
    });
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
    } on DioException {
      // Dio's exception can contain the signed authentication URL.
      throw const SrunUnavailable();
    }
  }

  void close() => _dio.close(force: true);

  static SrunStatus parseStatus(String body) {
    final data = _decode(body);
    final ip = _ipv4(data['online_ip']) ?? _ipv4(data['client_ip']);
    if ((data['error'] ?? data['res']) == 'not_online_error') {
      return SrunStatus(online: false, clientIp: ip);
    }
    if (!_ok(data)) {
      throw SrunRejected(_errorMessage(data, '网关未返回有效状态。'));
    }
    final balance = double.tryParse(data['user_balance'].toString().trim());
    final sumBytes = int.tryParse(data['sum_bytes'].toString().trim());
    return SrunStatus(
      online: true,
      balance: balance?.isFinite == true ? balance : null,
      sumBytes: sumBytes != null && sumBytes >= 0 ? sumBytes : null,
      clientIp: ip,
      connectionKey: jsonEncode([
        data['user_name'],
        data['domain'],
        ip,
        data['add_time'],
      ]),
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

  static bool _ok(Map<String, dynamic> data) =>
      (data['error'] ?? data['res']) == 'ok';

  static String _errorMessage(Map<String, dynamic> response, String fallback) {
    for (final key in ['error_msg', 'suc_msg']) {
      final value = response[key];
      if (value is String && value.trim().isNotEmpty) {
        return String.fromCharCodes(value.trim().runes.take(200));
      }
    }
    return fallback;
  }

  static String? _ipv4(Object? raw) {
    if (raw is! String) return null;
    final address = InternetAddress.tryParse(raw);
    return address?.type == InternetAddressType.IPv4 ? address!.address : null;
  }

  static Map<String, String> loginParameters({
    required String username,
    required String password,
    required String ip,
    required String token,
    String deviceName = 'Windows',
  }) {
    final digest = HMac(MD5Digest(), 64)
      ..init(KeyParameter(utf8.encode(token)));
    final md5 = _hex(digest.process(utf8.encode(password)));
    final details = jsonEncode({
      'username': username,
      'password': password,
      'ip': ip,
      'acid': _acId,
      'enc_ver': 'srun_bx1',
    });
    final info = '{SRBX1}${xencode(details, token)}';
    final checksum = [
      username,
      md5,
      _acId,
      ip,
      _n,
      _type,
      info,
    ].map((field) => token + field).join();
    return {
      'action': 'login',
      'username': username,
      'password': '{MD5}$md5',
      'info': info,
      'chksum': _hex(SHA1Digest().process(utf8.encode(checksum))),
      'ip': ip,
      'ac_id': _acId,
      'n': _n,
      'type': _type,
      'os': deviceName,
      'name': deviceName,
      'double_stack': '0',
    };
  }

  static String _hex(Uint8List bytes) =>
      bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();

  // SRun packs JavaScript string code units into little-endian words and
  // encodes the transformed bytes using its own Base64 alphabet.
  static String xencode(String input, String token) {
    if (input.isEmpty) return '';
    final words = _pack(input.codeUnits, includeLength: true);
    final key = _pack(token.codeUnits);
    while (key.length < 4) {
      key.add(0);
    }
    const delta = 0x9e3779b9;
    const mask = 0xffffffff;
    var z = words.last;
    var sum = 0;
    final rounds = 6 + 52 ~/ words.length;
    for (var round = 0; round < rounds; round++) {
      sum = (sum + delta) & mask;
      final e = (sum >>> 2) & 3;
      for (var i = 0; i < words.length; i++) {
        final y = words[(i + 1) % words.length];
        final mix =
            ((z >>> 5) ^ (y << 2)) +
            ((y >>> 3) ^ (z << 4) ^ (sum ^ y)) +
            (key[(i & 3) ^ e] ^ z);
        z = words[i] = (words[i] + mix) & mask;
      }
    }
    final bytes = ByteData(words.length * 4);
    for (var i = 0; i < words.length; i++) {
      bytes.setUint32(i * 4, words[i], Endian.little);
    }
    const standard =
        'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
    const custom =
        'LVoJPiCN2R8G90yg+hmFHuacZ1OWMnrsSTXkYpUq/3dlbfKwv6xztjI7DeBE45QA';
    return base64Encode(bytes.buffer.asUint8List()).split('').map((char) {
      return char == '=' ? char : custom[standard.indexOf(char)];
    }).join();
  }

  static List<int> _pack(List<int> units, {bool includeLength = false}) {
    final words = List<int>.filled((units.length + 3) ~/ 4, 0, growable: true);
    for (var i = 0; i < units.length; i++) {
      words[i ~/ 4] = (words[i ~/ 4] | (units[i] << (i % 4 * 8))) & 0xffffffff;
    }
    if (includeLength) words.add(units.length);
    return words;
  }
}
