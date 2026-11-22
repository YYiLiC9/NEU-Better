import 'dart:io';

/// 当前账号作用域：所有「用户数据」持久化文件都带上当前学号，
/// 避免同机多账号（如本科/研究生账号）互相串数据。
///
/// 账号 id 由登录态维护；未登录时退化为 `guest`。
/// 注意：登录凭据 / 会话等「用于恢复登录身份」的文件不使用本作用域。
class AccountScope {
  AccountScope._();

  static String _id = '';

  static String get id => _id;

  /// 设置当前账号（学号或任一稳定学生 id）。传入空则视为 guest。
  static void setAccount(String? studentId) {
    _id = _sanitize(studentId);
  }

  static void clear() {
    _id = '';
  }

  static String _sanitize(String? studentId) {
    final text = (studentId ?? '').trim().replaceAll(
      RegExp(r'[^0-9A-Za-z_-]'),
      '_',
    );
    return text.isEmpty ? 'guest' : text;
  }

  /// 把 `timetable.json` 变成 `timetable_<id>.json`。
  static String scopedName(String fileName, {String? account}) {
    final scope = account == null ? id : _sanitize(account);
    final dot = fileName.lastIndexOf('.');
    if (dot <= 0) {
      return '${fileName}_$scope';
    }
    return '${fileName.substring(0, dot)}_$scope${fileName.substring(dot)}';
  }

  /// 数据目录候选顺序（写时逐个尝试；读时同样顺序）。
  ///
  /// 稳定目录优先，保证应用更新/覆盖安装后数据仍在：
  /// - Windows：`%LOCALAPPDATA%\NEU Better`（与安装目录无关）；
  /// - Android：应用私有 `files/NEU Better`（`cache` 会被系统或覆盖安装清理）。
  /// 其余为历史位置，仅用于读取迁移。
  static List<String> get _dirs {
    final sep = Platform.pathSeparator;
    final dirs = <String>[];
    if (Platform.isAndroid) {
      dirs.add(
        '${Directory.systemTemp.parent.path}$sep'
        'files$sep'
        'NEU Better',
      );
      dirs.add(
        '${Directory.systemTemp.path}$sep'
        'NEU Better',
      );
      dirs.add(
        '${File(Platform.resolvedExecutable).parent.path}$sep'
        'data',
      );
      dirs.add(
        '${Directory.current.path}$sep'
        'data',
      );
    } else {
      final local = Platform.environment['LOCALAPPDATA'];
      if (local != null && local.isNotEmpty) {
        dirs.add(
          '$local$sep'
          'NEU Better',
        );
      }
      dirs.add(
        '${File(Platform.resolvedExecutable).parent.path}$sep'
        'data',
      );
      dirs.add(
        '${Directory.current.path}$sep'
        'data',
      );
      dirs.add(
        '${Directory.systemTemp.path}$sep'
        'NEU Better',
      );
    }
    return dirs;
  }

  static List<File> scopedFiles(String fileName, {String? account}) {
    final sep = Platform.pathSeparator;
    final name = scopedName(fileName, account: account);
    return [for (final dir in _dirs) File('$dir$sep$name')];
  }

  static List<File> legacyFiles(String fileName) {
    final sep = Platform.pathSeparator;
    return [for (final dir in _dirs) File('$dir$sep$fileName')];
  }
}
