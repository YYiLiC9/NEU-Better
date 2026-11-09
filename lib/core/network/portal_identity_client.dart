import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/student_identity.dart';
import 'windows_portal_identity_client.dart';

/// Fetches the authenticated student's identity from the personal portal.
///
/// The endpoint is the same one used by the portal SPA:
/// `GET https://personal.neu.edu.cn/site/user_info`.
abstract interface class PortalIdentityClient {
  Future<StudentIdentity?> fetch(Map<String, String> cookies);
}

/// A portal client that can perform a full browser login when a native CAS
/// session cannot create the portal's own SPA cookie (`cookie_vjuid_login`).
abstract interface class PortalLoginIdentityClient {
  Future<StudentIdentity?> fetchWithCredentials({
    required String username,
    required String password,
  });
}

class HttpPortalIdentityClient implements PortalIdentityClient {
  HttpPortalIdentityClient({Dio? dio}) : _dio = dio ?? Dio();

  final Dio _dio;

  @override
  Future<StudentIdentity?> fetch(Map<String, String> cookies) async {
    final cookieHeader = _cookieHeader(cookies);
    if (cookieHeader == null) return null;

    try {
      final response = await _dio
          .get<String>(
            'https://personal.neu.edu.cn/site/user_info',
            queryParameters: {'t': DateTime.now().millisecondsSinceEpoch},
            options: Options(
              headers: {
                'Cookie': cookieHeader,
                'Accept': 'application/json, text/plain, */*',
                'Content-Type': 'application/x-www-form-urlencoded',
                'Source-Version': '0',
                'X-Requested-With': 'XMLHttpRequest',
                'Origin': 'https://personal.neu.edu.cn',
                'Referer':
                    'https://personal.neu.edu.cn/page/site/homeIndex',
              },
              followRedirects: false,
              validateStatus: (_) => true,
              responseType: ResponseType.plain,
            ),
          )
          .timeout(const Duration(seconds: 3));

      if (response.statusCode != 200) {
        debugPrint('[identity] user_info status=${response.statusCode}');
        return null;
      }
      final body = response.data;
      if (body == null || body.trim().isEmpty) return null;

      var decoded = jsonDecode(body);
      if (decoded is String) decoded = jsonDecode(decoded);
      if (decoded is! Map) return null;
      if (int.tryParse('${decoded['e']}') != 0) {
        debugPrint('[identity] user_info error=${decoded['m']}');
        return null;
      }
      var data = decoded['d'];
      if (data is String) data = jsonDecode(data);
      if (data is List && data.isNotEmpty) data = data.first;
      if (data is! Map) return null;
      return StudentIdentity.fromUserInfo(data);
    } catch (error) {
      debugPrint('[identity] portal lookup failed: $error');
      return null;
    }
  }

  String? _cookieHeader(Map<String, String> cookies) {
    final pairs = <String, String>{};

    void addHeader(String header) {
      for (final part in header.split(';')) {
        final trimmed = part.trim();
        if (trimmed.isEmpty) continue;
        final index = trimmed.indexOf('=');
        if (index <= 0) continue;
        pairs.putIfAbsent(
          trimmed.substring(0, index),
          () => trimmed.substring(index + 1),
        );
      }
    }

    final personal = cookies['personal.neu.edu.cn']?.trim();
    if (personal != null && personal.isNotEmpty) addHeader(personal);

    for (final entry in cookies.entries) {
      if (entry.key == 'personal.neu.edu.cn') continue;
      if (!entry.key.endsWith('neu.edu.cn')) continue;
      final value = entry.value.trim();
      if (value.isNotEmpty) addHeader(value);
    }

    if (pairs.isEmpty) return null;
    return pairs.entries.map((e) => '${e.key}=${e.value}').join('; ');
  }
}

final portalIdentityClientProvider = Provider<PortalIdentityClient>((ref) {
  if (Platform.isWindows) return WindowsPortalIdentityClient();
  return HttpPortalIdentityClient();
});
