import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/app_theme.dart';
import '../../core/app_labels.dart';
import '../../core/network/neu_elec_client.dart' show ElectricityQueryException;
import '../auth/auth_controller.dart';
import 'electricity_alert.dart';
import '../../core/electricity/electricity_models.dart';
import 'electricity_service.dart';
import 'campus_card_balance_card.dart';
import '../../core/network/net_fee_client.dart';

part 'widgets/dorm_cards.dart';

/// 寝室用电：填一次房间码，之后随时查看剩余电量。
///
/// 楼栋编号表来自后勤处缴费编号页（2024-07-02 版，实测 3510409/2600116 命中）；
/// 也可以直接输入 7/8 位完整房间码（空调楼为 8 位）。
class DormPowerPage extends ConsumerStatefulWidget {
  const DormPowerPage({super.key, this.embedded = false});

  /// 内嵌在首页二级页时隐藏自带的大标题（外层已提供返回栏与标题）。
  final bool embedded;

  @override
  ConsumerState<DormPowerPage> createState() => _DormPowerPageState();
}

class _DormPowerPageState extends ConsumerState<DormPowerPage> {
  final _service = DormElectricityService();

  DormPrefs _prefs = const DormPrefs();
  bool _loading = false;
  bool _editing = false;
  String? _error;

  // 网费余额（进入余额中心自动刷新）。
  double? _netBalance;
  bool _netLoading = false;
  String? _netError;

  String _campus = '浑南校区';
  String? _buildingCode;
  final _roomController = TextEditingController();
  final _fullCodeController = TextEditingController();
  final _thresholdController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _thresholdController.text = '20';
    _loadPrefs();
    _loadNetFee();
    // 后台每日查询完成后自动刷新（home 页每日检查会触发信号）。
    dormPrefsChanged.addListener(_loadPrefs);
  }

  @override
  void dispose() {
    dormPrefsChanged.removeListener(_loadPrefs);
    _roomController.dispose();
    _fullCodeController.dispose();
    _thresholdController.dispose();
    super.dispose();
  }

  Future<void> _loadPrefs() async {
    final prefs = await _service.loadPrefs();
    if (!mounted) return;
    setState(() {
      _prefs = prefs;
      _thresholdController.text = prefs.alertThreshold == 0
          ? '20'
          : prefs.alertThreshold.truncate().toString();
      if (prefs.roomCode != null &&
          prefs.roomCode!.trim().isNotEmpty &&
          _fullCodeController.text.isEmpty) {
        _applyRoomCodeToFields(prefs.roomCode!);
      }
    });
  }

  double get _threshold {
    final value = double.tryParse(_thresholdController.text.trim());
    return value == null || value <= 0 ? 20 : value;
  }

  /// 进入余额中心时自动查询一次网费余额。
  Future<void> _loadNetFee() async {
    final auth = ref.read(authControllerProvider);
    final session = auth is AuthAuthenticated ? auth.session : null;
    if (session == null) return;
    if (mounted) {
      setState(() {
        _netLoading = true;
        _netError = null;
      });
    }
    try {
      final value = await NetFeeClient().queryWithSession(session: session);
      if (!mounted) return;
      setState(() {
        _netBalance = value;
        _netLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _netLoading = false;
        _netError = error is NetFeeQueryException ? error.message : '网费查询失败';
      });
    }
  }

  // 完整房间码 ↔ 校区/楼栋/寝室号 双向联动。

  /// 把 7/8 位完整房间码解析成 (校区, 楼栋编号, 寝室号)。寝室号去掉前导 0。
  (String, String, String)? _resolveRoomCode(String code) {
    final digits = code.replaceAll(RegExp(r'\D'), '');
    for (final entry in dormCampusNames.entries) {
      for (final building in entry.value) {
        if (digits.length == building.code.length + 4 &&
            digits.startsWith(building.code)) {
          var room = digits.substring(building.code.length);
          room = room.replaceFirst(RegExp(r'^0+'), '');
          if (room.isEmpty) room = '0';
          return (entry.key, building.code, room);
        }
      }
    }
    return null;
  }

  /// 顶部完整房间码变化 → 反填校区/楼栋/寝室号。
  void _onFullCodeChanged(String raw) {
    final resolved = _resolveRoomCode(raw);
    if (resolved == null) return;
    if (_campus == resolved.$1 &&
        _buildingCode == resolved.$2 &&
        _roomController.text == resolved.$3) {
      return;
    }
    setState(() {
      _campus = resolved.$1;
      _buildingCode = resolved.$2;
      _roomController.text = resolved.$3;
    });
  }

  /// 校区/楼栋/寝室号变化 → 正向填回完整房间码。
  void _syncFullCodeFromParts() {
    final code = _buildingCode;
    final room = _roomController.text.trim();
    if (code == null || room.isEmpty) return;
    final full = buildRoomCode(code, room);
    if (_fullCodeController.text != full) {
      _fullCodeController.text = full;
    }
  }

  /// 用完整房间码初始化表单（保存后 / 恢复历史房间时）。
  void _applyRoomCodeToFields(String code) {
    _fullCodeController.text = code;
    final resolved = _resolveRoomCode(code);
    if (resolved == null) return;
    _campus = resolved.$1;
    _buildingCode = resolved.$2;
    _roomController.text = resolved.$3;
  }

  bool get _isLow =>
      _prefs.lastReading != null &&
      DormElectricityService.isLow(_prefs.lastReading!, _prefs.alertThreshold);

  Future<void> _saveAndQuery({required String roomCode}) async {
    final code = roomCode.trim();
    if (code.length < 7 || code.length > 8 || int.tryParse(code) == null) {
      setState(() => _error = '房间码应为 7 位数字（空调楼 8 位）');
      return;
    }
    final prefs = DormPrefs(
      roomCode: code,
      alertThreshold: _threshold,
      lastQueryDate: _prefs.lastQueryDate,
      lastReading: _prefs.lastReading,
    );
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final auth = ref.read(authControllerProvider);
      final session = auth is AuthAuthenticated ? auth.session : null;
      final reading = await _service.queryNow(prefs, session: session);
      final saved = await _service.loadPrefs();
      if (!mounted) return;
      setState(() {
        _prefs = saved;
        _loading = false;
        _editing = false;
      });
      _showSnack('${reading.roomInfo} · 剩余 ${reading.rawRemain}');
    } on ElectricityQueryException catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.message;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = '查询失败：$error';
        _loading = false;
      });
    }
  }

  Future<void> _refresh() async {
    await _saveAndQuery(roomCode: _prefs.roomCode ?? '');
  }

  Future<void> _updateThreshold(double value) async {
    final prefs = DormPrefs(
      roomCode: _prefs.roomCode,
      alertThreshold: value,
      lastQueryDate: _prefs.lastQueryDate,
      lastReading: _prefs.lastReading,
    );
    await _service.savePrefs(prefs);
    if (!mounted) return;
    setState(() => _prefs = prefs);
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _testNotification() async {
    final reading = _prefs.lastReading;
    if (reading == null) {
      _showSnack('请先查询一次电量，测试通知会使用当前读数');
      return;
    }
    await DormAlertPresenter.present(context, reading: reading, prefs: _prefs);
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authControllerProvider);
    final session = auth is AuthAuthenticated ? auth.session : null;
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        _compact ? 20 : 36,
        _compact ? 8 : 32,
        _compact ? 20 : 36,
        32,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (!widget.embedded) ...[
                _buildHeader(),
                const SizedBox(height: 22),
              ],
              if (session != null) ...[
                CampusCardBalanceCard(
                  session: session,
                  onNetFee: (value) {
                    final parsed = value == null ? null : double.tryParse(value);
                    if (parsed == null || !mounted) return;
                    setState(() {
                      _netBalance = parsed;
                      _netLoading = false;
                      _netError = null;
                    });
                  },
                ),
                const SizedBox(height: 12),
              ],
              _buildNetFeeCard(),
              const SizedBox(height: 16),
              if (!_prefs.hasRoom || _editing) ...[
                _buildSetupCard(),
              ] else ...[
                if (_prefs.lastReading != null)
                  _buildReadingCard(_prefs.lastReading!)
                else
                  _buildEmptyReadingCard(),
                const SizedBox(height: 16),
                _buildThresholdCard(),
              ],
              if (_error != null) ...[
                const SizedBox(height: 16),
                _buildErrorBanner(_error!),
              ],
              const SizedBox(height: 18),
              Text(
                '系统电表每天 6:00 更新一次，当天查询均为当日 6:00 读数；23:30–6:00 系统维护，无法查询。',
                style: TextStyle(fontSize: 9, color: AppColors.faint),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _rebuild(VoidCallback fn) => setState(fn);

  bool get _compact => MediaQuery.sizeOf(context).width < 760;
}
