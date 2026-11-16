import 'package:flutter_test/flutter_test.dart';
import 'package:neu_better_pro/core/settings/app_settings.dart';

void main() {
  test('startMinimizedToTray 默认 false 且 JSON 往返保留', () {
    expect(const AppSettings().startMinimizedToTray, isFalse);
    const enabled = AppSettings(autoStart: true, startMinimizedToTray: true);
    final restored = AppSettings.fromJson(
      Map<String, dynamic>.from(enabled.toJson()),
    );
    expect(restored.startMinimizedToTray, isTrue);
    expect(restored.autoStart, isTrue);
    expect(restored.copyWith(startMinimizedToTray: false).startMinimizedToTray,
        isFalse);
  });
}
