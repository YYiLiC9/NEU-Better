import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/app_theme.dart';
import '../../core/auth/credential_store.dart';
import '../../core/auth/webview_login_result.dart';
import 'auth_controller.dart';
import 'webview_login_page.dart';

class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;
  bool _rememberMe = true;
  bool _rememberCredentials = true;

  @override
  void initState() {
    super.initState();
    unawaited(_restoreCredentials());
  }

  Future<void> _restoreCredentials() async {
    final saved = await ref.read(credentialStoreProvider).read();
    if (!mounted || saved == null) return;
    if (_usernameController.text.isEmpty) {
      _usernameController.text = saved.username;
    }
    if (_passwordController.text.isEmpty && saved.password != null) {
      _passwordController.text = saved.password!;
    }
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (ref.read(authControllerProvider) is AuthBusy) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;
    FocusManager.instance.primaryFocus?.unfocus();
    await ref
        .read(authControllerProvider.notifier)
        .login(
          username: _usernameController.text,
          password: _passwordController.text,
          saveCredentials: _rememberCredentials,
        );
  }

  Future<void> _openWebLogin() async {
    final typedUsername = _usernameController.text.trim();
    final typedPassword = _passwordController.text;
    final result = await Navigator.of(context).push<WebViewLoginResult>(
      MaterialPageRoute(builder: (_) => const WebViewLoginPage()),
    );
    if (result == null || !result.hasCookies) return;
    await ref
        .read(authControllerProvider.notifier)
        .loginWithCookies(
          result: result,
          fallbackStudentId: typedUsername.isEmpty ? null : typedUsername,
          typedUsername: typedUsername.isEmpty ? null : typedUsername,
          typedPassword: typedPassword.isEmpty ? null : typedPassword,
          saveCredentials: _rememberCredentials,
        );
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authControllerProvider);
    final busy = authState is AuthBusy;
    final message = authState is AuthUnauthenticated ? authState.message : null;

    return Scaffold(
      backgroundColor: AppColors.canvas,
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFF8FBFF), Color(0xFFE9F1FA)],
          ),
        ),
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= 900;
              if (wide) {
                return Row(
                  children: [
                    const Expanded(flex: 5, child: _BrandPanel()),
                    Expanded(
                      flex: 7,
                      child: Center(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 48,
                            vertical: 40,
                          ),
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 430),
                            child: _buildCard(
                              context,
                              compact: false,
                              busy: busy,
                              message: message,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              }

              return SingleChildScrollView(
                child: Column(
                  children: [
                    const _MobileHero(),
                    Transform.translate(
                      offset: const Offset(0, -34),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 18),
                        child: _buildCard(
                          context,
                          compact: true,
                          busy: busy,
                          message: message,
                        ),
                      ),
                    ),
                    const Padding(
                      padding: EdgeInsets.only(bottom: 22),
                      child: Text(
                        '非官方 · 开源 · AGPL-3.0',
                        style: TextStyle(
                          color: AppColors.faint,
                          fontSize: 10,
                          letterSpacing: 0.4,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildCard(
    BuildContext context, {
    required bool compact,
    required bool busy,
    required String? message,
  }) {
    return Container(
      padding: EdgeInsets.fromLTRB(
        compact ? 22 : 34,
        compact ? 24 : 34,
        compact ? 22 : 34,
        compact ? 22 : 30,
      ),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.96),
        borderRadius: BorderRadius.circular(compact ? 22 : 24),
        border: Border.all(color: Colors.white),
        boxShadow: const [
          BoxShadow(
            color: Color(0x1A0B2E5C),
            blurRadius: 42,
            offset: Offset(0, 18),
          ),
        ],
      ),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const _MiniMark(),
                const SizedBox(width: 10),
                Text(
                  '东北大学 · 一号通',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: AppColors.campusBlue,
                    letterSpacing: 0.8,
                  ),
                ),
              ],
            ),
            SizedBox(height: compact ? 20 : 26),
            Text(
              '登录你的校园',
              style: Theme.of(context).textTheme.headlineSmall
                  ?.copyWith(fontSize: compact ? 25 : 28),
            ),
            const SizedBox(height: 8),
            Text(
              '使用学校统一身份认证账号登录。登录状态只保存在本机。',
              style: Theme.of(context).textTheme.bodyMedium
                  ?.copyWith(fontSize: compact ? 12 : 13),
            ),
            SizedBox(height: compact ? 20 : 24),
            const _LoginTabs(),
            SizedBox(height: compact ? 18 : 22),
            _FieldLabel(label: '学号'),
            const SizedBox(height: 7),
            TextFormField(
              controller: _usernameController,
              enabled: !busy,
              autofillHints: const [AutofillHints.username],
              keyboardType: TextInputType.text,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                hintText: '输入学号',
                prefixIcon: Icon(Icons.badge_outlined, size: 19),
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return '请输入学号';
                }
                return null;
              },
            ),
            const SizedBox(height: 15),
            _FieldLabel(label: '密码'),
            const SizedBox(height: 7),
            TextFormField(
              controller: _passwordController,
              enabled: !busy,
              autofillHints: const [AutofillHints.password],
              obscureText: _obscurePassword,
              textInputAction: TextInputAction.done,
              onFieldSubmitted: (_) => _submit(),
              decoration: InputDecoration(
                hintText: '输入统一身份认证密码',
                prefixIcon: const Icon(Icons.lock_outline_rounded, size: 19),
                suffixIcon: IconButton(
                  tooltip: _obscurePassword ? '显示密码' : '隐藏密码',
                  onPressed: () {
                    setState(() => _obscurePassword = !_obscurePassword);
                  },
                  icon: Icon(
                    _obscurePassword
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                    size: 19,
                  ),
                ),
              ),
              validator: (value) {
                if (value == null || value.isEmpty) return '请输入密码';
                return null;
              },
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                SizedBox(
                  width: 20,
                  height: 20,
                  child: Checkbox(
                    value: _rememberMe,
                    onChanged: busy
                        ? null
                        : (value) {
                            setState(() => _rememberMe = value ?? true);
                          },
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(5),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                const Text(
                  '保持登录',
                  style: TextStyle(color: AppColors.muted, fontSize: 12),
                ),
                const Spacer(),
                const Text(
                  '仅保存在本机',
                  style: TextStyle(color: AppColors.faint, fontSize: 10),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                SizedBox(
                  width: 20,
                  height: 20,
                  child: Checkbox(
                    value: _rememberCredentials,
                    onChanged: busy
                        ? null
                        : (value) {
                            setState(
                              () => _rememberCredentials = value ?? true,
                            );
                          },
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(5),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                const Text(
                  '保存账号密码',
                  style: TextStyle(color: AppColors.muted, fontSize: 12),
                ),
                const Spacer(),
                const Text(
                  '使用系统安全存储',
                  style: TextStyle(color: AppColors.faint, fontSize: 10),
                ),
              ],
            ),
            if (message != null && message.isNotEmpty) ...[
              const SizedBox(height: 14),
              _ErrorBanner(message: message),
            ],
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              height: compact ? 46 : 48,
              child: FilledButton(
                onPressed: busy ? null : _submit,
                child: busy
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.2,
                          color: Colors.white,
                        ),
                      )
                    : const Text(
                        '登录',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.6,
                        ),
                      ),
              ),
            ),
            const SizedBox(height: 8),
            Center(
              child: TextButton.icon(
                onPressed: busy ? null : _openWebLogin,
                icon: const Icon(Icons.open_in_browser_rounded, size: 16),
                label: const Text('使用学校网页登录（验证码 / 二次验证）'),
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.campusBlue,
                  textStyle: const TextStyle(fontSize: 11),
                ),
              ),
            ),
            const SizedBox(height: 6),
            const Center(
              child: Text(
                '账号密码只用于登录学校系统，不会上传到任何第三方服务器。',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppColors.faint,
                  fontSize: 10,
                  height: 1.6,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

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
                    '你的校园，\n清楚一点。',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 36,
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
                          description: '周视图 · 单双周 · 本地缓存',
                        ),
                        SizedBox(height: 12),
                        _BrandPoint(
                          icon: Icons.lock_outline_rounded,
                          title: '一号通',
                          description: '原生登录 · 会话只保存在本机',
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
  const _MobileHero();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 300,
      width: double.infinity,
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
            right: -120,
            top: 36,
            child: _Ring(size: 300, opacity: 0.16),
          ),
          Positioned(
            right: -60,
            top: 92,
            child: _Ring(size: 200, opacity: 0.1),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 54, 24, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _LargeMark(size: 42),
                const SizedBox(height: 22),
                const Text(
                  'NORTHEASTERN UNIVERSITY',
                  style: TextStyle(
                    color: Color(0x99FFFFFF),
                    fontSize: 8,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1.8,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  '你的校园，清楚一点。',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    height: 1.35,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.4,
                  ),
                ),
                const SizedBox(height: 7),
                Text(
                  '课表、通知与校园服务，慢慢装进一个地方。',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.68),
                    fontSize: 10,
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

class _LoginTabs extends StatelessWidget {
  const _LoginTabs();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          height: 30,
          padding: const EdgeInsets.symmetric(horizontal: 13),
          decoration: BoxDecoration(
            color: AppColors.campusBlue.withValues(alpha: 0.09),
            borderRadius: BorderRadius.circular(8),
          ),
          alignment: Alignment.center,
          child: const Text(
            '研究生',
            style: TextStyle(
              color: AppColors.campusBlue,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Container(
          height: 30,
          padding: const EdgeInsets.symmetric(horizontal: 13),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.line),
          ),
          alignment: Alignment.center,
          child: const Text(
            '本科生 · 后续支持',
            style: TextStyle(
              color: AppColors.faint,
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
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
      style: const TextStyle(
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
        color: const Color(0xFFFFF2F0),
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: const Color(0xFFF3C6C0)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.info_outline_rounded,
            color: Color(0xFFB43A2E),
            size: 16,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: Color(0xFF8E2C22),
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
        gradient: const LinearGradient(
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
