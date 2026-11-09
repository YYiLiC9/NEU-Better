/// Student identity extracted from an authenticated CAS/portal page.
class StudentIdentity {
  const StudentIdentity({this.studentId, this.displayName});

  final String? studentId;
  final String? displayName;

  bool get hasStudentId => studentId != null && studentId!.trim().isNotEmpty;
  bool get hasDisplayName =>
      displayName != null && displayName!.trim().isNotEmpty;

  static final RegExp _labeledStudentId = RegExp(
    r'(?:学号|账号|用户名|工号)\s*[:：]?\s*(20\d{6,10})',
  );
  static final RegExp _anyStudentId = RegExp(r'(20\d{6,10})');
  static final RegExp _labeledName = RegExp(
    r'(?:姓名|用户姓名|真实姓名)\s*[:：]?\s*([\u4e00-\u9fa5]{2,4})',
  );

  /// Parses the visible text of a portal page and/or localStorage values.
  factory StudentIdentity.fromText(String text) {
    if (text.trim().isEmpty) return const StudentIdentity();
    final normalized = text.replaceAll('\u00a0', ' ');
    final idMatch =
        _labeledStudentId.firstMatch(normalized) ??
        _anyStudentId.firstMatch(normalized);
    final nameMatch = _labeledName.firstMatch(normalized);
    final id = idMatch?.group(1)?.trim();
    final name = nameMatch?.group(1)?.trim();
    return StudentIdentity(
      studentId: id == null || id.isEmpty ? null : id,
      displayName: name == null || name.isEmpty ? null : name,
    );
  }

  /// Combines a page probe with a cookie-derived id.
  StudentIdentity merge({String? fallbackStudentId, String? fallbackName}) {
    final id = _firstNonEmpty([studentId, fallbackStudentId]);
    final name = _firstNonEmpty([displayName, fallbackName]);
    return StudentIdentity(studentId: id, displayName: name);
  }

  static String? _firstNonEmpty(Iterable<String?> values) {
    for (final value in values) {
      final trimmed = value?.trim();
      if (trimmed != null && trimmed.isNotEmpty) return trimmed;
    }
    return null;
  }
}
