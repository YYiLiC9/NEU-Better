import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:neu_better_pro/core/update/update_installer.dart';

void main() {
  test('detects Inno Setup installed directory by unins000.exe', () {
    final dir = Directory.systemTemp.createTempSync('update_mode_test');
    addTearDown(() => dir.deleteSync(recursive: true));

    expect(UpdateInstaller.isSetupInstalledIn(dir.path), isFalse);
    File(
      '${dir.path}${Platform.pathSeparator}unins000.exe',
    ).writeAsBytesSync(const [0x4D, 0x5A]);
    expect(UpdateInstaller.isSetupInstalledIn(dir.path), isTrue);
  });
}
