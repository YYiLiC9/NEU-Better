/// 邮件列表/详情的时间展示：今天显示「HH:mm」，今年显示「MM-dd HH:mm」，
/// 更早显示「yyyy-MM-dd」。无值时返回空串。
String formatMailDate(DateTime? date, {DateTime? now}) {
  if (date == null) return '';
  final local = date.toLocal();
  final current = (now ?? DateTime.now()).toLocal();
  final sameDay = local.year == current.year &&
      local.month == current.month &&
      local.day == current.day;
  String two(int value) => value.toString().padLeft(2, '0');
  if (sameDay) {
    return '${two(local.hour)}:${two(local.minute)}';
  }
  if (local.year == current.year) {
    return '${two(local.month)}-${two(local.day)} '
        '${two(local.hour)}:${two(local.minute)}';
  }
  return '${local.year}-${two(local.month)}-${two(local.day)}';
}

/// 附件大小展示。
String formatMailSize(int? size) {
  if (size == null || size <= 0) return '';
  if (size < 1024) return '$size B';
  if (size < 1024 * 1024) return '${(size / 1024).toStringAsFixed(1)} KB';
  return '${(size / (1024 * 1024)).toStringAsFixed(1)} MB';
}
