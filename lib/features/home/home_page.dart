import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/app_theme.dart';
import '../../core/auth/auth_session.dart';
import '../../core/platform/windows_window.dart';
import '../../core/settings/app_settings.dart';
import '../auth/auth_controller.dart';
import '../dorm/dorm_page.dart';
import '../dorm/electricity_alert.dart';
import '../../core/electricity/electricity_models.dart';
import '../dorm/electricity_service.dart';
import '../settings/settings_page.dart';
import '../timetable/timetable_page.dart';
import '../timetable/timetable_sync.dart';

part 'widgets/home_chrome.dart';

class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key, required this.session});

  final AuthSession session;

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> {
  final _elecService = DormElectricityService();

  /// 0 = 课表, 1 = 寝室用电。
  int _tab = 0;
  DormPrefs? _statusPrefs;

  @override
  void initState() {
    super.initState();
    _loadStatus();
    dormPrefsChanged.addListener(_loadStatus);
    final settings = ref.read(appSettingsProvider);
    unawaited(
      WindowsWindow.setCloseBehavior(
        minimizeToTaskbar: settings.minimizeOnClose && settings.showTrayIcon,
      ),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _runDailyElectricityCheck();
      // 刚刚登录（而非恢复旧会话）时后台同步一次课表。
      final sinceLogin = DateTime.now().difference(widget.session.createdAt);
      if (!sinceLogin.isNegative && sinceLogin < const Duration(minutes: 3)) {
        _autoSyncTimetable();
      }
    });
  }

  Future<void> _autoSyncTimetable() async {
    final data = await TimetableSyncService.syncWithSession(widget.session);
    if (data != null && mounted) {
      debugPrint('[timetable] auto synced ${data.sessions.length} sessions');
    }
  }

  @override
  void dispose() {
    dormPrefsChanged.removeListener(_loadStatus);
    super.dispose();
  }

  Future<void> _loadStatus() async {
    final prefs = await _elecService.loadPrefs();
    if (!mounted) return;
    setState(() => _statusPrefs = prefs);
    final reading = prefs.lastReading;
    if (reading != null) {
      unawaited(
        WindowsWindow.setTaskbarTitle('NEU Better · 寝室用电 ${reading.rawRemain}'),
      );
    }
  }

  /// 每日一次：打开软件时若今天还没查过电量就查一次；
  /// 结果低于提醒线时弹窗 + Windows 通知。
  Future<void> _runDailyElectricityCheck() async {
    final reading = await _elecService.dailyCheck(session: widget.session);
    if (!mounted || reading == null) return;
    final prefs = await _elecService.loadPrefs();
    if (!DormElectricityService.isLow(reading, prefs.alertThreshold)) return;
    if (!mounted) return;
    await DormAlertPresenter.present(
      context,
      reading: reading,
      prefs: prefs,
      onView: () => setState(() => _tab = 1),
    );
  }

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 760;
    // 主题切换时让 HomePage 及其 IndexedStack 子页面一起重建。
    ref.watch(appSettingsProvider.select((settings) => settings.isDarkNow));
    ref.listen<AppSettingsController>(appSettingsProvider, (previous, next) {
      unawaited(
        WindowsWindow.setCloseBehavior(
          minimizeToTaskbar: next.minimizeOnClose && next.showTrayIcon,
        ),
      );
    });
    return Scaffold(
      backgroundColor: AppColors.canvas,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: compact ? _buildCompact(context) : _buildDesktop(context),
            ),
            _buildStatusBar(context),
          ],
        ),
      ),
    );
  }

  Future<void> _openSettings() async {
    await showSettingsDialog(context);
  }

  Widget _buildStatusBar(BuildContext context) {
    final reading = _statusPrefs?.lastReading;
    final remaining = reading?.rawRemain.trim() ?? '';
    final text = remaining.isEmpty ? '--' : remaining;
    return InkWell(
      onTap: () => setState(() => _tab = 1),
      child: Container(
        height: 28,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          border: Border(top: BorderSide(color: AppColors.line)),
        ),
        child: Row(
          children: [
            const Spacer(),
            Icon(
              Icons.electric_bolt_rounded,
              size: 13,
              color: remaining.isEmpty ? AppColors.faint : AppColors.campusBlue,
            ),
            const SizedBox(width: 4),
            Text(
              text,
              maxLines: 1,
              style: TextStyle(
                color: remaining.isEmpty ? AppColors.faint : AppColors.ink,
                fontSize: 10,
                fontWeight: FontWeight.w600,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDesktop(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 224,
          decoration: BoxDecoration(
            color: AppColors.surface,
            border: Border(right: BorderSide(color: AppColors.line)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(22, 20, 8, 20),
                child: SizedBox(height: 48, child: _Brand()),
              ),
              _NavItem(
                icon: Icons.calendar_month_outlined,
                label: '课表',
                active: _tab == 0,
                onTap: () => setState(() => _tab = 0),
              ),
              _NavItem(
                icon: Icons.electric_bolt_outlined,
                label: '寝室用电',
                active: _tab == 1,
                onTap: () => setState(() => _tab = 1),
              ),
              const _NavItem(
                icon: Icons.notifications_none_rounded,
                label: '通知',
                comingSoon: true,
              ),
              const _NavItem(
                icon: Icons.mail_outline_rounded,
                label: '邮件',
                comingSoon: true,
              ),
              const Spacer(),
              Padding(
                padding: const EdgeInsets.all(16),
                child: _AccountTile(
                  session: widget.session,
                  onLogout: _logout,
                  onSettings: _openSettings,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: IndexedStack(
            index: _tab,
            children: [TimetablePage(), DormPowerPage()],
          ),
        ),
      ],
    );
  }

  Widget _buildCompact(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 12, 8),
          child: Row(
            children: [
              const _Brand(),
              const Spacer(),
              IconButton(
                tooltip: '设置',
                onPressed: _openSettings,
                icon: Icon(
                  Icons.settings_outlined,
                  size: 21,
                  color: AppColors.campusBlue,
                ),
              ),
              IconButton(
                tooltip: '退出登录',
                onPressed: _logout,
                icon: const Icon(Icons.logout_rounded, size: 20),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: _compactSwitcher(),
        ),
        const SizedBox(height: 4),
        Expanded(
          child: IndexedStack(
            index: _tab,
            children: [TimetablePage(compact: true), DormPowerPage()],
          ),
        ),
      ],
    );
  }

  Widget _compactSwitcher() {
    return Container(
      height: 36,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: AppColors.canvas,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: AppColors.line),
      ),
      child: Row(
        children: [
          _compactTab('课表', Icons.calendar_month_outlined, 0),
          _compactTab('寝室用电', Icons.electric_bolt_outlined, 1),
        ],
      ),
    );
  }

  Widget _compactTab(String label, IconData icon, int index) {
    final active = _tab == index;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _tab = index),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: active ? AppColors.surface : Colors.transparent,
            borderRadius: BorderRadius.circular(7),
            border: active ? Border.all(color: AppColors.line) : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 14,
                color: active ? AppColors.campusBlue : AppColors.muted,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                  color: active ? AppColors.ink : AppColors.muted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _logout() async {
    await ref.read(authControllerProvider.notifier).logout();
  }
}
