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
    });

    test('returns null without tag', () {
      expect(UpdateInfoParser.fromRelease({'body': 'x'}), isNull);
    });
  });
}
