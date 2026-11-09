/// Student identity extracted from an authenticated CAS/portal page.
class StudentIdentity {
  const StudentIdentity({this.studentId, this.displayName});

  final String? studentId;
  final String? displayName;

  bool get hasStudentId => isValidStudentId(studentId);

  bool get hasDisplayName =>
      displayName != null && displayName!.trim().isNotEmpty;

  static final RegExp _studentIdPattern = RegExp(r'^\d{8,12}$');
  static final RegExp _labeledStudentId = RegExp(
    r'(?:学号|账号|用户名|工号)\s*[:：]?\s*(\d{8,12})',
  );
  static final RegExp _labeledName = RegExp(
    r'(?:姓名|用户姓名|真实姓名)\s*[:：]?\s*([\u4e00-\u9fa5]{2,8})',
  );

  /// NEU student numbers are 8-12 digits. Keep this check centralized so a
  /// date or course code can never be mistaken for an account number.
  static bool isValidStudentId(String? value) {
    final trimmed = value?.trim();
    return trimmed != null && _studentIdPattern.hasMatch(trimmed);
  }

  /// Parses the `d` object returned by `GET /site/user_info` or the equivalent
  /// `userInfo` localStorage entry.
  factory StudentIdentity.fromUserInfo(Map<dynamic, dynamic> info) {
    final rawId = '${info['user_number'] ?? ''}'.trim();
    final rawName = '${info['user_name'] ?? ''}'.trim();
    return StudentIdentity(
      studentId: isValidStudentId(rawId) ? rawId : null,
      displayName: rawName.isEmpty ? null : rawName,
    );
  }

  /// Parses only explicitly labelled text. A bare `20\d{6,10}` is deliberately
  /// not accepted because portal pages contain dates and course identifiers.
  factory StudentIdentity.fromText(String text) {
    if (text.trim().isEmpty) return const StudentIdentity();
    final normalized = text.replaceAll('\u00a0', ' ');
    final idMatch = _labeledStudentId.firstMatch(normalized);
    final nameMatch = _labeledName.firstMatch(normalized);
    final id = idMatch?.group(1)?.trim();
    final name = nameMatch?.group(1)?.trim();
    return StudentIdentity(
      studentId: isValidStudentId(id) ? id : null,
      displayName: name == null || name.isEmpty ? null : name,
    );
  }

  /// Combines a page probe with a cookie-derived id.
  StudentIdentity merge({String? fallbackStudentId, String? fallbackName}) {
    final id = _firstNonEmpty([studentId, fallbackStudentId]);
    final name = _firstNonEmpty([displayName, fallbackName]);
    return StudentIdentity(
      studentId: isValidStudentId(id) ? id : null,
      displayName: name,
    );
  }

  static String? _firstNonEmpty(Iterable<String?> values) {
    for (final value in values) {
      final trimmed = value?.trim();
      if (trimmed != null && trimmed.isNotEmpty) return trimmed;
    }
    return null;
  }
}
