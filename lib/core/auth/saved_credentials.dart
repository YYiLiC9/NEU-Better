import 'dart:convert';

/// Credentials remembered locally so the login form can be prefilled.
///
/// [password] is nullable: a web-login-only flow can remember the student id
/// without ever receiving the password.
class SavedCredentials {
  const SavedCredentials({
    required this.username,
    this.password,
    this.displayName,
  });

  final String username;
  final String? password;
  final String? displayName;

  Map<String, dynamic> toJson() {
    return {
      'username': username,
      if (password != null && password!.isNotEmpty) 'password': password,
      if (displayName != null && displayName!.isNotEmpty)
        'displayName': displayName,
    };
  }

  factory SavedCredentials.fromJson(Map<String, dynamic> json) {
    final username = '${json['username'] ?? ''}'.trim();
    final rawPassword = json['password'];
    final rawDisplayName = json['displayName'];
    final password = rawPassword is String ? rawPassword : null;
    final displayName = rawDisplayName is String ? rawDisplayName.trim() : null;
    return SavedCredentials(
      username: username,
      password: password == null || password.isEmpty ? null : password,
      displayName:
          displayName == null || displayName.isEmpty ? null : displayName,
    );
  }

  String encode() => jsonEncode(toJson());

  factory SavedCredentials.decode(String value) {
    final decoded = jsonDecode(value);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Invalid credentials payload');
    }
    return SavedCredentials.fromJson(decoded);
  }
}
