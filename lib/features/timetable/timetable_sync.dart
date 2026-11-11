import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../core/auth/auth_session.dart';
import '../../core/network/yjs_timetable_client.dart';
import 'timetable_import.dart';
import 'timetable_models.dart';
import 'timetable_store.dart';

/// 后台课表同步：登录成功后自动拉一次并写入本地缓存。
abstract final class TimetableSyncService {
  /// 用当前登录会话免密同步课表；失败时返回 null，不打断主流程。
  static Future<TimetableData?> syncWithSession(AuthSession session) async {
    if (!session.hasCookies) return null;
    try {
      final raw = await YjsTimetableClient().fetchWithSession(session: session);
      final data = parseEnvelope(raw);
      if (data == null) return null;
      await const TimetableStore().save(data);
      return data;
    } catch (error) {
      debugPrint('[timetable] auto sync skipped: $error');
      return null;
    }
  }

  /// 把 [YjsTimetableClient] 返回的 envelope 解析为 [TimetableData]。
  static TimetableData? parseEnvelope(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    final envelope = jsonDecode(raw);
    if (envelope is! Map) return null;
    final error = envelope['error'];
    if (error is String && error.trim().isNotEmpty) return null;
    final body = envelope['body'];
    if (body is! String || body.trim().isEmpty) return null;
    return YjsTimetableParser.parse(
      body,
      fallbackTermName: '研究生课程表',
      currentWeek: (envelope['currentWeek'] as num?)?.toInt(),
      examBody: envelope['examBody'] as String?,
      termStartDate: DateTime.tryParse(
        envelope['termStartDate'] as String? ?? '',
      ),
    );
  }
}
