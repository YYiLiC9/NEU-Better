import 'dart:convert';

/// A locally persisted login session.
///
/// Cookies are kept as `domain -> "name=value; name2=value2"` so the session
/// can be restored without asking the user to log in again.
class AuthSession {
  const AuthSession({
    required this.studentId,
    required this.cookies,
    required this.createdAt,
    this.displayName,
    this.college,
    this.major,
    this.grade,
    this.source = 'cas',
  });

  final String studentId;
  final String? displayName;
  final String? college;
  final String? major;
  final String? grade;
  final Map<String, String> cookies;
  final DateTime createdAt;
  final String source;

  bool get hasCookies => cookies.values.any((value) => value.trim().isNotEmpty);

  AuthSession copyWith({
    String? studentId,
    String? displayName,
    String? college,
    String? major,
    String? grade,
    Map<String, String>? cookies,
    DateTime? createdAt,
    String? source,
  }) {
    return AuthSession(
      studentId: studentId ?? this.studentId,
      displayName: displayName ?? this.displayName,
      college: college ?? this.college,
      major: major ?? this.major,
      grade: grade ?? this.grade,
      cookies: cookies ?? this.cookies,
      createdAt: createdAt ?? this.createdAt,
      source: source ?? this.source,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'studentId': studentId,
      'displayName': displayName,
      'college': college,
      'major': major,
      'grade': grade,
      'cookies': cookies,
      'createdAt': createdAt.toIso8601String(),
      'source': source,
    };
  }

  factory AuthSession.fromJson(Map<String, dynamic> json) {
    final rawCookies = json['cookies'];
    final cookies = <String, String>{};
    if (rawCookies is Map) {
      for (final entry in rawCookies.entries) {
        cookies['${entry.key}'] = '${entry.value}';
      }
    }

    return AuthSession(
      studentId: '${json['studentId'] ?? ''}',
      displayName: json['displayName'] as String?,
      college: json['college'] as String?,
      major: json['major'] as String?,
      grade: json['grade'] as String?,
      cookies: cookies,
      createdAt:
          DateTime.tryParse('${json['createdAt'] ?? ''}') ?? DateTime.now(),
      source: '${json['source'] ?? 'cas'}',
    );
  }

  String encode() => jsonEncode(toJson());

  factory AuthSession.decode(String value) {
    final decoded = jsonDecode(value);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Invalid session payload');
    }
    return AuthSession.fromJson(decoded);
  }

  /// A readable account label for the shell, falling back to the student id.
  String get accountLabel {
    final name = displayName?.trim();
    final id = studentId.trim();
    if (name != null && name.isNotEmpty && name != id) {
      return name;
    }
    if (id.isNotEmpty) return id;
    return '已连接学校账号';
  }
}
