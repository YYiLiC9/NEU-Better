import 'dart:convert';

/// Credentials remembered locally so the login form can be prefilled.
///
/// [password] is nullable: a web-login-only flow can remember the student id
/// without ever receiving the password.
class SavedCredentials {
  const SavedCredentials({required this.username, this.password});

  final String username;
  final String? password;

  Map<String, dynamic> toJson() {
    return {
      'username': username,
      if (password != null && password!.isNotEmpty) 'password': password,
    };
  }

  factory SavedCredentials.fromJson(Map<String, dynamic> json) {
    final username = '${json['username'] ?? ''}'.trim();
    final rawPassword = json['password'];
    final password = rawPassword is String ? rawPassword : null;
    return SavedCredentials(
      username: username,
      password: password == null || password.isEmpty ? null : password,
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
