class AuthException implements Exception {
  const AuthException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// The account/password step succeeded, but CAS requires a device or QR check.
class SecondaryVerificationRequired extends AuthException {
  const SecondaryVerificationRequired()
      : super('学校要求进行一次设备验证，请使用网页登录。');
}
