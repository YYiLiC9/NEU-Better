import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neu_better_pro/core/auth/auth_exception.dart';
import 'package:neu_better_pro/core/network/neu_cas_client.dart';
import 'package:neu_better_pro/core/network/srun_portal_client.dart';

void main() {
  const user = '20260001@neu';
  const password = 'synthetic-pass';
  const ip = '192.0.2.7';
  const ticket = 'ST-synthetic-ipgw-tpass';
  const casForm =
      '<input name="lt" value="test-lt">'
      '<input name="execution" value="test-execution">';

  test('parses school billing, the online session and gateway errors', () {
    final online = SrunPortalClient.parseStatus('''
      neuBetterStatus({"error":"ok","online_ip":"192.0.2.7","add_time":90,
        "user_name":"20260001","domain":"neu",
        "user_balance":"-1.50","sum_bytes":"5368709120"});
    ''');
    expect(online.online, isTrue);
    expect(online.balance, -1.5);
    expect(online.sumBytes, 5368709120);
    expect(online.clientIp, ip);
    expect(online.username, user);
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

  test(
    'gets an IPGW service ticket without contacting its HTTP callback',
    () async {
      final service = SrunPortalClient.ssoService;
      final requests = <RequestOptions>[];
      final dio = Dio()
        ..interceptors.add(
          InterceptorsWrapper(
            onRequest: (request, handler) {
              requests.add(request);
              if (request.method == 'GET') {
                handler.resolve(
                  Response<String>(
                    requestOptions: request,
                    statusCode: 200,
                    data: casForm,
                    headers: Headers.fromMap({
                      'set-cookie': ['CAS=test-only'],
                    }),
                  ),
                );
                return;
              }
              handler.resolve(
                Response<String>(
                  requestOptions: request,
                  statusCode: 302,
                  headers: Headers.fromMap({
                    'location': ['$service&ticket=$ticket'],
                  }),
                ),
              );
            },
          ),
        );
      final client = NeuCasClient(dio: dio);
      addTearDown(client.close);
      final result = await client.requestServiceTicket(
        username: user,
        password: password,
        service: service,
      );
      expect(result, ticket);
      expect(requests.map((request) => request.method), ['GET', 'POST']);
      expect(requests.map((request) => request.uri.host).toSet(), {
        'pass.neu.edu.cn',
      });
      expect(requests.map((request) => request.uri.scheme).toSet(), {'https'});
      expect(
        requests.first.uri.queryParameters['service'],
        'http://ipgw.neu.edu.cn/srun_portal_sso?ac_id=1',
      );
      expect(requests.last.headers['cookie'], 'CAS=test-only');
    },
  );

  for (final location in [
    'https://example.invalid/tpass/login?ticket=$ticket',
    'http://ipgw.neu.edu.cn/srun_portal_sso?ac_id=2&ticket=$ticket',
  ]) {
    test('rejects an unexpected CAS callback $location', () async {
      final requests = <Uri>[];
      final dio = Dio()
        ..interceptors.add(
          InterceptorsWrapper(
            onRequest: (request, handler) {
              requests.add(request.uri);
              if (request.method == 'GET') {
                handler.resolve(
                  Response<String>(
                    requestOptions: request,
                    statusCode: 200,
                    data: casForm,
                  ),
                );
                return;
              }
              handler.resolve(
                Response<String>(
                  requestOptions: request,
                  statusCode: 307,
                  headers: Headers.fromMap({
                    'location': [location],
                  }),
                ),
              );
            },
          ),
        );
      final client = NeuCasClient(dio: dio);
      addTearDown(client.close);
      await expectLater(
        client.requestServiceTicket(
          username: user,
          password: password,
          service: SrunPortalClient.ssoService,
        ),
        throwsA(
          isA<AuthException>().having(
            (error) => error.message,
            'message',
            contains('意外的服务地址'),
          ),
        ),
      );
      expect(requests.map((uri) => uri.host), [
        'pass.neu.edu.cn',
        'pass.neu.edu.cn',
      ]);
    });
  }

  test('redeems the ticket on the selected HTTPS gateway transport', () async {
    final requests = <Uri>[];
    final client = SrunPortalClient(
      readResponse: (uri) async {
        requests.add(uri);
        return '{"code":0,"message":"认证成功"}';
      },
    );
    addTearDown(client.close);
    client.useSourceAddress(ip);
    await client.loginWithTicket(ticket);
    final url = requests.single;
    expect(url.scheme, 'https');
    expect(url.host, 'ipgw.neu.edu.cn');
    expect(url.path, '/v1/srun_portal_sso');
    expect(url.queryParameters, {'ac_id': '1', 'ticket': ticket});
  });

  for (final (response, failure) in [
    ('{"code":1,"message":"票据无效"}', '票据无效'),
    ('{"code":7}', 'code=7'),
    (
      '{"code":0,"Redirect":"https://pass.neu.edu.cn/tpass/login"}',
      '重新进行统一身份认证',
    ),
  ]) {
    test('reports rejected SSO redemption $response', () async {
      final client = SrunPortalClient(readResponse: (_) async => response);
      addTearDown(client.close);
      await expectLater(
        client.loginWithTicket(ticket),
        throwsA(
          isA<SrunRejected>().having(
            (error) => error.message,
            'message',
            contains(failure),
          ),
        ),
      );
    });
  }

  test('signs out the observed session with the campus logout endpoint', () async {
    final requests = <Uri>[];
    final client = SrunPortalClient(
      readResponse: (uri) async {
        requests.add(uri);
        return '{"error":"ok"}';
      },
    );
    addTearDown(client.close);
    final status = SrunPortalClient.parseStatus(
      '{"error":"ok","online_ip":"$ip","user_name":"20260001","domain":"neu"}',
    );
    await client.logout(status);
    final url = requests.single;
    expect(url.path, '/cgi-bin/srun_portal');
    expect(url.queryParameters, containsPair('action', 'logout'));
    expect(url.queryParameters, containsPair('username', user));
    expect(url.queryParameters, containsPair('ip', ip));
    expect(url.queryParameters, containsPair('ac_id', '1'));
    expect(url.queryParameters, isNot(contains('password')));
  });
}
