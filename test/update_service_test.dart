import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:neu_better_pro/core/update/update_service.dart';

void main() {
  group('compareVersions', () {
    test('detects newer, equal and older versions', () {
      expect(compareVersions('0.2.0', '0.1.0'), greaterThan(0));
      expect(compareVersions('0.1.0', '0.2.0'), lessThan(0));
      expect(compareVersions('0.1.0', '0.1.0'), 0);
      expect(compareVersions('v0.1.0', '0.1.0'), 0);
      expect(compareVersions('1.0', '0.9.9'), greaterThan(0));
    });
  });

  group('UpdateInfoParser.fromRelease', () {
    test('parses tag, notes and picks platform assets', () {
      final info = UpdateInfoParser.fromRelease({
        'tag_name': 'v0.2.0',
        'body': '修复若干问题',
        'html_url': 'https://github.com/YYiLiC9/NEU-Better/releases/tag/v0.2.0',
        'assets': [
          {
            'name': 'NEU-Better-0.2.0-windows-x64.zip',
            'browser_download_url': 'https://example.com/win.zip',
          },
          {
            'name': 'NEU-Better-0.2.0-android.apk',
            'browser_download_url': 'https://example.com/app.apk',
          },
        ],
      });
      expect(info, isNotNull);
      expect(info!.version, '0.2.0');
      expect(info.notes, '修复若干问题');
      expect(info.windowsUrl, 'https://example.com/win.zip');
      expect(info.androidUrl, 'https://example.com/app.apk');
      expect(info.windowsFileName, 'NEU-Better-0.2.0-windows-x64.zip');
    });

    test('prefers windows setup .exe over zip when both exist', () {
      final info = UpdateInfoParser.fromRelease({
        'tag_name': 'v0.4.1',
        'assets': [
          {
            'name': 'NEU-Better-0.4.1-windows-x64.zip',
            'browser_download_url': 'https://example.com/win.zip',
            'size': 100,
          },
          {
            'name': 'NEU-Better-0.4.1-windows-x64-setup.exe',
            'browser_download_url': 'https://example.com/setup.exe',
            'size': 200,
          },
        ],
      });
      expect(info, isNotNull);
      expect(info!.windowsUrl, 'https://example.com/setup.exe');
      expect(
        info.windowsFileName,
        'NEU-Better-0.4.1-windows-x64-setup.exe',
      );
      expect(info.windowsSize, 200);
    });

    test('returns null without tag', () {
      expect(UpdateInfoParser.fromRelease({'body': 'x'}), isNull);
    });
  });

  group('isCompletePackage', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('upd_test_'));
    tearDown(() => dir.deleteSync(recursive: true));

    test('accepts exe with MZ header and zip/apk with PK header', () {
      final exe = File('${dir.path}/setup.exe')
        ..writeAsBytesSync([
          0x4D,
          0x5A,
          ...List<int>.filled(1024 * 1024, 0),
        ]);
      final zip = File('${dir.path}/pkg.zip')
        ..writeAsBytesSync([
          0x50,
          0x4B,
          ...List<int>.filled(1024 * 1024, 0),
        ]);
      expect(UpdateInfo.isCompletePackage(exe, null), isTrue);
      expect(UpdateInfo.isCompletePackage(zip, null), isTrue);
    });

    test('rejects exe with wrong header', () {
      final bad = File('${dir.path}/bad.exe')
        ..writeAsBytesSync(List<int>.filled(1024 * 1024, 0x41));
      expect(UpdateInfo.isCompletePackage(bad, null), isFalse);
    });
  });
}
