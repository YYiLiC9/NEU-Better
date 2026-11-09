import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/student_identity.dart';
import 'neu_cas_client.dart';

final casIdentityClientProvider = Provider<CasIdentityClient>(
  (ref) => CasIdentityClient(),
);

/// Reads the authenticated CAS user's real name and student number.
///
/// CAS already exposes these as `<cas:USER_NAME>` and `<cas:ID_NUMBER>` in the
/// `serviceValidate` response. This avoids a second browser-like login just to
/// scrape the portal SPA, and works for both native and WebView sessions.
class CasIdentityClient {
  Future<StudentIdentity?> fetch(
    CasLoginResult login, {
    Duration timeout = const Duration(seconds: 6),
  }) {
    final cookie = login.cookies['pass.neu.edu.cn'];
    if (cookie == null || cookie.isEmpty) return Future.value(null);
    return fetchFromCookieHeader(cookie, timeout: timeout);
  }

  /// Accepts the raw `pass.neu.edu.cn` Cookie header (as returned by the
  /// WebView cookie manager).
  Future<StudentIdentity?> fetchFromCookieHeader(
    String cookie, {
    Duration timeout = const Duration(seconds: 6),
  }) async {
    final client = HttpClient();
    try {
      return await _fetch(client, cookie).timeout(timeout);
    } catch (error) {
      debugPrint('[cas-identity] lookup failed: $error');
      return null;
    } finally {
      client.close(force: true);
    }
  }

  Future<StudentIdentity?> _fetch(HttpClient client, String cookie) async {
    const service = 'https://personal.neu.edu.cn/portal';
    final loginRequest = await client.getUrl(
      Uri.https('pass.neu.edu.cn', '/tpass/login', {'service': service}),
    );
    loginRequest.headers.set(HttpHeaders.cookieHeader, cookie);
    loginRequest.followRedirects = false;
    final loginResponse = await loginRequest.close();
    final location = loginResponse.headers.value(HttpHeaders.locationHeader);
    if (location == null) return null;
    final ticket = Uri.tryParse(location)?.queryParameters['ticket'];
    if (ticket == null || ticket.isEmpty) return null;

    final validateRequest = await client.getUrl(
      Uri.https('pass.neu.edu.cn', '/tpass/serviceValidate', {
        'service': service,
        'ticket': ticket,
      }),
    );
    validateRequest.headers.set(HttpHeaders.cookieHeader, cookie);
    final validateResponse = await validateRequest.close();
    final xml = await utf8.decoder.bind(validateResponse).join();
    return parse(xml);
  }

  static StudentIdentity? parse(String xml) {
    final id = _tag(xml, 'ID_NUMBER') ?? _tag(xml, 'id_number');
    final name = _tag(xml, 'USER_NAME') ?? _tag(xml, 'user_name');
    if (!StudentIdentity.isValidStudentId(id)) return null;
    return StudentIdentity(
      studentId: id,
      displayName: name?.trim().isEmpty == true ? null : name?.trim(),
    );
  }

  static String? _tag(String xml, String name) {
    final escaped = RegExp.escape(name);
    final match = RegExp(
      '<(?:cas|sso):$escaped>([^<]*)</(?:cas|sso):$escaped>',
      caseSensitive: false,
    ).firstMatch(xml);
    return match?.group(1)?.trim();
  }
}
