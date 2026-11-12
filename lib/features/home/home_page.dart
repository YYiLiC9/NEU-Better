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

  /// 0 = 课表, 1 = 寝室用电, 2 = 设置。
  int _tab = 0;
  DormPrefs? _statusPrefs;

  @override
  void initState() {
    super.initState();
    // 监听「点击用电提醒通知 → 打开寝室用电页」：先装 MethodChannel 回调，
    // 再查询冷启动时原生是否已有待处理请求。
    NotificationRouter.ensureHandlerInstalled();
    NotificationRouter.openDormSignal.addListener(_handleOpenDorm);
    unawaited(NotificationRouter.consumePending());
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
    NotificationRouter.openDormSignal.removeListener(_handleOpenDorm);
    dormPrefsChanged.removeListener(_loadStatus);
    super.dispose();
  }

  /// 收到通知点击请求：切到「寝室用电」页（tab 1）。
  void _handleOpenDorm() {
    if (!mounted) return;
    debugPrint('[notify] openDorm -> switch to tab 1 (寝室用电)');
    setState(() => _tab = 1);
  }

  Future<void> _loadStatus() async {
    final prefs = await _elecService.loadPrefs();
    if (!mounted) return;
    setState(() => _statusPrefs = prefs);
    final reading = prefs.lastReading;
    unawaited(
      WindowsWindow.setTrayTooltip(
        reading == null ? 'NEU Better' : '寝室用电 ${reading.rawRemain}',
      ),
    );
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

  /// 宽窗口（桌面/平板）用左侧栏；窄窗口（手机）用底部导航。
  /// 断点按「可用窗口宽度」判断，而非硬件平台或屏幕方向
  /// （见 flutter-build-responsive-layout skill）。
  static const double _wideLayoutMinWidth = 760;

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.sizeOf(context).width >= _wideLayoutMinWidth;
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
        child: isWide
            ? Column(
                children: [
                  Expanded(child: _buildDesktop(context)),
                  _buildStatusBar(context),
                ],
              )
            : _buildMobile(context),
      ),
      bottomNavigationBar: isWide ? null : _buildMobileNav(context),
    );
  }

  /// 手机端布局：不再有顶部品牌行与设置/退出图标，三块内容全部交给
  /// 底部导航（课表 / 寝室用电 / 设置）。设置以内嵌页呈现。
  Widget _buildMobile(BuildContext context) {
    return IndexedStack(
      index: _tab,
      children: [
        TimetablePage(compact: true, mobile: true),
        DormPowerPage(),
        MobileSettingsPage(onLogout: _logout),
      ],
    );
  }

  /// 底部导航栏：课表 / 寝室用电 / 设置，配色沿用静蓝令牌。
  Widget _buildMobileNav(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.line)),
      ),
      child: NavigationBarTheme(
        data: NavigationBarThemeData(
          backgroundColor: AppColors.surface,
          indicatorColor: AppColors.campusBlue.withValues(alpha: 0.12),
          iconTheme: WidgetStateProperty.resolveWith((states) {
            final selected = states.contains(WidgetState.selected);
            return IconThemeData(
              color: selected ? AppColors.campusBlue : AppColors.muted,
              size: 22,
            );
          }),
          labelTextStyle: WidgetStateProperty.resolveWith((states) {
            final selected = states.contains(WidgetState.selected);
            return TextStyle(
              fontSize: 11,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
              color: selected ? AppColors.campusBlue : AppColors.muted,
            );
          }),
        ),
        child: NavigationBar(
          height: 62,
          selectedIndex: _tab,
          labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
          onDestinationSelected: (index) => setState(() => _tab = index),
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.calendar_month_outlined),
              selectedIcon: Icon(Icons.calendar_month),
              label: '课表',
            ),
            NavigationDestination(
              icon: Icon(Icons.electric_bolt_outlined),
              selectedIcon: Icon(Icons.electric_bolt),
              label: '寝室用电',
            ),
            NavigationDestination(
              icon: Icon(Icons.settings_outlined),
              selectedIcon: Icon(Icons.settings),
              label: '设置',
            ),
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
      crossAxisAlignment: CrossAxisAlignment.stretch,
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

  Future<void> _logout() async {
    await ref.read(authControllerProvider.notifier).logout();
  }
}
