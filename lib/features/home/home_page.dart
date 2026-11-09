import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/app_theme.dart';
import '../../core/auth/auth_session.dart';
import '../auth/auth_controller.dart';
import '../timetable/timetable_page.dart';

class HomePage extends ConsumerWidget {
  const HomePage({super.key, required this.session});

  final AuthSession session;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final compact = MediaQuery.sizeOf(context).width < 760;
    return Scaffold(
      backgroundColor: AppColors.canvas,
      body: SafeArea(
        child: compact
            ? _buildCompact(context, ref)
            : _buildDesktop(context, ref),
      ),
    );
  }

  Widget _buildDesktop(BuildContext context, WidgetRef ref) {
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
              const _NavItem(
                icon: Icons.calendar_month_outlined,
                label: '课表',
                active: true,
              ),
              const _NavItem(
                icon: Icons.notifications_none_rounded,
                label: '通知',
              ),
              const _NavItem(icon: Icons.mail_outline_rounded, label: '邮件'),
              const _NavItem(icon: Icons.electric_bolt_outlined, label: '寝室用电'),
              const Spacer(),
              Padding(
                padding: const EdgeInsets.all(16),
                child: _AccountTile(
                  session: session,
                  onLogout: () => _logout(ref),
                ),
              ),
            ],
          ),
        ),
        const Expanded(child: TimetablePage()),
      ],
    );
  }

  Widget _buildCompact(BuildContext context, WidgetRef ref) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 12, 0),
          child: Row(
            children: [
              const _Brand(),
              const Spacer(),
              IconButton(
                tooltip: '退出登录',
                onPressed: () => _logout(ref),
                icon: const Icon(Icons.logout_rounded, size: 20),
              ),
            ],
          ),
        ),
        const Expanded(child: TimetablePage(compact: true)),
      ],
    );
  }

  Future<void> _logout(WidgetRef ref) async {
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
            gradient: const LinearGradient(
              colors: [AppColors.campusBlue, AppColors.campusBlueDeep],
            ),
            borderRadius: BorderRadius.circular(10),
          ),
          alignment: Alignment.center,
          child: const Text(
            'N',
            style: TextStyle(
              color: Colors.white,
              fontSize: 17,
              fontWeight: FontWeight.w800,
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
  });

  final IconData icon;
  final String label;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 10),
      decoration: BoxDecoration(
        color: active ? AppColors.campusBlue.withValues(alpha: 0.09) : null,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(
            icon,
            size: 19,
            color: active ? AppColors.campusBlue : AppColors.muted,
          ),
          const SizedBox(width: 11),
          Text(
            label,
            style: TextStyle(
              color: active ? AppColors.campusBlue : AppColors.muted,
              fontSize: 12,
              fontWeight: active ? FontWeight.w600 : FontWeight.w500,
            ),
          ),
          if (!active) ...[
            const Spacer(),
            const Text(
              '后续',
              style: TextStyle(color: AppColors.faint, fontSize: 9),
            ),
          ],
        ],
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
