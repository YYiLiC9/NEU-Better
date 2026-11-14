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
    final text = (studentId ?? '')
        .trim()
        .replaceAll(RegExp(r'[^0-9A-Za-z_-]'), '_');
    return text.isEmpty ? 'guest' : text;
  }

  /// 把 `timetable.json` 变成 `timetable_<id>.json`。
  static String scopedName(String fileName) {
    final dot = fileName.lastIndexOf('.');
    if (dot <= 0) return '${fileName}_' '$id';
    return '${fileName.substring(0, dot)}_$id${fileName.substring(dot)}';
  }

  /// 数据目录候选顺序（写时逐个尝试；读时同样顺序）。
  static List<String> get _dirs {
    final sep = Platform.pathSeparator;
    final dirs = <String>[
      '${File(Platform.resolvedExecutable).parent.path}$sep' 'data',
      '${Directory.current.path}$sep' 'data',
      // Android：systemTemp 是 cache（覆盖安装会清）；其父目录下 files 才是持久私有目录。
      if (Platform.isAndroid)
        '${Directory.systemTemp.parent.path}$sep' 'files$sep' 'NEU Better',
      '${Directory.systemTemp.path}$sep' 'NEU Better',
    ];
    final local = Platform.environment['LOCALAPPDATA'];
    if (local != null && local.isNotEmpty) {
      dirs.add('$local$sep' 'NEU Better');
    }
    return dirs;
  }

  static List<File> scopedFiles(String fileName) {
    final sep = Platform.pathSeparator;
    final name = scopedName(fileName);
    return [for (final dir in _dirs) File('$dir$sep$name')];
  }

  static List<File> legacyFiles(String fileName) {
    final sep = Platform.pathSeparator;
    return [for (final dir in _dirs) File('$dir$sep$fileName')];
  }
}
