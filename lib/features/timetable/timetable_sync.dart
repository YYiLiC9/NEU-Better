import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../core/auth/auth_exception.dart';
import '../../core/auth/auth_session.dart';
import '../../core/auth/credential_store.dart';
import '../../core/auth/saved_credentials.dart';
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
      var data = parseEnvelope(raw);
      if (data == null) return null;
      // 考试接口偶发失败（返回空）时不要把上一次已缓存的考试清空：保留旧考试，
      // 避免“同步一次考试就不见了”。
      if (data.exams.isEmpty) {
        // 1) 先用保存的账号密码重新登录：考试接口部署在部分后端节点上，
        //    少数会话会命中没有该接口的节点而返回 404。重新登录会换到新节点，
        //    多试几次基本都能拿到考试，保证「能读到课表就能读到考试」。
        final recovered = await _recoverWithCredentials(session);
        if (recovered != null) {
          data = recovered;
        } else {
          // 2) 实在拿不到就保留上一次缓存的考试，绝不清空。
          final previous = await const TimetableStore().read();
          if (previous != null && previous.exams.isNotEmpty) {
            data = TimetableData(
              termName: data.termName,
              totalWeeks: data.totalWeeks,
              sessions: data.sessions,
              isSample: data.isSample,
              currentWeek: data.currentWeek,
              termStartDate: data.termStartDate ?? previous.termStartDate,
              exams: previous.exams,
            );
          }
        }
      }
      await const TimetableStore().save(data);
      return data;
    } catch (error) {
      debugPrint('[timetable] auto sync skipped: $error');
      return null;
    }
  }

  /// 用保存的账号密码重新登录，直到命中能返回考试的后端节点为止。无密码或
  /// 账号不匹配时返回 null；认证失败立即中止，避免把账号试锁。
  static Future<TimetableData?> _recoverWithCredentials(
    AuthSession? session,
  ) async {
    SavedCredentials? saved;
    try {
      saved = await const SecureCredentialStore()
          .read()
          .timeout(const Duration(seconds: 3), onTimeout: () => null);
    } catch (error) {
      debugPrint('[timetable] exam recovery: credential read failed $error');
      return null;
    }
    final password = saved?.password;
    if (saved == null || password == null || password.isEmpty) return null;
    final studentId = session?.studentId.trim() ?? '';
    if (studentId.isNotEmpty && saved.username.trim() != studentId) {
      return null;
    }
    for (var attempt = 1; attempt <= 3; attempt++) {
      try {
        final raw = await YjsTimetableClient().fetch(
          username: saved.username,
          password: password,
          term: '20261',
        );
        final data = parseEnvelope(raw);
        if (data != null && data.exams.isNotEmpty) {
          debugPrint('[timetable] exams recovered on attempt $attempt');
          return data;
        }
      } on AuthException catch (error) {
        debugPrint('[timetable] exam recovery aborted (auth): $error');
        return null;
      } catch (error) {
        debugPrint('[timetable] exam recovery attempt $attempt failed: $error');
      }
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
    return null;
  }

  /// 交互式同步页用：返回重新登录后拿到的考试，拿不到则返回空列表。
  static Future<List<ExamEntry>> recoverExams(AuthSession? session) async {
    final data = await _recoverWithCredentials(session);
    return data?.exams ?? const [];
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
