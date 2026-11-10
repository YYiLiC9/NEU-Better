import 'package:flutter/foundation.dart';

import '../../core/auth/credential_store.dart';
import '../../core/network/neu_elec_client.dart';
import 'electricity_models.dart';
import 'electricity_store.dart';

/// 电量数据变化信号：后台每日查询或页面查询成功后自增，
/// 监听方（寝室页）据此重新读盘刷新界面。
final ValueNotifier<int> dormPrefsChanged = ValueNotifier<int>(0);

/// Shared dorm-electricity logic: prefs persistence + live query, used by the
/// dorm page (manual refresh) and the daily-once startup check.
class DormElectricityService {
  DormElectricityService({ElectricityStore? store, NeuElecClient? client})
      : _store = store ?? const ElectricityStore(),
        _client = client ?? NeuElecClient();

  final ElectricityStore _store;
  final NeuElecClient _client;

  Future<DormPrefs> loadPrefs() => _store.read();

  Future<void> savePrefs(DormPrefs prefs) => _store.save(prefs);

  /// Queries now with saved credentials, persists prefs
  /// (lastQueryDate = today, lastReading), returns the reading.
  ///
  /// Throws [ElectricityQueryException] / [StateError] on failure so callers
  /// can surface the message; daily-once checks should catch everything.
  Future<ElectricityReading> queryNow(DormPrefs prefs) async {
    if (!prefs.hasRoom) {
      throw const ElectricityQueryException('请先填写寝室房间码');
    }
    final credentials = await SecureCredentialStore().read();
    if (credentials == null ||
        credentials.password == null ||
        credentials.password!.isEmpty) {
      throw const ElectricityQueryException('未保存账号密码，请先在登录页登录');
    }
    final reading = await _client.query(
      username: credentials.username,
      password: credentials.password!,
      roomCode: prefs.roomCode!.trim(),
    );
    final today = DateTime.now();
    await savePrefs(
      DormPrefs(
        roomCode: prefs.roomCode,
        alertThreshold: prefs.alertThreshold,
        lastQueryDate: DateTime(today.year, today.month, today.day),
        lastReading: reading,
      ),
    );
    dormPrefsChanged.value++;
    return reading;
  }

  /// Daily-once startup check. Returns the fresh reading only when a room is
  /// saved, it has not been queried today, credentials exist, and the query
  /// succeeded; otherwise returns null (silent — the dorm page still shows
  /// the cached reading).
  Future<ElectricityReading?> dailyCheck() async {
    final prefs = await loadPrefs();
    if (!prefs.hasRoom) return null;
    final today = DateTime.now();
    final last = prefs.lastQueryDate;
    if (last != null &&
        last.year == today.year &&
        last.month == today.month &&
        last.day == today.day) {
      debugPrint('[elec] daily check skipped: already queried today');
      return null;
    }
    try {
      final reading = await queryNow(prefs);
      debugPrint('[elec] daily check ok: ${reading.rawRemain}');
      return reading;
    } catch (error) {
      debugPrint('[elec] daily check failed: $error');
      return null;
    }
  }

  /// True when the reading is at or below the alert threshold.
  static bool isLow(ElectricityReading reading, double threshold) {
    return reading.remainKwh <= threshold;
  }
}
