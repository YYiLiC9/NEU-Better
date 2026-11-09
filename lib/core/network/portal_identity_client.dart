import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/student_identity.dart';

/// Fetches the authenticated student's identity from the personal portal.
///
/// The endpoint is the same one used by the portal SPA:
/// `GET https://personal.neu.edu.cn/site/user_info`.
abstract interface class PortalIdentityClient {
  Future<StudentIdentity?> fetch(Map<String, String> cookies);
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
                'Content-Type': 'application/x-www-form-urlencoded',
                'Source-Version': '0',
                'X-Requested-With': 'XMLHttpRequest',
                'Referer': 'https://personal.neu.edu.cn/portal',
              },
              followRedirects: false,
              validateStatus: (_) => true,
              responseType: ResponseType.plain,
            ),
          )
          .timeout(const Duration(seconds: 2));

      if (response.statusCode != 200) return null;
      final body = response.data;
      if (body == null || body.trim().isEmpty) return null;

      final decoded = jsonDecode(body);
      if (decoded is! Map) return null;
      if (int.tryParse('${decoded['e']}') != 0) return null;
      final data = decoded['d'];
      if (data is! Map) return null;
      return StudentIdentity.fromUserInfo(data);
    } catch (error) {
      debugPrint('[identity] portal lookup failed: $error');
      return null;
    }
  }

  String? _cookieHeader(Map<String, String> cookies) {
    final personal = cookies['personal.neu.edu.cn']?.trim();
    if (personal != null && personal.isNotEmpty) return personal;

    final values = <String>[];
    for (final entry in cookies.entries) {
      if (!entry.key.endsWith('neu.edu.cn')) continue;
      final value = entry.value.trim();
      if (value.isNotEmpty) values.add(value);
    }
    return values.isEmpty ? null : values.join('; ');
  }
}

final portalIdentityClientProvider = Provider<PortalIdentityClient>((ref) {
  return HttpPortalIdentityClient();
});
