import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/auth_exception.dart';
import '../../core/auth/auth_session.dart';
import '../../core/auth/session_store.dart';
import '../../core/network/neu_cas_client.dart';

sealed class AuthState {
  const AuthState();
}

final class AuthInitial extends AuthState {
  const AuthInitial();
}

final class AuthBusy extends AuthState {
  const AuthBusy();
}

final class AuthUnauthenticated extends AuthState {
  const AuthUnauthenticated({this.message});

  final String? message;
}

final class AuthAuthenticated extends AuthState {
  const AuthAuthenticated(this.session);

  final AuthSession session;
}

final sessionStoreProvider = Provider<SessionStore>((ref) {
  return const SecureSessionStore();
});

final casClientProvider = Provider<CasClient>((ref) {
  return NeuCasClient();
});

final authControllerProvider = NotifierProvider<AuthController, AuthState>(
  AuthController.new,
);

class AuthController extends Notifier<AuthState> {
  @override
  AuthState build() {
    _restore();
    return const AuthInitial();
  }

  Future<void> _restore() async {
    try {
      final session = await ref.read(sessionStoreProvider).read();
      if (!ref.mounted) return;
      if (session != null && session.hasCookies) {
        state = AuthAuthenticated(session);
      } else {
        state = const AuthUnauthenticated();
      }
    } catch (error) {
      debugPrint('NEU Better session restore failed: $error');
      if (!ref.mounted) return;
      state = const AuthUnauthenticated();
    }
  }

  Future<void> login({
    required String username,
    required String password,
  }) async {
    if (state is AuthBusy) return;
    state = const AuthBusy();

    try {
      final result = await ref.read(casClientProvider).login(
            username: username,
            password: password,
          );
      final trimmed = username.trim();
      final session = AuthSession(
        studentId: trimmed,
        displayName: trimmed,
        cookies: result.cookies,
        createdAt: DateTime.now(),
        source: 'cas',
      );
      await ref.read(sessionStoreProvider).save(session);
      if (!ref.mounted) return;
      state = AuthAuthenticated(session);
    } on SecondaryVerificationRequired catch (error) {
      if (!ref.mounted) return;
      state = AuthUnauthenticated(message: error.message);
    } on AuthException catch (error) {
      if (!ref.mounted) return;
      state = AuthUnauthenticated(message: error.message);
    } catch (error) {
      if (!ref.mounted) return;
      state = AuthUnauthenticated(message: _friendlyError(error));
    }
  }

  Future<void> loginWithCookies({
    required Map<String, String> cookies,
    String? username,
  }) async {
    if (cookies.values.every((value) => value.trim().isEmpty)) {
      state = const AuthUnauthenticated(
        message: '网页登录没有返回有效会话，请重试。',
      );
      return;
    }

    final id = (username == null || username.trim().isEmpty)
        ? '东北大学用户'
        : username.trim();
    final session = AuthSession(
      studentId: id,
      displayName: id,
      cookies: cookies,
      createdAt: DateTime.now(),
      source: 'webview',
    );
    await ref.read(sessionStoreProvider).save(session);
    if (!ref.mounted) return;
    state = AuthAuthenticated(session);
  }

  Future<void> logout() async {
    await ref.read(sessionStoreProvider).clear();
    if (!ref.mounted) return;
    state = const AuthUnauthenticated();
  }

  String _friendlyError(Object error) {
    final text = error.toString();
    if (text.contains('SocketException') || text.contains('Connection')) {
      return '网络连接失败，请检查网络后重试。';
    }
    if (text.contains('HandshakeException') ||
        text.contains('certificate')) {
      return '无法建立安全连接，请稍后重试或使用网页登录。';
    }
    if (text.contains('TimeoutException')) {
      return '连接学校服务器超时，请稍后重试。';
    }
    return '登录失败，请稍后重试或使用网页登录。';
  }
}
