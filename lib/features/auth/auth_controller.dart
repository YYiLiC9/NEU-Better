import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/auth_exception.dart';
import '../../core/auth/auth_session.dart';
import '../../core/auth/credential_store.dart';
import '../../core/auth/saved_credentials.dart';
import '../../core/auth/session_store.dart';
import '../../core/auth/student_identity.dart';
import '../../core/auth/webview_login_result.dart';
import '../../core/network/cas_identity_client.dart';
import '../../core/network/neu_cas_client.dart';
import '../../core/network/portal_identity_client.dart';

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
  /// Only the first cold start of this controller may auto-login. A manual
  /// logout must not immediately sign the user back in.
  bool _autoLoginAllowed = true;

  @override
  AuthState build() {
    _restore();
    return const AuthInitial();
  }

  Future<void> _restore() async {
    // Secure storage can throw on locked-down Windows accounts. A failed
    // session read must never skip the saved-credential auto-login path.
    AuthSession? session;
    try {
      session = await ref
          .read(sessionStoreProvider)
          .read()
          .timeout(const Duration(seconds: 4), onTimeout: () => null);
    } catch (error) {
      debugPrint('[auth] session read failed: $error');
    }

    if (!ref.mounted || state is! AuthInitial) return;
    if (session != null && session.hasCookies) {
      state = AuthAuthenticated(session);
      unawaited(_refreshRestoredIdentity(session));
      return;
    }

    if (_autoLoginAllowed) {
      SavedCredentials? saved;
      try {
        saved = await ref
            .read(credentialStoreProvider)
            .read()
            .timeout(const Duration(seconds: 4), onTimeout: () => null);
      } catch (error) {
        debugPrint('[auth] credential read failed: $error');
      }
      if (!ref.mounted || state is! AuthInitial) return;
      if (saved != null &&
          saved.username.trim().isNotEmpty &&
          saved.password != null &&
          saved.password!.isNotEmpty) {
        _autoLoginAllowed = false;
        await login(
          username: saved.username,
          password: saved.password!,
          saveCredentials: true,
          initialDisplayName: saved.displayName,
        );
        // An expired saved password must not leave a scary "登录失败" banner
        // on the login page before the user has typed anything.
        if (ref.mounted && state is AuthUnauthenticated) {
          state = const AuthUnauthenticated();
        }
        return;
      }
    }

    if (!ref.mounted || state is! AuthInitial) return;
    state = const AuthUnauthenticated();
  }

  Future<void> _refreshRestoredIdentity(AuthSession session) async {
    SavedCredentials? saved;
    try {
      saved = await ref
          .read(credentialStoreProvider)
          .read()
          .timeout(const Duration(seconds: 4));
    } catch (error) {
      debugPrint('[auth] credential read for refresh failed: $error');
    }
    final cachedName = saved?.displayName?.trim();
    if (cachedName != null && cachedName.isNotEmpty) {
      final updated = session.copyWith(displayName: cachedName);
      if (ref.mounted) {
        final current = state;
        if (current is AuthAuthenticated &&
            current.session.createdAt == session.createdAt) {
          state = AuthAuthenticated(updated);
        }
      }
      session = updated;
    }
    if (saved == null || saved.password == null || saved.password!.isEmpty) {
      return;
    }
    // The user opted into saving credentials at login; the restore-time
    // identity refresh must keep that choice, otherwise the password file is
    // wiped on every launch and daily jobs (电费查询) lose the password.
    await _resolveAndPersistIdentity(
      session,
      saveCredentials: true,
      typedPassword: saved.password,
    );
  }

  Future<void> login({
    required String username,
    required String password,
    bool saveCredentials = false,
    String? initialDisplayName,
  }) async {
    if (state is AuthBusy) return;
    state = const AuthBusy();

    try {
      debugPrint('[auth] native login start');
      final result = await ref
          .read(casClientProvider)
          .login(username: username, password: password)
          .timeout(
            const Duration(seconds: 35),
            onTimeout: () =>
                throw TimeoutException('CAS login timed out after 35 seconds'),
          );
      debugPrint('[auth] native login response: ${result.finalUri.host}');
      final trimmed = username.trim();
      StudentIdentity? casIdentity;
      try {
        casIdentity = await ref
            .read(casIdentityClientProvider)
            .fetch(result)
            .timeout(const Duration(seconds: 4));
      } catch (error) {
        debugPrint('[auth] CAS identity lookup failed: $error');
      }
      final session = AuthSession(
        studentId: casIdentity?.studentId ?? trimmed,
        displayName: casIdentity?.displayName ?? initialDisplayName,
        cookies: result.cookies,
        createdAt: DateTime.now(),
        source: 'cas',
      );

      if (!ref.mounted) return;
      // Show the home page first. Secure-storage persistence is deliberately
      // fire-and-forget so a broken Windows plugin cannot hold the login
      // button in a spinner.
      state = AuthAuthenticated(session);
      unawaited(_persistSession(session));
      unawaited(
        _persistCredentials(
          enabled: saveCredentials,
          username: trimmed,
          password: password,
          displayName: initialDisplayName,
        ),
      );
      // The CAS redirect usually establishes a portal session too. Resolve
      // the real name in the background so native and web login display the
      // same identity.
      unawaited(
        _resolveAndPersistIdentity(
          session,
          saveCredentials: saveCredentials,
          typedPassword: password,
        ),
      );
    } on SecondaryVerificationRequired catch (error) {
      if (!ref.mounted) return;
      state = AuthUnauthenticated(message: error.message);
    } on AuthException catch (error) {
      if (!ref.mounted) return;
      state = AuthUnauthenticated(message: error.message);
    } on TimeoutException {
      if (!ref.mounted) return;
      state = const AuthUnauthenticated(message: '连接学校服务器超时，请检查网络后重试。');
    } catch (error) {
      if (!ref.mounted) return;
      state = AuthUnauthenticated(message: _friendlyError(error));
    }
  }

  Future<void> loginWithCookies({
    required WebViewLoginResult result,
    String? fallbackStudentId,
    String? typedUsername,
    String? typedPassword,
    bool saveCredentials = false,
  }) async {
    if (!result.hasCookies) {
      state = const AuthUnauthenticated(message: '网页登录没有返回有效会话，请重试。');
      return;
    }

    final resultId = StudentIdentity.isValidStudentId(result.studentId)
        ? result.studentId
        : null;
    final id = _firstNonEmpty([resultId, fallbackStudentId, typedUsername]);
    final name = _firstNonEmpty([result.displayName, id]);
    final session = AuthSession(
      studentId: id ?? '',
      displayName: name,
      cookies: result.cookies,
      createdAt: DateTime.now(),
      source: 'webview',
    );

    if (!ref.mounted) return;
    // Do not wait for secure storage here. The webview "完成" action must
    // return to the shell immediately; persistence is best-effort background
    // work.
    state = AuthAuthenticated(session);
    final needsIdentityRefresh =
        resultId == null ||
        result.displayName == null ||
        result.displayName == resultId ||
        result.displayName == '已连接学校账号';
    if (needsIdentityRefresh) {
      unawaited(
        _resolveAndPersistIdentity(
          session,
          saveCredentials: saveCredentials,
          typedPassword: typedPassword,
        ),
      );
    } else {
      unawaited(_persistSession(session));
    }
    unawaited(
      _persistCredentials(
        enabled: saveCredentials,
        username: id ?? typedUsername ?? '',
        password: typedPassword,
        displayName: result.displayName,
      ),
    );
  }

  Future<void> _resolveAndPersistIdentity(
    AuthSession initial, {
    required bool saveCredentials,
    String? typedPassword,
  }) async {
    var session = initial;
    try {
      StudentIdentity? identity;
      final passCookie = initial.cookies['pass.neu.edu.cn'];
      if (passCookie != null && passCookie.isNotEmpty) {
        identity = await ref
            .read(casIdentityClientProvider)
            .fetchFromCookieHeader(passCookie)
            .timeout(const Duration(seconds: 4));
      }
      if (identity == null) {
        final client = ref.read(portalIdentityClientProvider);
        final PortalLoginIdentityClient? loginClient =
            client is PortalLoginIdentityClient
                ? client as PortalLoginIdentityClient
                : null;
        if (typedPassword != null &&
            typedPassword.isNotEmpty &&
            loginClient != null) {
          identity = await loginClient
              .fetchWithCredentials(
                username: initial.studentId,
                password: typedPassword,
              )
              .timeout(const Duration(seconds: 25));
        } else {
          identity = await client.fetch(initial.cookies);
        }
      }
      if (identity != null && (identity.hasStudentId || identity.hasDisplayName)) {
        session = initial.copyWith(
          studentId: identity.hasStudentId ? identity.studentId : null,
          displayName: identity.displayName ??
              (identity.hasStudentId ? identity.studentId : null),
        );
        if (identity.hasStudentId) {
          unawaited(
            _persistCredentials(
              enabled: saveCredentials,
              username: identity.studentId!,
              password: typedPassword,
              displayName: identity.displayName,
            ),
          );
        }
        if (ref.mounted) {
          final current = state;
          if (current is AuthAuthenticated &&
              current.session.createdAt == initial.createdAt) {
            state = AuthAuthenticated(session);
          }
        }
      }
    } catch (error) {
      debugPrint('[auth] identity refresh failed: $error');
    }

    if (!ref.mounted) return;
    final current = state;
    if (current is! AuthAuthenticated ||
        current.session.createdAt != initial.createdAt) {
      return;
    }
    await _persistSession(session);
  }

  Future<void> _persistSession(AuthSession session) async {
    try {
      await ref
          .read(sessionStoreProvider)
          .save(session)
          .timeout(const Duration(seconds: 4));
      debugPrint('[auth] session saved');
    } on TimeoutException {
      debugPrint('[auth] session save timed out; using memory session');
    } catch (error) {
      debugPrint('[auth] session save failed: $error');
    }
  }

  Future<void> _persistCredentials({
    required bool enabled,
    required String username,
    String? password,
    String? displayName,
  }) async {
    try {
      final store = ref.read(credentialStoreProvider);
      if (!enabled) {
        await store.clear();
        return;
      }
      final trimmed = username.trim();
      if (trimmed.isEmpty) return;
      await store.save(
        SavedCredentials(
          username: trimmed,
          password: password == null || password.isEmpty ? null : password,
          displayName: displayName,
        ),
      );
    } catch (error) {
      debugPrint('[auth] credential update failed: $error');
    }
  }

  static String? _firstNonEmpty(Iterable<String?> values) {
    for (final value in values) {
      final trimmed = value?.trim();
      if (trimmed != null && trimmed.isNotEmpty) return trimmed;
    }
    return null;
  }

  Future<void> logout() async {
    // Show the login screen immediately; secure-storage deletion can block on
    // some Windows ACL setups and must not make the logout button feel dead.
    _autoLoginAllowed = false;
    state = const AuthUnauthenticated();
    // The CAS client keeps the single-sign-on ticket in memory. Without this
    // reset the next login skips the CAS form (stale TGT) and native login
    // fails with "学校登录页格式已更新".
    final casClient = ref.read(casClientProvider);
    if (casClient is NeuCasClient) {
      casClient.reset();
    }
    try {
      await ref
          .read(sessionStoreProvider)
          .clear()
          .timeout(const Duration(seconds: 3));
      debugPrint('[auth] session cleared');
    } on TimeoutException {
      debugPrint('[auth] session clear timed out');
    } catch (error) {
      debugPrint('[auth] session clear failed: $error');
    }
  }

  String _friendlyError(Object error) {
    final text = error.toString();
    if (text.contains('SocketException') || text.contains('Connection')) {
      return '网络连接失败，请检查网络后重试。';
    }
    if (text.contains('HandshakeException') || text.contains('certificate')) {
      return '无法建立安全连接，请稍后重试或使用网页登录。';
    }
    if (text.contains('TimeoutException')) {
      return '连接学校服务器超时，请稍后重试。';
    }
    return '登录失败，请稍后重试或使用网页登录。';
  }
}
