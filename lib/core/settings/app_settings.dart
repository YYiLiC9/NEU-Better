import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/legacy.dart';

/// 主题偏好：跟随系统 / 固定浅色 / 固定深色。
enum ThemePreference { system, light, dark }

/// 应用设置模型。所有字段都有安全的默认值，读取损坏的 JSON 时逐字段回退。
@immutable
class AppSettings {
  const AppSettings({
    this.themePreference = ThemePreference.system,
    this.scheduledTheme = false,
    this.darkStart = const TimeOfDay(hour: 19, minute: 0),
    this.lightStart = const TimeOfDay(hour: 7, minute: 0),
    this.minimizeOnClose = true,
    this.showTrayIcon = true,
  });

  final ThemePreference themePreference;
  final bool scheduledTheme;
  final TimeOfDay darkStart;
  final TimeOfDay lightStart;
  final bool minimizeOnClose;
  final bool showTrayIcon;

  AppSettings copyWith({
    ThemePreference? themePreference,
    bool? scheduledTheme,
    TimeOfDay? darkStart,
    TimeOfDay? lightStart,
    bool? minimizeOnClose,
    bool? showTrayIcon,
  }) {
    return AppSettings(
      themePreference: themePreference ?? this.themePreference,
      scheduledTheme: scheduledTheme ?? this.scheduledTheme,
      darkStart: darkStart ?? this.darkStart,
      lightStart: lightStart ?? this.lightStart,
      minimizeOnClose: minimizeOnClose ?? this.minimizeOnClose,
      showTrayIcon: showTrayIcon ?? this.showTrayIcon,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'themePreference': themePreference.name,
      'scheduledTheme': scheduledTheme,
      'darkStart': _timeToJson(darkStart),
      'lightStart': _timeToJson(lightStart),
      'minimizeOnClose': minimizeOnClose,
      'showTrayIcon': showTrayIcon,
    };
  }

  /// 容错解析：任何字段缺失或类型错误都回退到默认值，绝不抛出。
  factory AppSettings.fromJson(Map<String, dynamic> json) {
    const defaults = AppSettings();
    return AppSettings(
      themePreference: _parseThemePreference(json['themePreference']),
      scheduledTheme: _parseBool(
        json['scheduledTheme'],
        defaults.scheduledTheme,
      ),
      darkStart: _parseTime(json['darkStart'], defaults.darkStart),
      lightStart: _parseTime(json['lightStart'], defaults.lightStart),
      minimizeOnClose: _parseBool(
        json['minimizeOnClose'],
        defaults.minimizeOnClose,
      ),
      showTrayIcon: _parseBool(json['showTrayIcon'], defaults.showTrayIcon),
    );
  }

  static ThemePreference _parseThemePreference(Object? value) {
    if (value is String) {
      for (final preference in ThemePreference.values) {
        if (preference.name == value) return preference;
      }
    }
    return ThemePreference.system;
  }

  static bool _parseBool(Object? value, bool fallback) {
    return value is bool ? value : fallback;
  }

  static Map<String, dynamic> _timeToJson(TimeOfDay time) {
    return <String, dynamic>{'hour': time.hour, 'minute': time.minute};
  }

  static TimeOfDay _parseTime(Object? value, TimeOfDay fallback) {
    if (value is Map) {
      final hour = value['hour'];
      final minute = value['minute'];
      if (hour is int && minute is int && _isValidTime(hour, minute)) {
        return TimeOfDay(hour: hour, minute: minute);
      }
      return fallback;
    }
    if (value is String) {
      final parts = value.split(':');
      if (parts.length == 2) {
        final hour = int.tryParse(parts[0]);
        final minute = int.tryParse(parts[1]);
        if (hour != null && minute != null && _isValidTime(hour, minute)) {
          return TimeOfDay(hour: hour, minute: minute);
        }
      }
    }
    return fallback;
  }

  static bool _isValidTime(int hour, int minute) {
    return hour >= 0 && hour < 24 && minute >= 0 && minute < 60;
  }
}

/// settings.json 持久化。路径策略与 [ElectricityStore] 一致：
/// exe 同目录 data\ → cwd\data → systemTemp\NEU Better → LOCALAPPDATA\NEU Better。
class AppSettingsStore {
  const AppSettingsStore();

  static const _fileName = 'settings.json';

  List<File> get _candidates {
    final separator = Platform.pathSeparator;
    final files = <File>[
      File(
        '${File(Platform.resolvedExecutable).parent.path}$separator'
        'data$separator$_fileName',
      ),
      File(
        '${Directory.current.path}$separator'
        'data$separator$_fileName',
      ),
      File(
        '${Directory.systemTemp.path}$separator'
        'NEU Better$separator$_fileName',
      ),
    ];
    final local = Platform.environment['LOCALAPPDATA'];
    if (local != null && local.isNotEmpty) {
      files.add(
        File(
          '$local$separator'
          'NEU Better$separator$_fileName',
        ),
      );
    }
    return files;
  }

  Future<AppSettings> read() async {
    for (final file in _candidates) {
      try {
        if (!await file.exists()) continue;
        final decoded = jsonDecode(await file.readAsString());
        if (decoded is Map) {
          return AppSettings.fromJson(Map<String, dynamic>.from(decoded));
        }
      } catch (error) {
        debugPrint('[settings] read failed at ${file.path}: $error');
      }
    }
    return const AppSettings();
  }

  Future<void> save(AppSettings settings) async {
    final payload = jsonEncode(settings.toJson());
    Object? lastError;
    for (final file in _candidates) {
      try {
        await file.parent.create(recursive: true);
        await file.writeAsString(payload, flush: true);
        debugPrint('[settings] saved to ${file.path}');
        return;
      } catch (error) {
        lastError = error;
        debugPrint('[settings] save failed at ${file.path}: $error');
      }
    }
    if (lastError != null) {
      debugPrint('[settings] no writable path: $lastError');
    }
  }
}

/// 设置状态：修改即通知 UI，并异步写回 settings.json（串行写避免顺序错乱）。
class AppSettingsController extends ChangeNotifier {
  AppSettingsController({
    AppSettingsStore? store,
    AppSettings initial = const AppSettings(),
    Brightness? platformBrightness,
  }) : _store = store ?? const AppSettingsStore(),
       _settings = initial,
       _platformBrightness =
           platformBrightness ??
           PlatformDispatcher.instance.platformBrightness {
    _lastResolvedDark = isDarkNow;
  }

  final AppSettingsStore _store;
  AppSettings _settings;
  Brightness _platformBrightness;
  late bool _lastResolvedDark;
  Future<void> _pendingSave = Future<void>.value();
  bool _loaded = false;

  AppSettings get settings => _settings;
  ThemePreference get themePreference => _settings.themePreference;
  bool get scheduledTheme => _settings.scheduledTheme;
  TimeOfDay get darkStart => _settings.darkStart;
  TimeOfDay get lightStart => _settings.lightStart;
  bool get minimizeOnClose => _settings.minimizeOnClose;
  bool get showTrayIcon => _settings.showTrayIcon;
  Brightness get platformBrightness => _platformBrightness;

  /// 当前实际应使用的明暗状态（跟随系统 / 浅色 / 深色三选一）。
  bool get isDarkNow => isDarkNowAt(DateTime.now());

  bool isDarkNowAt(DateTime time) {
    return switch (_settings.themePreference) {
      ThemePreference.system => _platformBrightness == Brightness.dark,
      ThemePreference.light => false,
      ThemePreference.dark => true,
    };
  }

  /// 应用启动时加载持久化设置。重复调用安全。
  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    final loaded = await _store.read();
    _settings = loaded;
    _lastResolvedDark = isDarkNow;
    notifyListeners();
  }

  void setThemePreference(ThemePreference preference) {
    if (_settings.themePreference == preference) return;
    _settings = _settings.copyWith(themePreference: preference);
    _commit();
  }

  void setScheduledTheme(bool value) {
    if (_settings.scheduledTheme == value) return;
    _settings = _settings.copyWith(scheduledTheme: value);
    _commit();
  }

  void setDarkStart(TimeOfDay time) {
    if (_settings.darkStart == time) return;
    _settings = _settings.copyWith(darkStart: time);
    _commit();
  }

  void setLightStart(TimeOfDay time) {
    if (_settings.lightStart == time) return;
    _settings = _settings.copyWith(lightStart: time);
    _commit();
  }

  void setMinimizeOnClose(bool value) {
    if (_settings.minimizeOnClose == value) return;
    _settings = _settings.copyWith(minimizeOnClose: value);
    _commit();
  }

  void setShowTrayIcon(bool value) {
    if (_settings.showTrayIcon == value) return;
    _settings = _settings.copyWith(showTrayIcon: value);
    _commit();
  }

  /// 系统亮度变化时由根组件调用。
  void updatePlatformBrightness(Brightness brightness) {
    if (_platformBrightness == brightness) return;
    _platformBrightness = brightness;
    _lastResolvedDark = isDarkNow;
    notifyListeners();
  }

  /// 每分钟由根组件调用：只有实际明暗状态变化时才通知重建。
  void refreshSchedule() {
    final resolved = isDarkNow;
    if (resolved == _lastResolvedDark) return;
    _lastResolvedDark = resolved;
    notifyListeners();
  }

  void _commit() {
    _lastResolvedDark = isDarkNow;
    notifyListeners();
    final snapshot = _settings;
    _pendingSave = _pendingSave.then((_) => _store.save(snapshot));
  }

  /// 等待所有排队中的写盘完成（测试 / 退出前可用）。
  Future<void> flush() => _pendingSave;
}

final appSettingsProvider = ChangeNotifierProvider<AppSettingsController>((
  ref,
) {
  final controller = AppSettingsController();
  unawaited(controller.load());
  return controller;
});
