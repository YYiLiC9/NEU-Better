import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/app_theme.dart';
import '../../app/widgets/shared_axis_switcher.dart';
import '../../core/auth/auth_session.dart';
import '../../core/network/notification_client.dart';
import 'notification_detail_page.dart';
import 'notification_models.dart';

/// 通知列表页（校园消息中心，只读）。
class NotificationPage extends ConsumerStatefulWidget {
  const NotificationPage({
    super.key,
    required this.session,
    this.client,
    this.onBack,
  });

  final AuthSession session;
  final NotificationClient? client;

  /// 非空表示以「首页二级页」方式内嵌显示（保留底部导航），点击返回调用它。
  final VoidCallback? onBack;

  @override
  ConsumerState<NotificationPage> createState() => _NotificationPageState();
}

class _NotificationPageState extends ConsumerState<NotificationPage> {
  late final NotificationClient _client =
      widget.client ?? NotificationClient.fromSession(widget.session);
  final ScrollController _scroll = ScrollController();

  final List<AppNotification> _items = <AppNotification>[];
  bool _loading = true;
  bool _loadingMore = false;
  String? _error;
  int _page = 1;
  int _total = 0;
  int _noRead = 0;
  AppNotification? _detail;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    _load(refresh: true);
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    final position = _scroll.position;
    if (position.pixels >= position.maxScrollExtent - 160) {
      _loadMore();
    }
  }

  Future<void> _load({bool refresh = false}) async {
    if (refresh) {
      setState(() {
        _loading = true;
        _error = null;
        _page = 1;
      });
    }
    try {
      final counts = await _client.counts();
      final items = await _client.list(page: 1);
      if (!mounted) return;
      setState(() {
        _items
          ..clear()
          ..addAll(items);
        _total = counts.total;
        _noRead = counts.noRead;
        _page = 1;
        _loading = false;
        _error = null;
      });
      // 进入列表时尽力把当前页未读标记为已读（失败不阻塞）。
      final unreadIds = [
        for (final item in items)
          if (!item.read) item.logId,
      ];
      if (unreadIds.isNotEmpty) {
        final ok = await _client.markRead(unreadIds);
        if (ok && mounted) {
          setState(() => _noRead = 0);
        }
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error is NotificationQueryException ? error.message : '$error';
      });
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || _loading) return;
    if (_items.length >= _total) return;
    setState(() => _loadingMore = true);
    try {
      final next = _page + 1;
      final items = await _client.list(page: next);
      if (!mounted) return;
      setState(() {
        if (items.isNotEmpty) {
          _items.addAll(items);
          _page = next;
        }
        _loadingMore = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  Future<void> _open(AppNotification item) async {
    final index = _items.indexWhere((e) => e.logId == item.logId);
    if (index >= 0 && !_items[index].read && mounted) {
      setState(() {
        _items[index] = AppNotification(
          logId: item.logId,
          read: true,
          time: item.time,
          title: item.title,
          content: item.content,
          sourceName: item.sourceName,
          url: item.url,
          typeName: item.typeName,
        );
        if (_noRead > 0) _noRead--;
      });
      unawaited(_client.markRead([item.logId]));
    }
    if (widget.onBack != null) {
      setState(() => _detail = item);
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => NotificationDetailPage(item: item)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final embedded = widget.onBack != null;
    final body = RefreshIndicator(
      onRefresh: () => _load(refresh: true),
      color: AppColors.campusBlue,
      child: _buildBody(),
    );
    if (!embedded) {
      if (_detail != null) {
        return NotificationDetailPage(
          item: _detail!,
          onBack: () => setState(() => _detail = null),
        );
      }
      return Scaffold(
        backgroundColor: AppColors.canvas,
        appBar: AppBar(
          backgroundColor: AppColors.canvas,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          title: Row(
            children: [
              Text(
                '通知',
                style: TextStyle(
                  color: AppColors.ink,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (_noRead > 0) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.campusBlue.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '未读 $_noRead',
                    style: TextStyle(
                      color: AppColors.campusBlue,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ],
          ),
          actions: [
            IconButton(
              tooltip: '刷新',
              icon: Icon(Icons.refresh_rounded, color: AppColors.muted),
              onPressed: () => _load(refresh: true),
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
              Text(
                '通知',
                style: TextStyle(
                  color: AppColors.ink,
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (_noRead > 0) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.campusBlue.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '未读 $_noRead',
                    style: TextStyle(
                      color: AppColors.campusBlue,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
              const Spacer(),
              IconButton(
                tooltip: '刷新',
                icon: Icon(Icons.refresh_rounded, color: AppColors.muted),
                onPressed: () => _load(refresh: true),
              ),
            ],
          ),
        ),
        Divider(height: 1, color: AppColors.line),
        Expanded(child: body),
      ],
    );
    final detailPage = _detail != null
        ? NotificationDetailPage(
            item: _detail!,
            onBack: () => setState(() => _detail = null),
          )
        : null;
    return SharedAxisSwitcher(
      forward: detailPage != null,
      child: detailPage != null
          ? KeyedSubtree(
              key: ValueKey('notify-detail-${_detail!.logId}'),
              child: detailPage,
            )
          : KeyedSubtree(
              key: const ValueKey('notify-list'),
              child: listPage,
            ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return Center(
        child: CircularProgressIndicator(
          strokeWidth: 2.4,
          color: AppColors.campusBlue,
        ),
      );
    }
    if (_error != null) {
      return _ErrorState(message: _error!, onRetry: () => _load(refresh: true));
    }
    if (_items.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          SizedBox(height: 120),
          Icon(Icons.notifications_none_rounded, size: 40, color: AppColors.faint),
          const SizedBox(height: 10),
          Center(
            child: Text(
              '暂无通知',
              style: TextStyle(color: AppColors.muted, fontSize: 13),
            ),
          ),
        ],
      );
    }
    return ListView.separated(
      controller: _scroll,
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      itemCount: _items.length + (_loadingMore ? 1 : 0),
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        if (index >= _items.length) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Center(
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          );
        }
        return _NotificationTile(item: _items[index], onTap: () => _open(_items[index]));
      },
    );
  }
}

class _NotificationTile extends StatelessWidget {
  const _NotificationTile({required this.item, required this.onTap});

  final AppNotification item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.line),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 6, right: 10),
                child: Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: item.read ? Colors.transparent : AppColors.nowRed,
                  ),
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title.isEmpty ? '（无标题）' : item.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13.5,
                        height: 1.35,
                        fontWeight: item.read ? FontWeight.w500 : FontWeight.w700,
                        color: AppColors.ink,
                      ),
                    ),
                    if (item.preview.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        item.preview,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          height: 1.4,
                          color: AppColors.muted,
                        ),
                      ),
                    ],
                    const SizedBox(height: 6),
                    Text(
                      [
                        if (item.sourceName.isNotEmpty) item.sourceName,
                        if (item.time != null) _formatTime(item.time!),
                      ].join(' · '),
                      style: TextStyle(fontSize: 10.5, color: AppColors.faint),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(Icons.chevron_right_rounded, size: 18, color: AppColors.faint),
            ],
          ),
        ),
      ),
    );
  }

  static String _formatTime(DateTime time) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${time.year}-${two(time.month)}-${two(time.day)} '
        '${two(time.hour)}:${two(time.minute)}';
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        const SizedBox(height: 110),
        Icon(Icons.cloud_off_rounded, size: 40, color: AppColors.faint),
        const SizedBox(height: 10),
        Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.muted, fontSize: 12.5, height: 1.5),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Center(
          child: OutlinedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded, size: 16),
            label: const Text('重试'),
            style: OutlinedButton.styleFrom(foregroundColor: AppColors.campusBlue),
          ),
        ),
      ],
    );
  }
}

void unawaited(Future<void> future) {
  future.catchError((Object error) {
    debugPrint('[notify] background task failed: $error');
  });
}
