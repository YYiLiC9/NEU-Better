import 'package:flutter_test/flutter_test.dart';
import 'package:neu_better_pro/core/settings/app_settings.dart';

void main() {
  test('app settings persist autoStart flag', () {
    const settings = AppSettings(autoStart: true);
    final json = settings.toJson();
    expect(json['autoStart'], true);
    final restored = AppSettings.fromJson(json);
    expect(restored.autoStart, true);
    expect(restored.copyWith(autoStart: false).autoStart, false);
    expect(const AppSettings().autoStart, false);
  });
}
