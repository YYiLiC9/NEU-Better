import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../platform/windows_startup.dart';
import '../storage/account_scope.dart';
import 'app_font.dart';

/// 主题偏好：跟随系统 / 固定浅色 / 固定深色。
enum ThemePreference { system, light, dark }

enum FontSizePreference {
  small(0.9),
  medium(1.0),
  large(1.1),
  extraLarge(1.25);

  const FontSizePreference(this.scale);

  final double scale;
}

/// 每周起始日：周一 / 周日。
///
/// 仅影响课表“显示顺序”和“今天高亮”的排布；底层数据里 [CourseSession.day]
/// 的语义恒为 1=周一 … 7=周日，不随此设置改变。
enum WeekStart { monday, sunday }

/// 应用设置模型。所有字段都有安全的默认值，读取损坏的 JSON 时逐字段回退。
@immutable
class AppSettings {
  const AppSettings({
    this.themePreference = ThemePreference.system,
    this.fontPreference = AppFontPreference.bundled,
    this.importedFont,
    this.fontSizePreference = FontSizePreference.medium,
    this.scheduledTheme = false,
    this.darkStart = const TimeOfDay(hour: 19, minute: 0),
    this.lightStart = const TimeOfDay(hour: 7, minute: 0),
    this.minimizeOnClose = true,
    this.showTrayIcon = true,
    this.weekStart = WeekStart.monday,
    this.timetableWeekView = true,
    this.autoUpdate = true,
    this.autoStart = false,
    this.startMinimizedToTray = false,
    this.notifySources = const <String, bool>{},
  });

  final ThemePreference themePreference;
  final AppFontPreference fontPreference;
  final ImportedAppFont? importedFont;
  final FontSizePreference fontSizePreference;
  final bool scheduledTheme;
  final TimeOfDay darkStart;
  final TimeOfDay lightStart;
  final bool minimizeOnClose;
  final bool showTrayIcon;
  final WeekStart weekStart;
  final bool timetableWeekView;

  /// 是否自动检查并从 GitHub 更新。
  final bool autoUpdate;

  /// Windows 开机自启动（仅 Windows 生效，注册表 HKCU Run 项）。
  final bool autoStart;

  /// 开机启动时自动隐藏窗口到托盘（仅 Windows 且 autoStart 生效时有意义）。
  final bool startMinimizedToTray;

  /// 系统通知来源开关：`campus` / `dorm` / `mail` / `plugin:<id>`。
  /// 缺省未写入时：内置来源（campus/dorm/mail）默认开，插件来源默认关。
  final Map<String, bool> notifySources;

  AppSettings copyWith({
    ThemePreference? themePreference,
    AppFontPreference? fontPreference,
    ImportedAppFont? importedFont,
    FontSizePreference? fontSizePreference,
    bool? scheduledTheme,
    TimeOfDay? darkStart,
    TimeOfDay? lightStart,
    bool? minimizeOnClose,
    bool? showTrayIcon,
    WeekStart? weekStart,
    bool? timetableWeekView,
    bool? autoUpdate,
    bool? autoStart,
    bool? startMinimizedToTray,
    Map<String, bool>? notifySources,
  }) {
    return AppSettings(
      themePreference: themePreference ?? this.themePreference,
      fontPreference: fontPreference ?? this.fontPreference,
      importedFont: importedFont ?? this.importedFont,
      fontSizePreference: fontSizePreference ?? this.fontSizePreference,
      scheduledTheme: scheduledTheme ?? this.scheduledTheme,
      darkStart: darkStart ?? this.darkStart,
      lightStart: lightStart ?? this.lightStart,
      minimizeOnClose: minimizeOnClose ?? this.minimizeOnClose,
      showTrayIcon: showTrayIcon ?? this.showTrayIcon,
      weekStart: weekStart ?? this.weekStart,
      timetableWeekView: timetableWeekView ?? this.timetableWeekView,
      autoUpdate: autoUpdate ?? this.autoUpdate,
      autoStart: autoStart ?? this.autoStart,
      startMinimizedToTray: startMinimizedToTray ?? this.startMinimizedToTray,
      notifySources: notifySources ?? this.notifySources,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'themePreference': themePreference.name,
      'fontPreference': fontPreference.name,
      if (importedFont != null) 'importedFont': importedFont!.toJson(),
      'fontSizePreference': fontSizePreference.name,
      'scheduledTheme': scheduledTheme,
      'darkStart': _timeToJson(darkStart),
      'lightStart': _timeToJson(lightStart),
      'minimizeOnClose': minimizeOnClose,
      'showTrayIcon': showTrayIcon,
      'weekStart': weekStart.name,
      'timetableWeekView': timetableWeekView,
      'autoUpdate': autoUpdate,
      'autoStart': autoStart,
      'startMinimizedToTray': startMinimizedToTray,
      'notifySources': notifySources,
    };
  }

  /// 容错解析：任何字段缺失或类型错误都回退到默认值，绝不抛出。
  factory AppSettings.fromJson(Map<String, dynamic> json) {
    const defaults = AppSettings();
    final importedFont = ImportedAppFont.fromJson(json['importedFont']);
    return AppSettings(
      themePreference: _parseThemePreference(json['themePreference']),
      fontPreference: switch (json['fontPreference']) {
        'system' => AppFontPreference.system,
        'imported' when importedFont != null => AppFontPreference.imported,
        _ => AppFontPreference.bundled,
      },
      importedFont: importedFont,
      fontSizePreference: _parseFontSizePreference(json['fontSizePreference']),
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
      weekStart: _parseWeekStart(json['weekStart']),
      timetableWeekView: _parseBool(
        json['timetableWeekView'],
        defaults.timetableWeekView,
      ),
      autoUpdate: _parseBool(json['autoUpdate'], defaults.autoUpdate),
      autoStart: _parseBool(json['autoStart'], defaults.autoStart),
      startMinimizedToTray: _parseBool(
        json['startMinimizedToTray'],
        defaults.startMinimizedToTray,
      ),
      notifySources: _parseNotifySources(json['notifySources']),
    );
  }

  static Map<String, bool> _parseNotifySources(Object? value) {
    if (value is! Map) return const <String, bool>{};
    final result = <String, bool>{};
    for (final entry in value.entries) {
      final key = entry.key.toString().trim();
      if (key.isEmpty) continue;
      if (entry.value is bool) result[key] = entry.value as bool;
    }
    return result;
  }

  static WeekStart _parseWeekStart(Object? value) {
    if (value is String) {
      for (final weekStart in WeekStart.values) {
        if (weekStart.name == value) return weekStart;
      }
    }
    return WeekStart.monday;
  }

  static ThemePreference _parseThemePreference(Object? value) {
    if (value is String) {
      for (final preference in ThemePreference.values) {
        if (preference.name == value) return preference;
      }
    }
    return ThemePreference.system;
  }

  static FontSizePreference _parseFontSizePreference(Object? value) {
    for (final preference in FontSizePreference.values) {
      if (preference.name == value) return preference;
    }
    return FontSizePreference.medium;
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

  List<File> get _candidates => AccountScope.scopedFiles(_fileName);

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
    // 兼容旧版本未加账号后缀的 settings.json：读到即用（之后保存到账号文件）。
    for (final file in AccountScope.legacyFiles(_fileName)) {
      try {
        if (!await file.exists()) continue;
        final decoded = jsonDecode(await file.readAsString());
        if (decoded is Map) {
          return AppSettings.fromJson(Map<String, dynamic>.from(decoded));
        }
      } catch (error) {
        debugPrint('[settings] legacy read failed at ${file.path}: $error');
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
  AppFontPreference get fontPreference => _settings.fontPreference;
  ImportedAppFont? get importedFont => _settings.importedFont;
  FontSizePreference get fontSizePreference => _settings.fontSizePreference;
  bool get scheduledTheme => _settings.scheduledTheme;
  TimeOfDay get darkStart => _settings.darkStart;
  TimeOfDay get lightStart => _settings.lightStart;
  bool get minimizeOnClose => _settings.minimizeOnClose;
  bool get showTrayIcon => _settings.showTrayIcon;
  WeekStart get weekStart => _settings.weekStart;
  bool get timetableWeekView => _settings.timetableWeekView;
  bool get autoStart => _settings.autoStart;
  bool get autoUpdate => _settings.autoUpdate;
  bool get startMinimizedToTray => _settings.startMinimizedToTray;
  Brightness get platformBrightness => _platformBrightness;

  Map<String, bool> get notifySources => _settings.notifySources;

  /// 指定来源的系统通知是否开启（内置来源默认开、插件来源默认关）。
  bool notifyEnabled(String key) {
    return _settings.notifySources[key] ?? !key.startsWith('plugin:');
  }

  void setNotifyEnabled(String key, bool value) {
    if (notifyEnabled(key) == value) return;
    final next = Map<String, bool>.from(_settings.notifySources);
    next[key] = value;
    _settings = _settings.copyWith(notifySources: next);
    _commit();
  }

  /// 确保某来源在设置里有一项（插件安装后使用；默认关闭，避免新插件默认打扰）。
  void ensureNotifySource(String key, {bool enabled = false}) {
    if (_settings.notifySources.containsKey(key)) return;
    final next = Map<String, bool>.from(_settings.notifySources);
    next[key] = enabled;
    _settings = _settings.copyWith(notifySources: next);
    _commit();
  }

  /// 移除某来源（插件卸载后使用）。
  void removeNotifySource(String key) {
    if (!_settings.notifySources.containsKey(key)) return;
    final next = Map<String, bool>.from(_settings.notifySources);
    next.remove(key);
    _settings = _settings.copyWith(notifySources: next);
    _commit();
  }

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
    // 已开启自启动时，每次启动都按当前 exe 路径重写一次 Run 项，
    // 避免安装目录变化后仍指向旧路径。
    if (loaded.autoStart && Platform.isWindows) {
      unawaited(WindowsStartup.setEnabled(true));
    }
  }

  void setThemePreference(ThemePreference preference) {
    if (_settings.themePreference == preference) return;
    _settings = _settings.copyWith(themePreference: preference);
    _commit();
  }

  void setFontPreference(AppFontPreference preference) {
    if (_settings.fontPreference == preference ||
        (preference == AppFontPreference.imported && importedFont == null)) {
      return;
    }
    _settings = _settings.copyWith(fontPreference: preference);
    _commit();
  }

  void setImportedFont(ImportedAppFont font) {
    _settings = _settings.copyWith(
      fontPreference: AppFontPreference.imported,
      importedFont: font,
    );
    _commit();
  }

  void setFontSizePreference(FontSizePreference preference) {
    if (_settings.fontSizePreference == preference) return;
    _settings = _settings.copyWith(fontSizePreference: preference);
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

  void setWeekStart(WeekStart value) {
    if (_settings.weekStart == value) return;
    _settings = _settings.copyWith(weekStart: value);
    _commit();
  }

  void setTimetableWeekView(bool value) {
    if (_settings.timetableWeekView == value) return;
    _settings = _settings.copyWith(timetableWeekView: value);
    _commit();
  }

  void setAutoStart(bool value) {
    if (_settings.autoStart == value) return;
    _settings = _settings.copyWith(autoStart: value);
    _commit();
    if (Platform.isWindows) {
      unawaited(WindowsStartup.setEnabled(value));
    }
  }

  void setAutoUpdate(bool value) {
    if (_settings.autoUpdate == value) return;
    _settings = _settings.copyWith(autoUpdate: value);
    _commit();
  }

  void setStartMinimizedToTray(bool value) {
    if (_settings.startMinimizedToTray == value) return;
    _settings = _settings.copyWith(startMinimizedToTray: value);
    _commit();
  }

  /// 账号切换后重新读取该账号的持久化设置。
  Future<void> reload() async {
    _loaded = false;
    await load();
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
