part of '../login_page.dart';

class _BrandPanel extends StatelessWidget {
  const _BrandPanel();

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF0B4F9C), Color(0xFF082E5C)],
          ),
        ),
        child: Stack(
          children: [
            Positioned(
              right: -170,
              top: 120,
              child: _Ring(size: 380, opacity: 0.16),
            ),
            Positioned(
              right: -100,
              top: 180,
              child: _Ring(size: 260, opacity: 0.11),
            ),
            Positioned(
              left: -30,
              bottom: -80,
              child: Container(
                width: 260,
                height: 260,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      Colors.white.withValues(alpha: 0.08),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(38, 38, 34, 30),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const _LargeMark(),
                  const SizedBox(height: 44),
                  const Text(
                    'NORTHEASTERN UNIVERSITY',
                    style: TextStyle(
                      color: Color(0x99FFFFFF),
                      fontSize: 9,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 2.1,
                    ),
                  ),
                  const SizedBox(height: 13),
                  const Text(
                    '把琐碎留在这里，\n把时间还给自己。',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 34,
                      height: 1.45,
                      fontWeight: FontWeight.w600,
                      letterSpacing: -0.6,
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    '一个为东北大学学生做的\n开源校园客户端。',
                    style: TextStyle(
                      color: Color(0xB3FFFFFF),
                      fontSize: 12,
                      height: 1.8,
                    ),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.12),
                      ),
                    ),
                    child: const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _BrandPoint(
                          icon: Icons.calendar_month_outlined,
                          title: '课表',
                          description: '一周安排，打开就看',
                        ),
                        SizedBox(height: 12),
                        _BrandPoint(
                          icon: Icons.lock_outline_rounded,
                          title: '一号通',
                          description: '学校账号，直接登录',
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    '非官方 · 开源 · AGPL-3.0',
                    style: TextStyle(
                      color: Color(0x80FFFFFF),
                      fontSize: 9,
                      letterSpacing: 0.6,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MobileHero extends StatelessWidget {
  const _MobileHero({this.compact = false});

  /// 紧凑版：高度由父级 SizedBox 限定（约 150），内部字号/内边距同步收紧，
  /// 让登录卡片能在一屏内完整显示。
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: double.infinity,
      width: double.infinity,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF0B4F9C), Color(0xFF082E5C)],
        ),
      ),
      child: Stack(
        clipBehavior: Clip.hardEdge,
        children: [
          Positioned(
            right: -120,
            top: compact ? 4 : 36,
            child: _Ring(size: compact ? 210 : 300, opacity: 0.16),
          ),
          Positioned(
            right: -60,
            top: compact ? 44 : 92,
            child: _Ring(size: compact ? 140 : 200, opacity: 0.1),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(
              compact ? 20 : 24,
              compact ? 16 : 54,
              compact ? 20 : 24,
              0,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _LargeMark(size: compact ? 30 : 42),
                SizedBox(height: compact ? 10 : 22),
                Text(
                  'NORTHEASTERN UNIVERSITY',
                  style: TextStyle(
                    color: const Color(0x99FFFFFF),
                    fontSize: compact ? 7 : 8,
                    fontWeight: FontWeight.w600,
                    letterSpacing: compact ? 1.4 : 1.8,
                  ),
                ),
                SizedBox(height: compact ? 5 : 8),
                Text(
                  '把琐碎留在这里，\n把时间还给自己。',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: compact ? 18 : 28,
                    height: 1.28,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.4,
                  ),
                ),
                SizedBox(height: compact ? 3 : 7),
                Text(
                  '少一点翻找，多一点从容。',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.68),
                    fontSize: compact ? 9 : 10,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: TextStyle(
        color: AppColors.muted,
        fontSize: 11,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.2,
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.danger.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: AppColors.danger.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline_rounded, color: AppColors.danger, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                color: AppColors.danger,
                fontSize: 11,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniMark extends StatelessWidget {
  const _MiniMark();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [AppColors.campusBlue, AppColors.campusBlueDeep],
        ),
        borderRadius: BorderRadius.circular(8),
      ),
      alignment: Alignment.center,
      child: const Text(
        'N',
        style: TextStyle(
          color: Colors.white,
          fontSize: 14,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _LargeMark extends StatelessWidget {
  const _LargeMark({this.size = 46});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(size * 0.28),
        border: Border.all(color: Colors.white.withValues(alpha: 0.24)),
      ),
      alignment: Alignment.center,
      child: Text(
        'N',
        style: TextStyle(
          color: Colors.white,
          fontSize: size * 0.43,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _Ring extends StatelessWidget {
  const _Ring({required this.size, required this.opacity});

  final double size;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white.withValues(alpha: opacity)),
      ),
    );
  }
}

class _BrandPoint extends StatelessWidget {
  const _BrandPoint({
    required this.icon,
    required this.title,
    required this.description,
  });

  final IconData icon;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: Colors.white, size: 16),
        ),
        const SizedBox(width: 10),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              description,
              style: const TextStyle(color: Color(0x99FFFFFF), fontSize: 9),
            ),
          ],
        ),
      ],
    );
  }
}
