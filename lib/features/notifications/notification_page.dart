import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/app_theme.dart';
import '../../app/widgets/secondary_page_header.dart';
import '../../app/widgets/secondary_page_title.dart';
import '../../app/widgets/shared_axis_switcher.dart';
import '../../core/auth/auth_session.dart';
import '../../core/network/notification_client.dart';
import 'notification_cache.dart';
import 'notification_detail_page.dart';
import 'notification_models.dart';
import 'notification_store.dart';

/// 通知列表页（校园消息中心，只读）。
class NotificationPage extends ConsumerStatefulWidget {
  const NotificationPage({
    super.key,
    required this.session,
    this.client,
    this.localState,
    this.isCurrent,
    this.onBack,
  });

  final AuthSession session;
  final NotificationClient? client;
  final Future<NotificationStore>? localState;
  final bool Function()? isCurrent;

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
  bool _refreshing = false;

  bool get _active => mounted && widget.isCurrent?.call() != false;
  String? _error;
  int _page = 1;
  int _total = 0;
  int _noRead = 0;
  AppNotification? _detail;
  NotificationStore? _localStore;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    final cached = NotificationCache.instance.dataFor(widget.session.studentId);
    if (cached != null) _useSnapshot(cached);
    unawaited(_initCached());
  }

  /// 先用本地缓存秒开列表，再静默后台刷新。
  Future<void> _initCached() async {
    final state = widget.localState ?? _loadLocalState();
    final cached = await NotificationCache.instance.loadFor(
      widget.session.studentId,
    );
    if (!_active) return;
    if (cached != null) setState(() => _useSnapshot(cached));
    final store = await state;
    if (!_active) return;
    setState(() => _localStore = store);
    await _load(refresh: true, silent: true);
  }

  void _useSnapshot(NotificationCacheData data) {
    _items
      ..clear()
      ..addAll(data.items);
    _total = data.total;
    _noRead = data.noRead;
    _loading = data.items.isEmpty;
  }

  Future<NotificationStore> _loadLocalState() async {
    final store = NotificationStore(studentId: widget.session.studentId);
    await store.load();
    return store;
  }

  @override
  void dispose() {
    if (widget.client == null) _client.close();
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

  Future<void> _load({bool refresh = false, bool silent = false}) async {
    if (!_active || _refreshing) return;
    _refreshing = true;
    if (refresh) {
      setState(() {
        // 有缓存时秒开：刷新不清空列表，也不无条件盖全屏 loading。
        if (!silent && _items.isEmpty) _loading = true;
        _error = null;
        _page = 1;
      });
    }
    try {
      final counts = await _client.counts().timeout(
        const Duration(seconds: 15),
      );
      final items = await _client
          .list(page: 1)
          .timeout(const Duration(seconds: 15));
      if (!_active) return;
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
      unawaited(_persistCache());
      // 进入列表时尽力把当前页未读标记为已读（失败不阻塞）。
      final unreadIds = [
        for (final item in items)
          if (!item.read) item.logId,
      ];
      if (unreadIds.isNotEmpty) {
        final ok = await _client.markRead(unreadIds);
        if (ok && _active) {
          await _localStore?.markLocallyRead(unreadIds);
          if (!_active) return;
          setState(() => _noRead = 0);
          unawaited(_persistCache());
        }
      }
    } catch (error) {
      if (!_active) return;
      final hasCache = _items.isNotEmpty;
      setState(() {
        _loading = false;
        // 有缓存时保留旧列表，不显示全屏错误。
        if (!hasCache) {
          _error = error is NotificationQueryException
              ? error.message
              : '$error';
        }
      });
      if (!silent && hasCache) _showRefreshFailure();
    } finally {
      _refreshing = false;
    }
  }

  /// 把当前列表写回本地缓存（供下次秒开）。
  Future<void> _persistCache() {
    return NotificationCache.instance.save(
      widget.session.studentId,
      [
        for (final item in _items)
          applyLocalNotificationRead(item, _localStore),
      ],
      _total,
      _noRead,
    );
  }

  void _showRefreshFailure() {
    if (!_active) return;
    ScaffoldMessenger.maybeOf(context)
        ?.showSnackBar(const SnackBar(content: Text('刷新失败，已显示缓存内容')));
  }

  /// 展示层叠加本地已读：服务端标记失败但本地已读过的条目仍显示为已读。
  bool _isRead(AppNotification item) {
    return item.read ||
        (_localStore?.localReadIds.contains(item.logId) ?? false);
  }

  Future<void> _loadMore() async {
    if (!_active || _loadingMore || _loading || _refreshing) return;
    if (_items.length >= _total) return;
    setState(() => _loadingMore = true);
    try {
      final next = _page + 1;
      final items = await _client
          .list(page: next)
          .timeout(const Duration(seconds: 15));
      if (!_active) return;
      setState(() {
        if (items.isNotEmpty) {
          _items.addAll(items);
          _page = next;
        }
        _loadingMore = false;
      });
      if (items.isNotEmpty) unawaited(_persistCache());
    } catch (_) {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  Future<void> _open(AppNotification item) async {
    if (!_active) return;
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
      // 本地兜底已读 + 把已读状态写回缓存，避免重进被旧缓存覆盖。
      final store = _localStore;
      if (store != null) unawaited(store.markLocalRead(item.logId));
      unawaited(_persistCache());
    }
    if (widget.onBack != null) {
      setState(() => _detail = item);
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => NotificationDetailPage(item: item),
      ),
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
              const SecondaryPageTitle('通知'),
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
        SecondaryPageHeader(
          title: '通知',
          onBack: widget.onBack,
          actions: [
            if (_noRead > 0)
              Container(
                margin: const EdgeInsets.only(right: 4),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
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
            IconButton(
              tooltip: '刷新',
              icon: Icon(Icons.refresh_rounded, color: AppColors.muted),
              onPressed: () => _load(refresh: true),
            ),
          ],
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
          : KeyedSubtree(key: const ValueKey('notify-list'), child: listPage),
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
          Icon(
            Icons.notifications_none_rounded,
            size: 40,
            color: AppColors.faint,
          ),
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
        return _NotificationTile(
          item: _items[index],
          read: _isRead(_items[index]),
          onTap: () => _open(_items[index]),
        );
      },
    );
  }
}

class _NotificationTile extends StatelessWidget {
  const _NotificationTile({
    required this.item,
    required this.read,
    required this.onTap,
  });

  final AppNotification item;
  final bool read;
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
                    color: read ? Colors.transparent : AppColors.nowRed,
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
                        fontWeight: read ? FontWeight.w500 : FontWeight.w700,
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
              Icon(
                Icons.chevron_right_rounded,
                size: 18,
                color: AppColors.faint,
              ),
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
              style: TextStyle(
                color: AppColors.muted,
                fontSize: 12.5,
                height: 1.5,
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Center(
          child: OutlinedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded, size: 16),
            label: const Text('重试'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.campusBlue,
            ),
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
