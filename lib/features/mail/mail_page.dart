import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/app_theme.dart';
import '../../app/widgets/secondary_page_title.dart';
import '../../app/widgets/shared_axis_switcher.dart';
import '../../core/auth/auth_session.dart';
import '../../core/auth/credential_store.dart';
import '../../core/network/mail_client.dart';
import 'mail_detail_page.dart';
import 'mail_format.dart';

/// 邮件（只读收件箱，纯原生）。
///
/// 用已保存的 CAS 会话换 Coremail sid，原生拉取收件箱列表与读信元数据；
/// 正文在详情页原生渲染。初始化失败时只显示原生错误态 + 重试，不再使用
/// WebView / 网页版兜底。
class MailPage extends ConsumerStatefulWidget {
  const MailPage({super.key, required this.session, this.onBack});

  final AuthSession session;

  /// 非空表示以「首页二级页」方式内嵌显示（保留底部导航），点击返回调用它。
  final VoidCallback? onBack;

  @override
  ConsumerState<MailPage> createState() => _MailPageState();
}

class _MailPageState extends ConsumerState<MailPage> {
  MailClient? _client;
  List<MailSummary> _items = const [];
  bool _loading = true;
  String? _error;
  MailSummary? _detail;

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
      final items = await client.list().timeout(const Duration(seconds: 20));
      if (!mounted) return;
      setState(() {
        _client = client;
        _items = items;
        _loading = false;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = _describe(error);
      });
    }
  }

  String _describe(Object error) {
    if (error is MailSessionExpired) return '邮箱登录状态已过期，请重新登录后重试';
    if (error is MailException) return error.toString();
    return '邮件加载失败：$error';
  }

  void _openDetail(MailSummary summary) {
    final client = _client;
    if (client == null) return;
    if (!summary.read) {
      unawaited(_markRead(summary, client));
    }
    if (widget.onBack != null) {
      setState(() => _detail = summary);
      return;
    }
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

  /// 点开未读邮件：先本地置已读（列表/未读数立即更新），再尽力同步远程。
  /// 远程失败只记录日志，不阻塞进入详情。
  Future<void> _markRead(MailSummary summary, MailClient client) async {
    if (!mounted) return;
    setState(() {
      _items = [
        for (final item in _items)
          if (item.id == summary.id)
            MailSummary(
              id: item.id,
              subject: item.subject,
              from: item.from,
              to: item.to,
              receivedDate: item.receivedDate,
              read: true,
              hasAttachment: item.hasAttachment,
            )
          else
            item,
      ];
    });
    try {
      await client.markRead(summary.id);
    } catch (error) {
      debugPrint('邮件远程标记已读失败（本地已置已读）：$error');
    }
  }

  @override
  Widget build(BuildContext context) {
    final embedded = widget.onBack != null;
    final body = _buildNative();
    if (!embedded) {
      if (_detail != null && _client != null) {
        return MailDetailPage(
          client: _client!,
          summary: _detail!,
          session: widget.session,
          onBack: () => setState(() => _detail = null),
        );
      }
      return Scaffold(
        backgroundColor: AppColors.canvas,
        appBar: AppBar(
          backgroundColor: AppColors.surface,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          foregroundColor: AppColors.ink,
          title: const SecondaryPageTitle('邮件'),
          actions: [
            IconButton(
              tooltip: '刷新收件箱',
              onPressed: _loading ? null : () => _load(refresh: true),
              icon: const Icon(Icons.refresh_rounded, size: 20),
            ),
          ],
        ),
        body: body,
      );
    }
    final listPage = Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 12, 8),
          child: Row(
            children: [
              IconButton(
                tooltip: '返回',
                onPressed: widget.onBack,
                icon: const Icon(Icons.arrow_back_rounded, size: 20),
              ),
              const SecondaryPageTitle('邮件'),
              const Spacer(),
              IconButton(
                tooltip: '刷新收件箱',
                onPressed: _loading ? null : () => _load(refresh: true),
                icon: const Icon(Icons.refresh_rounded, size: 20),
              ),
            ],
          ),
        ),
        Divider(height: 1, color: AppColors.line),
        Expanded(child: body),
      ],
    );
    final detailPage = (_detail != null && _client != null)
        ? MailDetailPage(
            client: _client!,
            summary: _detail!,
            session: widget.session,
            onBack: () => setState(() => _detail = null),
          )
        : null;
    return SharedAxisSwitcher(
      forward: detailPage != null,
      child: detailPage != null
          ? KeyedSubtree(
              key: ValueKey('mail-detail-${_detail!.id}'),
              child: detailPage,
            )
          : KeyedSubtree(key: const ValueKey('mail-list'), child: listPage),
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
            OutlinedButton(
              onPressed: () => _load(),
              child: const Text('重试'),
            ),
          ],
        ),
      ),
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
