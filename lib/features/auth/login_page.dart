import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/app_theme.dart';
import '../../core/auth/credential_store.dart';
import '../../core/auth/webview_login_result.dart';
import 'auth_controller.dart';
import 'webview_login_page.dart';

part 'widgets/login_widgets.dart';

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
  String? _savedDisplayName;

  @override
  void initState() {
    super.initState();
    unawaited(_restoreCredentials());
  }

  Future<void> _restoreCredentials() async {
    final saved = await ref.read(credentialStoreProvider).read();
    if (!mounted || saved == null) return;
    _savedDisplayName = saved.displayName;
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
          keepSignedIn: _rememberMe,
          initialDisplayName: _savedDisplayName,
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
          keepSignedIn: _rememberMe,
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
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              AppColors.canvas,
              AppColors.isDark
                  ? const Color(0xFF13202F)
                  : const Color(0xFFE9F1FA),
            ],
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
                    Padding(
                      padding: const EdgeInsets.only(bottom: 22),
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
        color: AppColors.surface.withValues(
          alpha: AppColors.isDark ? 0.98 : 0.96,
        ),
        borderRadius: BorderRadius.circular(compact ? 22 : 24),
        border: Border.all(
          color: AppColors.isDark ? AppColors.line : Colors.white,
        ),
        boxShadow: AppColors.isDark
            ? null
            : const [
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
              '使用学校统一身份认证账号登录。',
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
                Text(
                  '保持登录',
                  style: TextStyle(color: AppColors.muted, fontSize: 12),
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
                Text(
                  '保存账号密码',
                  style: TextStyle(color: AppColors.muted, fontSize: 12),
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
                    ? SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.2,
                          color: Theme.of(context).colorScheme.onPrimary,
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
          ],
        ),
      ),
    );
  }
}
