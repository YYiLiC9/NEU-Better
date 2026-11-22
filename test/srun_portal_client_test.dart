import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neu_better_pro/core/network/srun_portal_client.dart';

void main() {
  const user = '20260001@neu';
  const password = 'synthetic-pass';
  const ip = '192.0.2.7';
  const token = '0123456789abcdef0123456789abcdef';

  test('matches the SRun xencode and login checksum reference vectors', () {
    expect(SrunPortalClient.xencode('NEU测试', 'abc'), 'eqFzmXPyEdGqzub7');
    expect(SrunPortalClient.xencode('', 'abc'), isEmpty);
    final fields = SrunPortalClient.loginParameters(
      username: user,
      password: password,
      ip: ip,
      token: token,
    );
    expect(fields['password'], '{MD5}0f097a97e3e387c03817bd9add8ebc3c');
    expect(
      fields['info'],
      '{SRBX1}rlsKHk7i/pVpIk4cd4Y3HBzxD1wQ6zjs4BeH2HkCnAh0HQWOrFn28XgCm5V2'
      'muiNj7KLd0T/16Er0Sx2K4tqShDv04S0Z4arjzOi5V1CGFHqVjBf2QOgDh2csH'
      'kscCO5rnNU+mzHzyB9IQ1F',
    );
    expect(fields['chksum'], '01d4749e44598a24d04dea574aab4ee28d14ef48');
    expect(fields['ac_id'], '1');
    expect(fields['double_stack'], '0');
  });

  test('parses cumulative billing, an offline address, and gateway errors', () {
    final online = SrunPortalClient.parseStatus('''
      neuBetterStatus({"error":"ok","online_ip":"192.0.2.7","add_time":90,
        "user_balance":"-1.50","sum_bytes":"5368709120"});
    ''');
    expect(online.online, isTrue);
    expect(online.balance, -1.5);
    expect(online.sumBytes, 5368709120);
    expect(online.clientIp, ip);
    expect(online.connectionKey, isNotNull);
    expect(
      SrunPortalClient.parseStatus('{"error":"ok","sum_bytes":-1}').sumBytes,
      isNull,
    );
    final offline = SrunPortalClient.parseStatus(
      'neuBetterStatus({"res":"not_online_error","client_ip":"192.0.2.7"})',
    );
    expect(offline.online, isFalse);
    expect(offline.clientIp, ip);
    expect(
      () => SrunPortalClient.parseStatus(
        '{"error":"server_error","error_msg":"测试网关错误"}',
      ),
      throwsA(
        isA<SrunRejected>().having(
          (error) => error.message,
          'message',
          '测试网关错误',
        ),
      ),
    );
    expect(
      () => SrunPortalClient.parseStatus('<html>redirect</html>'),
      throwsFormatException,
    );
  });

  test('uses the mobile Wi-Fi transport for both SRun steps', () async {
    final requests = <Uri>[];
    final client = SrunPortalClient(
      deviceName: 'Android',
      readResponse: (uri) async {
        requests.add(uri);
        return uri.path.endsWith('get_challenge')
            ? '{"error":"ok","challenge":"$token","client_ip":"$ip"}'
            : '{"error":"ok"}';
      },
    );
    addTearDown(client.close);
    client.useSourceAddress(ip);
    await client.login(username: user, password: password, clientIp: ip);
    expect(requests.map((url) => url.scheme), ['https', 'https']);
    expect(requests.map((url) => url.path), [
      '/cgi-bin/get_challenge',
      '/cgi-bin/srun_portal',
    ]);
    expect(requests.last.queryParameters['os'], 'Android');
  });

  test('requests the challenge then authenticates over HTTPS and surfaces rejection', () async {
    final requests = <Uri>[];
    final dio = Dio()
      ..interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            requests.add(options.uri);
            expect(options.followRedirects, isFalse);
            final body = options.uri.path.endsWith('get_challenge')
                ? '{"error":"ok","challenge":"$token","client_ip":"$ip"}'
                : '{"res":"fail","error_msg":"密码错误"}';
            handler.resolve(
              Response<String>(
                requestOptions: options,
                data: 'neuBetterStatus($body);',
              ),
            );
          },
        ),
      );
    final client = SrunPortalClient(dio: dio);
    addTearDown(client.close);
    await expectLater(
      client.login(username: user, password: password),
      throwsA(
        isA<SrunRejected>().having((error) => error.message, 'message', '密码错误'),
      ),
    );
    expect(requests.map((url) => url.scheme), ['https', 'https']);
    expect(requests.map((url) => url.host), [
      'ipgw.neu.edu.cn',
      'ipgw.neu.edu.cn',
    ]);
    expect(requests.map((url) => url.path), [
      '/cgi-bin/get_challenge',
      '/cgi-bin/srun_portal',
    ]);
    expect(requests.first.queryParameters['username'], user);
    expect(requests.last.queryParameters['ip'], ip);
    expect(requests.last.queryParameters['password'], startsWith('{MD5}'));
    expect(requests.last.toString(), isNot(contains(password)));
  });
}
