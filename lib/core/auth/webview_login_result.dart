/// The result of a completed school web login.
class WebViewLoginResult {
  const WebViewLoginResult({
    required this.cookies,
    this.studentId,
    this.displayName,
  });

  final Map<String, String> cookies;
  final String? studentId;
  final String? displayName;

  bool get hasCookies => cookies.values.any((value) => value.trim().isNotEmpty);
}
