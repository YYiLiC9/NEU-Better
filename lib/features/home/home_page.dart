import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/app_theme.dart';
import '../../core/auth/auth_session.dart';
import '../auth/auth_controller.dart';

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
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(36, 32, 36, 32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 980),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _TopBar(session: session),
                  const SizedBox(height: 36),
                  _WelcomeCard(session: session),
                  const SizedBox(height: 20),
                  const _RoadmapCard(),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCompact(BuildContext context, WidgetRef ref) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
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
          const SizedBox(height: 28),
          _WelcomeCard(session: session),
          const SizedBox(height: 16),
          const _RoadmapCard(),
          const SizedBox(height: 18),
          const Text(
            '非官方 · 开源 · AGPL-3.0',
            style: TextStyle(color: AppColors.faint, fontSize: 10),
          ),
        ],
      ),
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
    final initial = session.accountLabel.characters.first;
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
                    session.accountLabel,
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

class _TopBar extends StatelessWidget {
  const _TopBar({required this.session});

  final AuthSession session;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '下午好，${session.accountLabel}',
              style: Theme.of(context).textTheme.headlineSmall
                  ?.copyWith(fontSize: 28),
            ),
            const SizedBox(height: 5),
            const Text(
              '欢迎回到 NEU Better。',
              style: TextStyle(color: AppColors.muted, fontSize: 12),
            ),
          ],
        ),
        const Spacer(),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: AppColors.line),
            borderRadius: BorderRadius.circular(9),
          ),
          child: const Row(
            children: [
              Icon(Icons.circle, size: 7, color: AppColors.accent),
              SizedBox(width: 7),
              Text(
                '本地会话 · 已连接',
                style: TextStyle(color: AppColors.muted, fontSize: 10),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _WelcomeCard extends StatelessWidget {
  const _WelcomeCard({required this.session});

  final AuthSession session;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(26),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF0B4F9C), Color(0xFF083A72)],
        ),
        borderRadius: BorderRadius.circular(22),
        boxShadow: const [
          BoxShadow(
            color: Color(0x330B4F9C),
            blurRadius: 30,
            offset: Offset(0, 14),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned(
            right: -40,
            top: -70,
            child: Container(
              width: 220,
              height: 220,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: const Color(0x26FFFFFF)),
              ),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'MILESTONE 1 · 登录',
                style: TextStyle(
                  color: Color(0xB3FFFFFF),
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.5,
                ),
              ),
              const SizedBox(height: 14),
              const Text(
                '登录成功，会话已保存。',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.3,
                ),
              ),
              const SizedBox(height: 9),
              Text(
                session.studentId.trim().isEmpty
                    ? '已连接学校账号 · 下次打开会自动恢复登录状态。'
                    : '账号 ${session.studentId} · 下次打开会自动恢复登录状态。',
                style: const TextStyle(
                  color: Color(0xB3FFFFFF),
                  fontSize: 11,
                  height: 1.6,
                ),
              ),
              const SizedBox(height: 22),
              Row(
                children: [
                  _Pill(icon: Icons.check_circle_outline, label: '一号通已连接'),
                  const SizedBox(width: 8),
                  _Pill(icon: Icons.shield_outlined, label: 'Cookie 本机加密存储'),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white, size: 13),
          const SizedBox(width: 5),
          Text(label, style: const TextStyle(color: Colors.white, fontSize: 9)),
        ],
      ),
    );
  }
}

class _RoadmapCard extends StatelessWidget {
  const _RoadmapCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '下一步',
            style: TextStyle(
              color: AppColors.ink,
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'M2 会把研究生课表接入这里。当前可以先验证登录和重启后的会话恢复。',
            style: TextStyle(color: AppColors.muted, fontSize: 11, height: 1.7),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              _Step(index: '01', label: '登录', done: true),
              const _StepLine(done: true),
              _Step(index: '02', label: '课表', done: false),
              const _StepLine(done: false),
              _Step(index: '03', label: '设置', done: false),
              const _StepLine(done: false),
              _Step(index: '04', label: '打包', done: false),
            ],
          ),
        ],
      ),
    );
  }
}

class _Step extends StatelessWidget {
  const _Step({required this.index, required this.label, required this.done});

  final String index;
  final String label;
  final bool done;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 22,
          height: 22,
          decoration: BoxDecoration(
            color: done ? AppColors.campusBlue : AppColors.canvas,
            shape: BoxShape.circle,
            border: Border.all(
              color: done ? AppColors.campusBlue : AppColors.line,
            ),
          ),
          alignment: Alignment.center,
          child: done
              ? const Icon(Icons.check, color: Colors.white, size: 13)
              : Text(
                  index,
                  style: const TextStyle(color: AppColors.faint, fontSize: 8),
                ),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(
            color: done ? AppColors.ink : AppColors.muted,
            fontSize: 10,
            fontWeight: done ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      ],
    );
  }
}

class _StepLine extends StatelessWidget {
  const _StepLine({required this.done});

  final bool done;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        height: 1,
        margin: const EdgeInsets.symmetric(horizontal: 6),
        color: done
            ? AppColors.campusBlue.withValues(alpha: 0.4)
            : AppColors.line,
      ),
    );
  }
}
