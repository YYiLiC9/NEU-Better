import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:neu_better_pro/core/platform/windows_wifi.dart';

void main() {
  const disconnected = '''
    Name : WLAN 2
    State : disconnected
    Radio status : Hardware On
                   Software On
  ''';
  final cases = <String, String>{
    'no adapter': 'There is no wireless interface on the system.',
    'radio off': disconnected.replaceFirst('Software On', 'Software Off'),
    'location denied': 'Location permission is required. Access is denied.',
  };
  for (final entry in cases.entries) {
    test('reports ${entry.key} without attempting to connect', () async {
      final wifi = WindowsWifi(
        run: (args) async {
          expect(args, ['show', 'interfaces']);
          return ProcessResult(0, 0, entry.value, '');
        },
      );
      await expectLater(
        wifi.connect('NEU'),
        throwsA(isA<WindowsWifiException>()),
      );
    });
  }

  test('reuses the Windows profile and waits for the matching SSID', () async {
    bool connected = false;
    final wifi = WindowsWifi(
      run: (args) async {
        if (args[0] == 'connect') {
          expect(args, ['connect', 'name=NEU', 'ssid=NEU', 'interface=WLAN 2']);
          connected = true;
        }
        final value = connected
            ? '''
        名称 : WLAN 2
        状态 : 已连接
        BSSID : 00:11:22:33:44:55
        SSID : NEU
      '''
            : disconnected;
        return ProcessResult(0, 0, utf8.encode(value), const <int>[]);
      },
    );
    await wifi.connect('NEU');
    expect(await wifi.currentSsid(), 'NEU');
  });

  test(
    'uses the selected WLAN interface and ignores link-local addresses',
    () async {
      final wifi = WindowsWifi(
        run: (args) async {
          if (args.first == 'interface') {
            expect(args, [
              'interface',
              'ipv4',
              'show',
              'addresses',
              'name=WLAN 2',
            ]);
            return ProcessResult(
              0,
              0,
              utf8.encode('''
          IP 地址 : 169.254.3.9
          IP 地址 : 192.0.2.9
        '''),
              const <int>[],
            );
          }
          return ProcessResult(0, 0, '''
        Name : Wi-Fi
        State : connected
        SSID : Other
        Name : WLAN 2
        State : connected
        SSID : NEU
      ''', '');
        },
      );
      expect(await wifi.ipv4Address('NEU'), '192.0.2.9');
      expect(await wifi.ipv4Address('Offline'), isNull);
    },
  );

  test(
    'creates an escaped current-user profile only for a confirmed open SSID',
    () async {
      bool connected = false;
      String? config;
      final wifi = WindowsWifi(
        run: (args) async {
          if (args[0] == 'show' && args[1] == 'profile') {
            return ProcessResult(0, 1, 'The profile is not found.', '');
          }
          if (args[0] == 'show' && args[1] == 'networks') {
            return ProcessResult(0, 0, '''
          SSID 1 : Private
              Authentication : WPA2-Personal
              Encryption : CCMP
          SSID 2 : NEU & Test
              Authentication : Open
              Encryption : None
        ''', '');
          }
          if (args[0] == 'add') {
            expect(args.last, 'user=current');
            config = args[2].substring('filename='.length);
            final xml = await File(config!).readAsString();
            expect(xml, contains('<name>NEU &amp; Test</name>'));
            expect(xml, contains('<hex>4E455520262054657374</hex>'));
            expect(xml, contains('<connectionMode>manual</connectionMode>'));
          }
          if (args[0] == 'connect') connected = true;
          final output = connected
              ? '''
        Name : WLAN 2
        State : connected
        SSID : NEU & Test
      '''
              : disconnected;
          return ProcessResult(0, 0, output, '');
        },
      );
      await expectLater(
        wifi.connect('Private'),
        throwsA(
          isA<WindowsWifiException>().having(
            (error) => error.message,
            'message',
            contains('需要密码'),
          ),
        ),
      );
      expect(config, isNull);
      await expectLater(
        wifi.connect('Missing'),
        throwsA(
          isA<WindowsWifiException>().having(
            (error) => error.message,
            'message',
            contains('找不到'),
          ),
        ),
      );
      expect(config, isNull);
      await wifi.connect('NEU & Test');
      expect(config, isNotNull);
      expect(await File(config!).exists(), isFalse);
    },
  );
}
