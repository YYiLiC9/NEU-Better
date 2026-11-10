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
import '../dorm/electricity_models.dart';
import '../dorm/electricity_service.dart';
import '../settings/settings_page.dart';
import '../timetable/timetable_page.dart';

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
        minimizeToTaskbar: settings.minimizeOnClose,
      ),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _runDailyElectricityCheck();
    });
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
        WindowsWindow.setCloseBehavior(minimizeToTaskbar: next.minimizeOnClose),
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
    await Navigator.of(context)
        .push(MaterialPageRoute<void>(builder: (_) => const SettingsPage()));
  }

  Widget _buildStatusBar(BuildContext context) {
    final reading = _statusPrefs?.lastReading;
    final room = reading?.roomInfo ?? '';
    final text = reading == null
        ? '寝室用电 · 暂无电量数据'
        : '寝室用电 · ${room.isEmpty ? reading.roomCode : room} · '
              '剩余 ${reading.rawRemain}';
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
            Icon(
              Icons.electric_bolt_rounded,
              size: 13,
              color: reading == null ? AppColors.faint : AppColors.campusBlue,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: AppColors.muted,
                  fontSize: 10,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
            Text(
              '点击查看用电',
              style: TextStyle(color: AppColors.faint, fontSize: 9),
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
              Padding(
                padding: const EdgeInsets.fromLTRB(22, 20, 8, 20),
                child: SizedBox(
                  height: 48,
                  child: Row(
                    children: [
                      const Expanded(child: _Brand()),
                      Tooltip(
                        message: '设置',
                        child: InkWell(
                          onTap: _openSettings,
                          borderRadius: BorderRadius.circular(8),
                          child: Padding(
                            padding: const EdgeInsets.all(6),
                            child: Icon(
                              Icons.settings_outlined,
                              size: 18,
                              color: AppColors.muted,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
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
                child: _AccountTile(session: widget.session, onLogout: _logout),
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
                  size: 20,
                  color: AppColors.muted,
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

class _Brand extends StatelessWidget {
  const _Brand();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: AppColors.campusBlue,
            borderRadius: BorderRadius.circular(9),
          ),
          alignment: Alignment.center,
          child: Text(
            '静',
            style: TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w700,
              height: 1.0,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'NEU Better',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: AppColors.ink,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
              SizedBox(height: 2),
              Text(
                'NORTHEASTERN UNIVERSITY',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: AppColors.faint,
                  fontSize: 7,
                  letterSpacing: 0.8,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.label,
    this.active = false,
    this.comingSoon = false,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final bool active;
  final bool comingSoon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final dim = comingSoon;
    return Opacity(
      opacity: dim ? 0.55 : 1,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 10),
          decoration: BoxDecoration(
            color: active ? AppColors.campusBlue : null,
            borderRadius: BorderRadius.circular(9),
          ),
          child: Row(
            children: [
              Icon(
                icon,
                size: 19,
                color: active ? Colors.white : AppColors.muted,
              ),
              const SizedBox(width: 11),
              Text(
                label,
                style: TextStyle(
                  color: active ? Colors.white : AppColors.muted,
                  fontSize: 12,
                  fontWeight: active ? FontWeight.w600 : FontWeight.w500,
                ),
              ),
              if (comingSoon) ...[
                const Spacer(),
                Text(
                  '后续',
                  style: TextStyle(color: AppColors.faint, fontSize: 9),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _AccountTile extends StatelessWidget {
  const _AccountTile({required this.session, required this.onLogout});

  final AuthSession session;
  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) {
    final label = session.accountLabel.trim();
    final initial = label.isEmpty ? 'N' : label.characters.first;
    return Column(
      children: [
        Row(
          children: [
            CircleAvatar(
              radius: 17,
              backgroundColor: AppColors.campusBlue.withValues(alpha: 0.1),
              child: Text(
                initial,
                style: TextStyle(
                  color: AppColors.campusBlue,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label.isEmpty ? '已连接学校账号' : label,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: AppColors.ink,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '研究生 · 已登录',
                    style: TextStyle(color: AppColors.muted, fontSize: 9),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          height: 30,
          child: TextButton(
            onPressed: onLogout,
            style: TextButton.styleFrom(
              foregroundColor: AppColors.muted,
              padding: EdgeInsets.zero,
              textStyle: TextStyle(fontSize: 10),
            ),
            child: Text('退出登录'),
          ),
        ),
      ],
    );
  }
}
