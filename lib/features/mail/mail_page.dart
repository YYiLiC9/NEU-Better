import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/app_theme.dart';
import '../../core/auth/auth_session.dart';
import '../../core/auth/credential_store.dart';
import '../../core/network/mail_client.dart';
import 'mail_detail_page.dart';
import 'mail_format.dart';
import 'mail_web_view.dart';

/// 邮件（只读收件箱）。
///
/// 主路径 B1：用已保存的 CAS 会话换 Coremail sid，原生拉取收件箱列表与读信
/// 元数据；正文在详情页用 WebView 打开。初始化失败时自动切 A：用 WebView
/// 打开官方邮箱（注入学校 Cookie）兜底。
class MailPage extends ConsumerStatefulWidget {
  const MailPage({super.key, required this.session});

  final AuthSession session;

  @override
  ConsumerState<MailPage> createState() => _MailPageState();
}

class _MailPageState extends ConsumerState<MailPage> {
  static const _ssoUrl =
      'https://mails.neu.edu.cn/coremail/cmcu_addon/dbdxsso.jsp';

  MailClient? _client;
  List<MailSummary> _items = const [];
  bool _loading = true;
  String? _error;
  bool _webFallback = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<MailClient> _createClient() async {
    try {
      return await MailClient.fromSession(widget.session);
    } catch (error) {
      // 会话换票失败时，若本地保存了密码则用密码再走一次 CAS。
      final credentials = await ref.read(credentialStoreProvider).read();
      final password = credentials?.password;
      if (credentials != null &&
          password != null &&
          password.isNotEmpty) {
        return MailClient.fromCredentials(
          username: credentials.username,
          password: password,
        );
      }
      rethrow;
    }
  }

  Future<void> _load({bool refresh = false}) async {
    if (refresh) {
      setState(() => _error = null);
    } else {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final client = _client ?? await _createClient();
      final items = await client.list();
      if (!mounted) return;
      setState(() {
        _client = client;
        _items = items;
        _loading = false;
        _error = null;
        _webFallback = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = _describe(error);
        if (_client == null && widget.session.hasCookies) {
          _webFallback = true;
        }
        if (error is MailSessionExpired) _webFallback = true;
      });
    }
  }

  String _describe(Object error) {
    if (error is MailSessionExpired) return '邮箱登录状态已过期，请重试或使用网页版';
    if (error is MailException) return error.toString();
    return '邮件加载失败：$error';
  }

  void _openDetail(MailSummary summary) {
    final client = _client;
    if (client == null) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => MailDetailPage(
          client: client,
          summary: summary,
          session: widget.session,
        ),
      ),
    );
  }

  void _useWebFallback() {
    setState(() => _webFallback = true);
  }

  void _retryNative() {
    setState(() => _webFallback = false);
    unawaited(_load());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        foregroundColor: AppColors.ink,
        titleSpacing: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('邮件', style: TextStyle(fontSize: 16)),
            Text(
              widget.session.accountLabel,
              style: TextStyle(fontSize: 10.5, color: AppColors.muted),
            ),
          ],
        ),
        actions: [
          if (!_webFallback)
            IconButton(
              tooltip: '刷新收件箱',
              onPressed: _loading ? null : () => _load(refresh: true),
              icon: const Icon(Icons.refresh_rounded, size: 20),
            ),
          IconButton(
            tooltip: _webFallback ? '重试原生收件箱' : '使用网页版',
            onPressed: _webFallback ? _retryNative : _useWebFallback,
            icon: Icon(
              _webFallback
                  ? Icons.inbox_rounded
                  : Icons.open_in_browser_rounded,
              size: 20,
            ),
          ),
        ],
      ),
      body: _webFallback ? _buildWebFallback() : _buildNative(),
    );
  }

  Widget _buildNative() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _items.isEmpty) {
      return _buildErrorState();
    }
    return RefreshIndicator(
      onRefresh: () => _load(refresh: true),
      child: _items.isEmpty
          ? ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                SizedBox(
                  height: 320,
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.inbox_outlined,
                            size: 40, color: AppColors.faint),
                        const SizedBox(height: 10),
                        Text('收件箱暂无邮件',
                            style: TextStyle(
                                fontSize: 12.5, color: AppColors.muted)),
                      ],
                    ),
                  ),
                ),
              ],
            )
          : ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 20),
              itemCount: _items.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final item = _items[index];
                return _MailListItem(
                  item: item,
                  onTap: () => _openDetail(item),
                );
              },
            ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off_rounded, size: 40, color: AppColors.muted),
            const SizedBox(height: 12),
            Text(
              _error ?? '邮件加载失败',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12.5, color: AppColors.muted),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                OutlinedButton(
                  onPressed: () => _load(),
                  child: const Text('重试'),
                ),
                const SizedBox(width: 12),
                FilledButton(
                  onPressed: _useWebFallback,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.campusBlue,
                  ),
                  child: const Text('使用网页版'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWebFallback() {
    final client = _client;
    final url = client?.inboxWebUrl ?? _ssoUrl;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          color: AppColors.campusBlue.withValues(alpha: 0.08),
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
          child: Row(
            children: [
              Icon(Icons.info_outline_rounded,
                  size: 15, color: AppColors.campusBlue),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '原生收件箱暂不可用，已切换到网页版邮箱',
                  style: TextStyle(fontSize: 11.5, color: AppColors.ink),
                ),
              ),
              TextButton(
                onPressed: _retryNative,
                child: const Text('重试原生', style: TextStyle(fontSize: 11.5)),
              ),
            ],
          ),
        ),
        Expanded(
          child: MailWebView(
            session: widget.session,
            initialUrl: url,
            cookieHeader: client?.session.cookieHeader,
          ),
        ),
      ],
    );
  }
}

class _MailListItem extends StatelessWidget {
  const _MailListItem({required this.item, required this.onTap});

  final MailSummary item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final unread = !item.read;
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 12, 14, 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.line),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                margin: const EdgeInsets.only(top: 6, right: 10),
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: unread ? AppColors.campusBlue : Colors.transparent,
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.subject.isEmpty ? '(无主题)' : item.subject,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13.5,
                        height: 1.3,
                        fontWeight:
                            unread ? FontWeight.w700 : FontWeight.w500,
                        color: AppColors.ink,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      item.from.isEmpty ? '未知发件人' : item.from,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 11.5, color: AppColors.muted),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    formatMailDate(item.receivedDate),
                    style: TextStyle(fontSize: 10.5, color: AppColors.faint),
                  ),
                  if (item.hasAttachment) ...[
                    const SizedBox(height: 6),
                    Icon(Icons.attach_file_rounded,
                        size: 13, color: AppColors.muted),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
