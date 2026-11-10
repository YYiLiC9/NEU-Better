import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:local_notifier/local_notifier.dart';

import '../../app/theme/app_theme.dart';
import '../../core/auth/auth_session.dart';
import '../auth/auth_controller.dart';
import '../dorm/dorm_page.dart';
import '../dorm/electricity_service.dart';
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
  /// 0 = 课表, 1 = 寝室用电。
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _runDailyElectricityCheck();
    });
  }

  /// 每日一次：打开软件时若今天还没查过电量就查一次；
  /// 结果低于提醒线时弹窗 + Windows 通知。
  Future<void> _runDailyElectricityCheck() async {
    final reading = await _elecService.dailyCheck();
    if (!mounted || reading == null) return;
    final prefs = await _elecService.loadPrefs();
    if (!DormElectricityService.isLow(reading, prefs.alertThreshold)) return;
    // Windows toast 尽力而为：插件初始化失败（如 AUMI 快捷方式未建好）时
    // 不能卡住后续的弹窗提醒，所以加超时并吞掉一切异常。
    if (Platform.isWindows) {
      try {
        final notification = LocalNotification(
          title: '寝室电量不足',
          body: '${reading.roomInfo} · 剩余 ${reading.rawRemain}，低于提醒线'
              '（${prefs.alertThreshold.truncate()} 度）',
        );
        await notification
            .show()
            .timeout(const Duration(seconds: 3), onTimeout: () {});
      } catch (error) {
        debugPrint('[elec] notification failed: $error');
      }
    }
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: AppColors.line),
        ),
        title: Row(
          children: [
            Icon(Icons.bolt_rounded, size: 22, color: AppColors.nowRed),
            const SizedBox(width: 8),
            Text(
              '寝室电量不足',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AppColors.ink,
              ),
            ),
          ],
        ),
        content: Text(
          '${reading.roomInfo}\n剩余 ${reading.rawRemain}，'
          '已低于提醒线 ${prefs.alertThreshold.truncate()} 度，建议尽快充值。',
          style: TextStyle(
            fontSize: 12,
            height: 1.6,
            color: AppColors.muted,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('知道了'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.campusBlue,
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              Navigator.of(dialogContext).pop();
              setState(() => _tab = 1);
            },
            child: const Text('查看电量'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 760;
    return Scaffold(
      backgroundColor: AppColors.canvas,
      body: SafeArea(
        child: compact
            ? _buildCompact(context)
            : _buildDesktop(context),
      ),
    );
  }

  Widget _buildDesktop(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 224,
          decoration: const BoxDecoration(
            color: Colors.white,
            border: Border(right: BorderSide(color: AppColors.line)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(22, 24, 18, 28),
                child: _Brand(),
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
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: IndexedStack(
            index: _tab,
            children: const [
              TimetablePage(),
              DormPowerPage(),
            ],
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
            children: const [
              TimetablePage(compact: true),
              DormPowerPage(),
            ],
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
            color: active ? Colors.white : Colors.transparent,
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
          child: const Text(
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
        const Flexible(
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
                const Text(
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
                style: const TextStyle(
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
                    style: const TextStyle(
                      color: AppColors.ink,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  const Text(
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
              textStyle: const TextStyle(fontSize: 10),
            ),
            child: const Text('退出登录'),
          ),
        ),
      ],
    );
  }
}
