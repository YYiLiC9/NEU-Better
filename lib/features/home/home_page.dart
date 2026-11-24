import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../../app/theme/app_theme.dart';
import '../../app/widgets/secondary_page_header.dart';
import '../../app/widgets/secondary_page_title.dart';
import '../../app/widgets/shared_axis_switcher.dart';
import '../../core/app_labels.dart';
import '../../core/plugins/plugin_icon_resolver.dart';
import '../../core/auth/auth_session.dart';
import '../../core/auth/credential_store.dart';
import '../../core/platform/windows_window.dart';
import '../../core/settings/app_settings.dart';
import '../../core/storage/account_scope.dart';
import '../auth/auth_controller.dart';
import '../dorm/dorm_page.dart';
import '../dorm/electricity_alert.dart';
import '../../core/electricity/electricity_models.dart';
import '../../core/network/mail_client.dart';
import '../../core/plugins/campus_network_plugin.dart';
import '../../core/network/neu_service_session.dart';
import '../../core/plugins/plugin_models.dart';
import '../../core/plugins/plugin_placement_store.dart';
import '../../core/plugins/plugin_service.dart';
import '../dorm/electricity_service.dart';
import '../ecode/ecode_feed.dart';
import '../ecode/ecode_page.dart';
import '../../core/network/notification_client.dart';
import '../mail/mail_format.dart';
import '../mail/mail_feed.dart';
import '../mail/mail_cache.dart';
import '../mail/mail_page.dart';
import '../mail/mail_poll_state.dart';
import '../mail/mail_poller.dart';
import '../plugins/campus_network_page.dart';
import '../notifications/notification_cache.dart';
import '../notifications/notification_models.dart';
import '../notifications/notification_dispatch.dart';
import '../notifications/notification_page.dart';
import '../notifications/notification_poller.dart';
import '../notifications/notification_store.dart';
import '../../core/models/news_models.dart';
import '../../core/network/news_client.dart';
import '../news/news_page.dart';
import '../news/news_store.dart';
import '../plugins/plugin_runtime_page.dart';
import '../settings/settings_page.dart';
import '../timetable/timetable_page.dart';
import '../timetable/timetable_store.dart';
import '../timetable/timetable_sync.dart';
import '../timetable/timetable_widget_service.dart';
import '../timetable/timetable_schedule.dart';
import 'home_card_catalog.dart';
import 'home_card_layout.dart';
import 'home_layout_store.dart';
import 'widgets/campus_network_card.dart';
import 'widgets/news_card.dart';
import 'widgets/plugin_card.dart';

part 'widgets/home_card_gallery.dart';
part 'widgets/home_chrome.dart';
part 'widgets/home_grid.dart';

/// 当前选中一级页（0 = 首页, 1 = 课表, 2 = e码通, 3 = 设置）。
/// 放在 ProviderScope 层：主题切换会重挂载根子树，重建后仍停留原页面。
final homeTabProvider = StateProvider<int>((ref) => 0);
final homePluginServiceProvider = Provider<PluginService>(
  (ref) => PluginService(),
);

enum _HomeSection {
  overview,
  dorm,
  gallery,
  mail,
  notifications,
  network,
  news,
  library,
}

/// 主题切换重建时保留首页二级页，以及图书馆的插件清单。
final _homeDestinationProvider =
    StateProvider<({_HomeSection section, PluginManifest? plugin})>(
      (ref) => (section: _HomeSection.overview, plugin: null),
    );

class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key, required this.session});

  final AuthSession session;

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  final _elecService = DormElectricityService();
  final _homeLayoutStore = const HomeLayoutStore();
  late final _pluginService = ref.read(homePluginServiceProvider);

  /// 已安装的远程插件（完整清单）与已安装版本登记。
  List<PluginManifest> _installedPlugins = const <PluginManifest>[];
  Map<String, String> _installedPluginVersions = const <String, String>{};

  /// 远程插件目录（卡片库「可选插件」列表）。
  List<PluginManifest> _catalogPlugins = const <PluginManifest>[];
  bool _catalogLoading = false;
  bool _catalogLoaded = false;
  String? _catalogError;

  /// 下载/安装进度（0..1）与失败标记，key 为插件 id。
  final Map<String, double> _downloadProgress = <String, double>{};
  final Set<String> _downloadFailed = <String>{};

  /// 0 = 首页, 1 = 课表, 2 = e码通, 3 = 设置。
  int get _tab => ref.watch(homeTabProvider);

  /// 首页卡片布局（顺序 + 尺寸），按账号持久化。
  List<HomeCardLayout> _homeCards = defaultHomeCards();
  bool _layoutLoaded = false;

  /// 插件外观（首页 / 侧栏，可同时）与侧栏顺序，按账号持久化。
  final _placementStore = PluginPlacementStore();
  Map<String, PluginAppearance> _appearances =
      const <String, PluginAppearance>{};
  List<String> _sidebarPluginIds = const <String>[];
  bool _sidebarDragging = false;
  Timer? _sidebarHintTimer;

  List<String> get _visibleSidebarIds => <String>[
    for (final id in _sidebarPluginIds)
      if (_sidebarMeta(id) != null) id,
  ];

  /// 侧栏当前打开的插件内容（null = 显示一级 IndexedStack）。
  String? _displayedPluginId;

  /// 是否允许「添加到侧栏」（仅 Windows 桌面）。
  bool get _allowSidebar =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;

  /// 安卓「设计模式」：长按进入后可拖动/删除/改尺寸；桌面无此状态。
  bool _designMode = false;

  /// 桌面卡片固定像素单元尺寸（不随窗口缩放）。
  static const double _desktopHomeUnit = 88;

  DormPrefs? _statusPrefs;

  /// 首页「邮件」卡片展示用（best-effort 拉取，失败不影响首页）。
  int _mailUnread = 0;
  List<MailSummary> _mailRecent = const [];

  /// 首页「通知」卡片展示用（best-effort 拉取，失败不影响首页）。
  int _notifyUnread = 0;
  List<AppNotification> _notifyRecent = const [];
  NotificationPoller? _notifyPoller;
  bool _notifyPollerStarted = false;
  bool _endingSession = false;
  late final _notifications = NotificationClient.fromSession(widget.session);
  late final _notificationState = _loadNotificationState();
  late final MailFeed _mailFeed;
  EcodeFeed? _ecodeFeed;

  bool _isSessionActive() {
    if (!mounted || _endingSession) return false;
    final current = ref.read(authControllerProvider);
    return current is AuthAuthenticated &&
        current.session.studentId == widget.session.studentId &&
        current.session.createdAt == widget.session.createdAt;
  }

  Future<NotificationStore> _loadNotificationState() async {
    final store = NotificationStore(studentId: widget.session.studentId);
    await store.load();
    return store;
  }

  /// 新邮件轮询（App 进程存活时每 3 分钟一次，不做后台/被杀推送）。
  MailPoller? _mailPoller;

  /// 首页「新闻」卡片展示用（best-effort 拉取，失败不影响首页）。
  int _newsUnread = 0;
  List<NewsItem> _newsLatest = const <NewsItem>[];

  final _visitedTabs = <int>{0};

  /// 一级标签「淡入淡出」转场（Material 3 Fade Through）：旧页淡出→换页→新页
  /// 淡入并轻微放大。用独立 _displayedTab 驱动 IndexedStack，保证子页状态不丢。
  late final AnimationController _tabFade;
  late int _displayedTab;
  int? _pendingTab;

  @override
  void initState() {
    super.initState();
    _tabFade = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 210),
      value: 1.0,
    );
    _displayedTab = ref.read(homeTabProvider);
    _visitedTabs.add(_displayedTab);
    // 所有用户数据（课表 / 修改 / 备注 / 寝室号）都按当前账号隔离存储。
    AccountScope.setAccount(widget.session.studentId);
    _mailFeed = MailFeed(
      widget.session,
      credentials: ref.read(credentialStoreProvider),
      isCurrent: _isSessionActive,
    );
    WidgetsBinding.instance.addObserver(this);
    // 预热邮件本地缓存：首页卡片与邮件页可先用上次结果秒开。
    final account = widget.session.studentId;
    unawaited(
      MailCache.instance.loadFor(account).then((items) {
        if (_isSessionActive()) _showMailSummary(items);
      }),
    );
    unawaited(ref.read(appSettingsProvider.notifier).reload());
    final layout = _bootstrapPlugins();
    // 监听「点击用电提醒通知 → 打开寝室用电页」：先装 MethodChannel 回调，
    // 再查询冷启动时原生是否已有待处理请求。
    NotificationRouter.ensureHandlerInstalled();
    NotificationRouter.openDormSignal.addListener(_handleOpenDorm);
    NotificationRouter.openTabSignal.addListener(_handleOpenTab);
    NotificationRouter.openMailSignal.addListener(_handleOpenMail);
    unawaited(NotificationRouter.consumePending());
    _loadStatus();
    dormPrefsChanged.addListener(_loadStatus);
    // 预热通知缓存：进入通知页时可同步命中内存缓存，冷启动也尽量首帧直出。
    unawaited(
      NotificationCache.instance.loadFor(account).then((snapshot) {
        if (_isSessionActive() && snapshot != null) {
          _showNotifySummary(snapshot.items, snapshot.noRead);
        }
      }),
    );
    final settings = ref.read(appSettingsProvider);
    unawaited(
      WindowsWindow.setCloseBehavior(
        minimizeToTaskbar: settings.minimizeOnClose && settings.showTrayIcon,
      ),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(_runDailyElectricityCheck());
      unawaited(_loadMailSummary());
      unawaited(_loadNotifySummary());
      unawaited(
        layout.then((_) {
          if (_isSessionActive() &&
              _homeCards.any((card) => card.id == 'news')) {
            return _loadNewsSummary();
          }
        }),
      );
      unawaited(_startNotificationPoller());
      unawaited(_syncNotificationBackground());
      _syncMailPoller();
      unawaited(_ensureTimetable());
      if (Platform.isAndroid &&
          !Platform.environment.containsKey('FLUTTER_TEST')) {
        final feed = _ecodeFeed ??= EcodeFeed(
          widget.session,
          credentials: ref.read(credentialStoreProvider),
        );
        unawaited(
          feed
              .fetch(preferCached: true)
              .then<void>((_) {}, onError: (Object _) {}),
        );
      }
      if (ref.read(_homeDestinationProvider).section == _HomeSection.gallery) {
        unawaited(_fetchCatalog());
      }
    });
  }

  /// 允许出现在首页的卡片 id：内置 + 已安装插件。
  Set<String> get _allowedCardIds => <String>{
    ...builtinHomeCardIds,
    for (final plugin in _installedPlugins) plugin.id,
  };

  Future<void> _bootstrapPlugins() async {
    final placements = _placementStore.load();
    try {
      final installed = await _pluginService.readInstalledManifests();
      if (!_isSessionActive()) return;
      _installedPlugins = installed;
      _installedPluginVersions = _pluginService.registry.installed;
      _syncPluginNotifySources(installed);
    } catch (error) {
      debugPrint('[plugins] load installed failed: $error');
    }
    final cards = await _homeLayoutStore.read(allowedIds: _allowedCardIds);
    await placements;
    if (!_isSessionActive()) return;
    await _applyPlacements(cards);
  }

  /// 读取插件外观，并与首页布局对齐：
  /// - 内置三项默认 home，远程已装默认 none（由 store 默认值给出）；
  /// - `home || sidebar` 保证首页有一张兜底卡；none 则移除卡片；
  /// - 侧栏成员 = sidebar==true 的插件，默认顺序为内置在前、远程按安装顺序。
  Future<void> _applyPlacements(List<HomeCardLayout> cards) async {
    final allowed = _allowedCardIds;
    final nextCards = <HomeCardLayout>[...cards];
    var layoutChanged = false;
    for (final id in <String>{
      ...homeCardCatalog.map((e) => e.id),
      ..._installedPlugins.map((e) => e.id),
    }) {
      if (!allowed.contains(id)) continue;
      final appearance = _placementStore.appearanceOf(id);
      final hasCard = nextCards.any((card) => card.id == id);
      if (appearance.none && hasCard) {
        nextCards.removeWhere((card) => card.id == id);
        layoutChanged = true;
      } else if (!appearance.none && !hasCard) {
        nextCards.add(HomeCardLayout(id: id, size: HomeCardSize.s1x1));
        layoutChanged = true;
      }
    }
    if (!mounted) return;
    setState(() {
      _homeCards = nextCards;
      _layoutLoaded = true;
      _appearances = Map<String, PluginAppearance>.from(
        _placementStore.appearances,
      );
      _sidebarPluginIds = _computeSidebarIds();
    });
    if (layoutChanged) await _saveHomeLayout();
  }

  /// 有效外观：优先本次会话缓存，缺省回落到 store 默认。
  PluginAppearance _appearanceOf(String id) =>
      _appearances[id] ?? _placementStore.appearanceOf(id);

  /// 计算侧栏插件顺序。
  /// 默认：内置固定 [dorm, notify, mail]，再远程按安装顺序；
  /// 用户拖动过后使用持久化的自定义顺序，新增项追加末尾。
  List<String> _computeSidebarIds() {
    final allowed = _allowedCardIds;
    final candidates = <String>[
      for (final id in <String>[
        ...kDefaultHomePluginIds,
        ..._installedPlugins.map((e) => e.id),
      ])
        if (allowed.contains(id) && _appearanceOf(id).sidebar) id,
    ];
    final unique = <String>[];
    for (final id in candidates) {
      if (!unique.contains(id)) unique.add(id);
    }
    if (!_placementStore.sidebarCustomOrder) return unique;
    final custom = <String>[
      for (final id in _placementStore.sidebarIds)
        if (unique.contains(id)) id,
    ];
    for (final id in unique) {
      if (!custom.contains(id)) custom.add(id);
    }
    return custom;
  }

  /// 让「设置 → 通知」里为每个已安装插件出现一个通知开关（默认关）。
  void _syncPluginNotifySources(Iterable<PluginManifest> plugins) {
    final controller = ref.read(appSettingsProvider.notifier);
    for (final plugin in plugins) {
      controller.ensureNotifySource('plugin:${plugin.id}');
    }
  }

  Future<void> _fetchCatalog({bool force = false}) async {
    if (!mounted || _catalogLoading || (_catalogLoaded && !force)) return;
    setState(() {
      _catalogLoading = true;
      _catalogError = null;
    });
    try {
      final catalog = await _pluginService.fetchCatalog(force: force);
      if (!mounted) return;
      setState(() {
        _catalogPlugins = catalog.plugins;
        _catalogLoaded = true;
        _catalogLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _catalogError = error.toString();
        _catalogLoading = false;
      });
    }
  }

  /// 下载/安装（或更新）远程插件。用分步进度反馈写入过程。
  Future<void> _downloadPlugin(PluginManifest manifest) async {
    if (!manifest.isEnabled) return;
    setState(() {
      _downloadProgress[manifest.id] = 0.05;
      _downloadFailed.remove(manifest.id);
    });
    try {
      await Future<void>.delayed(const Duration(milliseconds: 300));
      if (mounted) setState(() => _downloadProgress[manifest.id] = 0.4);
      await _pluginService.install(manifest);
      if (mounted) setState(() => _downloadProgress[manifest.id] = 0.9);
      await Future<void>.delayed(const Duration(milliseconds: 300));
      final installed = await _pluginService.readInstalledManifests();
      final versions = _pluginService.registry.installed;
      if (!mounted) return;
      setState(() {
        _downloadProgress.remove(manifest.id);
        _installedPlugins = installed;
        _installedPluginVersions = versions;
      });
      ref
          .read(appSettingsProvider.notifier)
          .ensureNotifySource('plugin:${manifest.id}');
      // Windows：下载完成默认「不添加」，由用户在插件库显式选择首页/侧栏。
      if (_allowSidebar) {
        await _placementStore.setAppearance(
          manifest.id,
          const PluginAppearance(),
        );
        if (!mounted) return;
        setState(() {
          _appearances = Map<String, PluginAppearance>.from(
            _placementStore.appearances,
          );
        });
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _downloadProgress.remove(manifest.id);
        _downloadFailed.add(manifest.id);
      });
      ScaffoldMessenger.maybeOf(context)
          ?.showSnackBar(SnackBar(content: Text('安装失败：$error')));
    }
  }

  /// 卸载插件：删插件文件 + registry 登记 + 首页卡片。
  Future<void> _uninstallPlugin(String id) async {
    try {
      await _pluginService.uninstall(id);
      final installed = await _pluginService.readInstalledManifests();
      final versions = _pluginService.registry.installed;
      if (!mounted) return;
      setState(() {
        _installedPlugins = installed;
        _installedPluginVersions = versions;
        _downloadProgress.remove(id);
        _downloadFailed.remove(id);
        _homeCards = <HomeCardLayout>[
          for (final card in _homeCards)
            if (card.id != id) card,
        ];
        _appearances = <String, PluginAppearance>{
          for (final entry in _appearances.entries)
            if (entry.key != id) entry.key: entry.value,
        };
        _sidebarPluginIds = <String>[
          for (final existing in _sidebarPluginIds)
            if (existing != id) existing,
        ];
        if (_displayedPluginId == id) _displayedPluginId = null;
      });
      await _placementStore.remove(id);
      ref.read(appSettingsProvider.notifier).removeNotifySource('plugin:$id');
      await _saveHomeLayout();
    } catch (error) {
      debugPrint('[plugins] uninstall failed: $error');
    }
  }

  void _openPlugin(PluginManifest manifest) {
    if (_visibleSidebarIds.contains(manifest.id)) {
      _openSidebarPlugin(manifest.id);
      return;
    }
    switch (manifest.id) {
      case campusNetworkPluginId:
        _showHomeSection(_HomeSection.network);
        return;
      case 'library':
        _showHomeSection(_HomeSection.library, plugin: manifest);
        return;
    }
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            PluginRuntimePage(manifest: manifest, session: widget.session),
      ),
    );
  }

  Future<void> _saveHomeLayout() async {
    await _homeLayoutStore.save(_homeCards);
  }

  void _enterDesign() {
    if (!_designMode) setState(() => _designMode = true);
  }

  void _exitDesign() {
    if (_designMode) setState(() => _designMode = false);
  }

  void _addCard(String id) {
    if (_homeCards.any((card) => card.id == id)) return;
    setState(() {
      _homeCards = <HomeCardLayout>[
        ..._homeCards,
        HomeCardLayout(id: id, size: HomeCardSize.s1x1),
      ];
    });
    unawaited(_saveHomeLayout());
  }

  void _deleteCard(String id) {
    if (!_homeCards.any((card) => card.id == id)) return;
    setState(() {
      _homeCards = <HomeCardLayout>[
        for (final card in _homeCards)
          if (card.id != id) card,
      ];
    });
    unawaited(_saveHomeLayout());
  }

  void _setSize(String id, HomeCardSize size) {
    setState(() {
      _homeCards = <HomeCardLayout>[
        for (final card in _homeCards)
          card.id == id ? card.copyWith(size: size) : card,
      ];
    });
    unawaited(_saveHomeLayout());
  }

  void _reorder(List<String> order) {
    final byId = <String, HomeCardLayout>{
      for (final card in _homeCards) card.id: card,
    };
    final next = <HomeCardLayout>[
      for (final id in order)
        if (byId[id] != null) byId[id]!,
    ];
    setState(() => _homeCards = next);
    unawaited(_saveHomeLayout());
  }

  /// 侧栏点击插件：把内容区切换为该插件（复用一级淡入过渡）。
  void _openSidebarPlugin(String id) {
    if (_displayedPluginId == id) return;
    setState(() => _displayedPluginId = id);
    _tabFade.value = 0.0;
    unawaited(
      _tabFade.animateTo(
        1.0,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
      ),
    );
  }

  /// 首页卡片点击：若该功能也在侧栏中，则从侧栏进入（侧栏同步高亮）；
  /// 否则走各自的内嵌二级页。
  void _openCardFeature(String id, VoidCallback fallback) {
    if (_visibleSidebarIds.contains(id)) {
      _openSidebarPlugin(id);
    } else {
      fallback();
    }
  }

  /// 从侧栏插件内容返回：回到首页根（并清除侧栏选中）。
  void _returnFromSidebarPlugin() => _goToTab(0);

  /// 侧栏内容区渲染：内置（余额/通知/邮件）与远程插件各自打开内嵌页。
  Widget _buildPluginContent(String id) {
    switch (id) {
      case 'dorm':
        return _HomeDormDetail(onBack: _returnFromSidebarPlugin);
      case 'notify':
        return NotificationPage(
          session: widget.session,
          client: _notifications,
          localState: _notificationState,
          isCurrent: _isSessionActive,
          onBack: _returnFromSidebarPlugin,
        );
      case 'mail':
        return MailPage(
          session: widget.session,
          feed: _mailFeed,
          onBack: _returnFromSidebarPlugin,
        );
      case campusNetworkPluginId:
        return CampusNetworkPage(
          onBack: _returnFromSidebarPlugin,
          visible: true,
        );
      case 'news':
        return NewsPage(onBack: _returnFromSidebarPlugin);
    }
    for (final plugin in _installedPlugins) {
      if (plugin.id == id) {
        return PluginRuntimePage(
          manifest: plugin,
          session: widget.session,
          onBack: _returnFromSidebarPlugin,
        );
      }
    }
    return const SizedBox.shrink();
  }

  void _startSidebarHint() {
    _sidebarHintTimer?.cancel();
    _sidebarHintTimer = Timer(const Duration(milliseconds: 260), () {
      if (mounted && !_sidebarDragging) {
        setState(() => _sidebarDragging = true);
      }
    });
  }

  void _cancelSidebarHint() {
    _sidebarHintTimer?.cancel();
    _sidebarHintTimer = null;
    if (mounted && _sidebarDragging) {
      setState(() => _sidebarDragging = false);
    }
  }

  /// 侧栏拖动排序：移动 id 后写入自定义顺序并持久化。
  /// 使用 [onReorderItem]（newIndex 已按移除后的列表调整）。
  void _reorderSidebarItems(int oldIndex, int newIndex) {
    final visible = _visibleSidebarIds;
    if (oldIndex < 0 || oldIndex >= visible.length) return;
    final moved = visible.removeAt(oldIndex);
    visible.insert(newIndex.clamp(0, visible.length), moved);
    final hidden = <String>[
      for (final id in _sidebarPluginIds)
        if (!visible.contains(id)) id,
    ];
    final next = <String>[...visible, ...hidden];
    setState(() {
      _sidebarPluginIds = next;
      _sidebarDragging = false;
    });
    unawaited(_placementStore.reorderSidebar(next));
  }

  /// 设置插件外观，并同步首页布局 / 侧栏 / 持久化。
  Future<void> _setPluginAppearance(
    String id,
    PluginAppearance appearance,
  ) async {
    await _placementStore.setAppearance(id, appearance);
    var cards = <HomeCardLayout>[..._homeCards];
    if (appearance.none) {
      cards = <HomeCardLayout>[
        for (final card in cards)
          if (card.id != id) card,
      ];
    } else if (!cards.any((card) => card.id == id)) {
      cards.add(HomeCardLayout(id: id, size: HomeCardSize.s1x1));
    }
    if (!mounted) return;
    setState(() {
      _homeCards = cards;
      _appearances = Map<String, PluginAppearance>.from(
        _placementStore.appearances,
      );
      _sidebarPluginIds = _computeSidebarIds();
      if (appearance.none && _displayedPluginId == id) {
        _displayedPluginId = null;
      }
    });
    await _saveHomeLayout();
  }

  Future<void> _ensureTimetable() async {
    // 测试环境不联网同步（无校园网、且会悬挂网络等待）。
    try {
      final account = widget.session.studentId;
      if (!_isSessionActive()) return;
      final owner = AccountScope.scopedName('timetable', account: account);
      final previousOwner = ref.read(timetableAccountProvider);
      if (previousOwner != owner) {
        ref.read(timetableOverlayProvider.notifier).state = null;
        ref.read(timetableAccountProvider.notifier).state = owner;
        if (previousOwner != null) {
          ref.read(timetableDataProvider.notifier).state = null;
        }
      }
      final snapshot = ref.read(timetableDataProvider);
      final cached =
          snapshot ?? await const TimetableStore().read(account: account);
      if (!_isSessionActive()) return;
      if (cached != null && ref.read(timetableDataProvider) == null) {
        ref.read(timetableDataProvider.notifier).state = cached;
        unawaited(
          TimetableWidgetService.syncOfficial(cached, account: account),
        );
      }
      if (Platform.environment.containsKey('FLUTTER_TEST')) return;
      final cacheEmpty = cached == null || cached.sessions.isEmpty;
      final sinceLogin = DateTime.now().difference(widget.session.createdAt);
      final justLoggedIn =
          !sinceLogin.isNegative && sinceLogin < const Duration(minutes: 3);
      if (cacheEmpty || justLoggedIn) {
        await _autoSyncTimetable();
      }
    } catch (error) {
      debugPrint('[timetable] ensure failed: $error');
    }
  }

  Future<void> _autoSyncTimetable() async {
    final data = await TimetableSyncService.syncWithSession(widget.session);
    if (data != null && _isSessionActive()) {
      // 同步到的最新课表（含考试）写入共享 Provider，主题切换重挂载时可直接恢复。
      ref.read(timetableDataProvider.notifier).state = data;
      debugPrint('[timetable] auto synced ${data.sessions.length} sessions');
    }
  }

  @override
  void dispose() {
    NotificationRouter.openDormSignal.removeListener(_handleOpenDorm);
    NotificationRouter.openTabSignal.removeListener(_handleOpenTab);
    NotificationRouter.openMailSignal.removeListener(_handleOpenMail);
    WidgetsBinding.instance.removeObserver(this);
    dormPrefsChanged.removeListener(_loadStatus);
    _notifyPoller?.stop();
    _mailPoller?.stop();
    _mailFeed.dispose();
    _notifications.close();
    _ecodeFeed?.dispose();
    _sidebarHintTimer?.cancel();
    _tabFade.dispose();
    super.dispose();
  }

  /// 应用回到前台时补一次邮件检查（≥30s 节流，避免频繁切页重复拉取）。
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state != AppLifecycleState.resumed) return;
    final poller = _mailPoller;
    if (poller == null) return;
    final last = poller.state.lastCheckAt;
    if (last != null &&
        DateTime.now().difference(last) < const Duration(seconds: 30)) {
      return;
    }
    unawaited(poller.checkOnce());
    unawaited(_loadMailSummary());
  }

  /// 收到桌面小部件点击请求：切到「课表」一级页。
  void _handleOpenTab() {
    if (!mounted) return;
    final tab = NotificationRouter.requestedTab;
    debugPrint('[notify] openTab -> $tab');
    _selectTab(tab);
  }

  /// 收到通知点击请求：切到「首页 · 寝室用电」二级页。
  void _handleOpenDorm() {
    if (!mounted) return;
    debugPrint('[notify] openDorm -> home dorm detail');
    _openDormDetail();
  }

  /// 收到新邮件通知点击请求：切到「首页 · 邮件」二级页。
  void _handleOpenMail() {
    if (!mounted) return;
    NotificationRouter.requestedOpenMail = false;
    debugPrint('[notify] openMail -> home mail section');
    _openMail();
  }

  /// 打开邮件二级页（保留底部导航，不破坏内嵌 onBack 与详情逻辑）。
  void _openMail() {
    _goToTab(0, keepHomeSection: true);
    _showHomeSection(_HomeSection.mail);
  }

  Future<void> _loadStatus() async {
    final prefs = await _elecService.loadPrefs();
    if (!mounted) return;
    setState(() => _statusPrefs = prefs);
    final reading = prefs.lastReading;
    unawaited(
      WindowsWindow.setTrayTooltip(
        reading == null ? 'NEU Better' : '寝室用电 ${reading.rawRemain}',
      ),
    );
  }

  /// 每日一次：打开软件时若今天还没查过电量就查一次；
  /// 结果低于提醒线时弹窗 + Windows 通知。
  Future<void> _runDailyElectricityCheck() async {
    final reading = await _elecService.dailyCheck(session: widget.session);
    if (!mounted || reading == null) return;
    final prefs = await _elecService.loadPrefs();
    if (!DormElectricityService.isLow(reading, prefs.alertThreshold)) return;
    if (!mounted) return;
    // 设置 → 通知：用电提醒总开关（关闭后不再弹系统/应用内提醒）。
    if (!ref.read(appSettingsProvider.notifier).notifyEnabled('dorm')) return;
    await DormAlertPresenter.present(
      context,
      reading: reading,
      prefs: prefs,
      onView: _openDormDetail,
    );
  }

  final GlobalKey _dormCardKey = GlobalKey();

  void _showHomeSection(_HomeSection section, {PluginManifest? plugin}) {
    if (section == _HomeSection.gallery) unawaited(_fetchCatalog());
    ref.read(_homeDestinationProvider.notifier).state = (
      section: section,
      plugin: plugin,
    );
  }

  void _returnHome() => _showHomeSection(_HomeSection.overview);

  /// 打开「首页 · 余额中心」二级页。
  void _openDormDetail() {
    _goToTab(0, keepHomeSection: true);
    _showHomeSection(_HomeSection.dorm);
  }

  /// 一级标签切换的唯一入口：同步 homeTabProvider 与 _displayedTab，并清理
  /// 当前侧栏插件内容，避免「点首页却仍显示课表 / 插件」的不一致。
  void _goToTab(int target, {bool keepHomeSection = false}) {
    final hadPlugin = _displayedPluginId != null;
    if (hadPlugin) {
      setState(() => _displayedPluginId = null);
    }
    ref.read(homeTabProvider.notifier).state = target;
    if (hadPlugin && target == _displayedTab) {
      // 当前 IndexedStack 已停在目标 tab，只是被插件内容盖住：做一次
      // 单段淡入切换到该 tab，不重复触发 _animateToTab 的排队逻辑。
      _tabFade.value = 0.0;
      unawaited(
        _tabFade.animateTo(
          1.0,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
        ),
      );
    } else {
      unawaited(_animateToTab(target));
    }
    if (target == 0 && !keepHomeSection) {
      _returnHome();
    }
  }

  /// 一级标签切换，并实现「首页」标签的返回语义：
  /// 从别的标签点「首页」→ 回到上次的二级页；已在首页根再点「首页」→ 回根。
  void _selectTab(int value) {
    if (value == 0) {
      final onHomeRoot =
          _tab == 0 && _displayedTab == 0 && _displayedPluginId == null;
      _goToTab(0, keepHomeSection: !onHomeRoot);
      return;
    }
    _goToTab(value);
  }

  /// 系统返回（侧滑/返回键）在二级界面时先回一级根，而不是退出应用。
  /// 优先退出设计模式，其次把首页 section 复位到根卡片。
  void _handleSystemBack() {
    if (_designMode) {
      setState(() => _designMode = false);
      return;
    }
    if (_displayedPluginId != null) {
      setState(() => _displayedPluginId = null);
      _tabFade.value = 0.0;
      unawaited(
        _tabFade.animateTo(
          1.0,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
        ),
      );
      return;
    }
    _returnHome();
  }

  /// 主标签切换：直接换到目标页，再整体淡入 + 0.96→1 轻放大（220ms）。
  /// 不做「先淡出到全黑再进」的两段式，避免出现卡顿/闪白。
  Future<void> _animateToTab(int target) async {
    _pendingTab = target;
    if (_tabFade.isAnimating) return;
    while (_pendingTab != null) {
      final next = _pendingTab!;
      _pendingTab = null;
      if (next == _displayedTab) continue;
      setState(() {
        _displayedTab = next;
        _visitedTabs.add(next);
      });
      _tabFade.value = 0.0;
      await _tabFade.animateTo(
        1.0,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
      );
      if (!mounted) return;
    }
  }

  Widget _wrapTabFade(Widget child) => FadeTransition(
    opacity: _tabFade,
    child: ScaleTransition(
      scale: Tween<double>(
        begin: 0.96,
        end: 1.0,
      ).animate(CurvedAnimation(parent: _tabFade, curve: Curves.easeOutCubic)),
      child: child,
    ),
  );

  /// 宽窗口（桌面/平板）用左侧栏；窄窗口（手机）用底部导航。
  /// 断点按「可用窗口宽度」判断，而非硬件平台或屏幕方向
  /// （见 flutter-build-responsive-layout skill）。
  static const double _wideLayoutMinWidth = 760;

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.sizeOf(context).width >= _wideLayoutMinWidth;
    // 主题切换时让 HomePage 及其 IndexedStack 子页面一起重建。
    ref.watch(appSettingsProvider.select((settings) => settings.isDarkNow));
    ref.listen<AppSettingsController>(appSettingsProvider, (previous, next) {
      unawaited(
        WindowsWindow.setCloseBehavior(
          minimizeToTaskbar: next.minimizeOnClose && next.showTrayIcon,
        ),
      );
      // 通知开关变化时同步启停邮件轮询（关闭后不再 fetch/通知）。
      _syncMailPoller();
    });
    ref.listen<int>(homeTabProvider, (previous, next) {
      unawaited(_animateToTab(next));
    });
    final homeSection = _homeDestinationProvider.select(
      (value) => value.section,
    );
    ref.listen(homeSection, (previous, _) {
      switch (previous) {
        case _HomeSection.mail:
          unawaited(_loadMailSummary());
        case _HomeSection.notifications:
          unawaited(_loadNotifySummary());
        case _HomeSection.news:
          unawaited(_loadNewsSummary());
        default:
          break;
      }
    });
    final atHomeRoot =
        ref.watch(homeSection) == _HomeSection.overview && !_designMode;
    return PopScope(
      canPop: atHomeRoot,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _handleSystemBack();
      },
      child: Scaffold(
        backgroundColor: AppColors.canvas,
        body: SafeArea(
          child: isWide
              ? Column(
                  children: [
                    Expanded(child: _buildDesktop(context)),
                    _buildStatusBar(context),
                  ],
                )
              : _buildMobile(context),
        ),
        bottomNavigationBar: isWide ? null : _buildMobileNav(context),
      ),
    );
  }

  /// 手机端布局：底部导航（首页 / 课表 / e码通 / 设置），设置以内嵌页呈现。
  Widget _buildMobile(BuildContext context) {
    return _wrapTabFade(
      IndexedStack(
        key: const ValueKey('home-tab-stack-mobile'),
        index: _displayedTab,
        children: [
          _buildHomeTab(),
          _visitedTabs.contains(1)
              ? TimetablePage(
                  compact: true,
                  mobile: true,
                  visible: _displayedTab == 1,
                  account: widget.session.studentId,
                )
              : const SizedBox.shrink(),
          _visitedTabs.contains(2) ? _buildEcode() : const SizedBox.shrink(),
          _visitedTabs.contains(3)
              ? MobileSettingsPage(onLogout: _logout)
              : const SizedBox.shrink(),
        ],
      ),
    );
  }

  Widget _buildEcode() => EcodePage(
    session: widget.session,
    active: _displayedTab == 2 && _displayedPluginId == null,
    feed: _ecodeFeed ??= EcodeFeed(
      widget.session,
      credentials: ref.read(credentialStoreProvider),
    ),
  );

  /// 底部导航栏：首页 / 课表 / e码通 / 设置。
  /// 用自绘 Row + GestureDetector，彻底去掉 NavigationBar 选中项的胶囊
  /// 指示器与其切换动画、水波纹；只靠图标/文字变深区分当前项。
  Widget _buildMobileNav(BuildContext context) {
    const items = <(IconData, IconData, String)>[
      (Icons.home_outlined, Icons.home_rounded, '首页'),
      (Icons.calendar_month_outlined, Icons.calendar_month, '课表'),
      (Icons.qr_code_2_outlined, Icons.qr_code_2, 'e码通'),
      (Icons.settings_outlined, Icons.settings, '设置'),
    ];
    // 底部系统手势条（小白条）安全区：图标行下方补足系统手势高度，
    // 背景与上分隔线覆盖整块（含底部内边距），总高 = 62 + bottomInset。
    final bottomInset = MediaQuery.of(context).padding.bottom;
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.line)),
      ),
      padding: EdgeInsets.only(bottom: bottomInset),
      child: SizedBox(
        height: 62,
        child: Row(
          children: [
            for (var i = 0; i < items.length; i++)
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => _selectTab(i),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        _tab == i ? items[i].$2 : items[i].$1,
                        size: 22,
                        color: _tab == i ? AppColors.ink : AppColors.muted,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        items[i].$3,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: _tab == i
                              ? FontWeight.w700
                              : FontWeight.w500,
                          color: _tab == i ? AppColors.ink : AppColors.muted,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _openSettings() async {
    await showSettingsDialog(context);
  }

  Widget _buildStatusBar(BuildContext context) {
    final reading = _statusPrefs?.lastReading;
    final remaining = reading?.rawRemain.trim() ?? '';
    final text = remaining.isEmpty ? '--' : remaining;
    return Container(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.line)),
      ),
      child: Row(
        children: [
          const Spacer(),
          Icon(
            Icons.electric_bolt_rounded,
            size: 13,
            color: remaining.isEmpty ? AppColors.faint : AppColors.campusBlue,
          ),
          const SizedBox(width: 4),
          Text(
            text,
            maxLines: 1,
            style: TextStyle(
              color: remaining.isEmpty ? AppColors.faint : AppColors.ink,
              fontSize: 10,
              fontWeight: FontWeight.w600,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }

  /// 侧栏项的展示信息：内置来自卡片目录，远程来自插件清单。
  ({String label, IconData icon, String? badge})? _sidebarMeta(String id) {
    if (builtinHomeCardIds.contains(id)) {
      final info = homeCardInfo(id);
      if (info == null) return null;
      return (
        label: info.name,
        icon: info.icon,
        badge: id == 'news' ? '闻' : null,
      );
    }
    for (final plugin in _installedPlugins) {
      if (plugin.id != id) continue;
      final icon = plugin.icon;
      return (
        label: plugin.name,
        icon: resolvePluginIcon(icon),
        badge: icon?.type == 'text' ? icon!.value : null,
      );
    }
    return null;
  }

  Widget _buildDesktop(BuildContext context) {
    final showEcode = defaultTargetPlatform == TargetPlatform.android;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          width: 224,
          decoration: BoxDecoration(
            color: AppColors.surface,
            border: Border(right: BorderSide(color: AppColors.line)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(22, 20, 8, 20),
                child: SizedBox(height: 48, child: _Brand()),
              ),
              _NavItem(
                icon: Icons.home_outlined,
                label: '首页',
                active: _displayedPluginId == null && _tab == 0,
                onTap: () => _selectTab(0),
              ),
              _NavItem(
                icon: Icons.calendar_month_outlined,
                label: '课表',
                active: _displayedPluginId == null && _tab == 1,
                onTap: () => _selectTab(1),
              ),
              if (_visibleSidebarIds.isNotEmpty)
                Listener(
                  onPointerDown: (_) => _startSidebarHint(),
                  onPointerUp: (_) => _cancelSidebarHint(),
                  onPointerCancel: (_) => _cancelSidebarHint(),
                  child: SizedBox(
                    // 固定为条数高度：让下方 Spacer 继续把账号块压到底部，
                    // 同时 ReorderableListView 不再吞掉剩余空间。
                    height: _visibleSidebarIds.length * 46.0,
                    child: ReorderableListView(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      buildDefaultDragHandles: false,
                      onReorderItem: _reorderSidebarItems,
                      onReorderStart: (_) {
                        _sidebarHintTimer?.cancel();
                        if (!_sidebarDragging) {
                          setState(() => _sidebarDragging = true);
                        }
                      },
                      onReorderEnd: (_) => _cancelSidebarHint(),
                      children: [
                        for (var i = 0; i < _visibleSidebarIds.length; i++)
                          if (_sidebarMeta(_visibleSidebarIds[i])
                              case final meta?)
                            ReorderableDelayedDragStartListener(
                              key: ValueKey('sidebar-${_visibleSidebarIds[i]}'),
                              index: i,
                              child: _PluginNavItem(
                                label: meta.label,
                                icon: meta.icon,
                                badge: meta.badge,
                                active:
                                    _displayedPluginId == _visibleSidebarIds[i],
                                showDragHandle: _sidebarDragging,
                                onTap: () =>
                                    _openSidebarPlugin(_visibleSidebarIds[i]),
                              ),
                            ),
                      ],
                    ),
                  ),
                ),
              if (showEcode)
                _NavItem(
                  icon: Icons.qr_code_2_outlined,
                  label: 'e码通',
                  active: _tab == 2,
                  onTap: () => _selectTab(2),
                ),
              const Spacer(),
              Padding(
                padding: const EdgeInsets.all(16),
                child: _AccountTile(
                  session: widget.session,
                  onLogout: _logout,
                  onSettings: _openSettings,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: _wrapTabFade(
            Stack(
              fit: StackFit.expand,
              children: [
                Offstage(
                  offstage: _displayedPluginId != null,
                  child: IndexedStack(
                    key: const ValueKey('home-tab-stack'),
                    index: !showEcode && _displayedTab > 1 ? 0 : _displayedTab,
                    children: [
                      _buildHomeTab(),
                      _visitedTabs.contains(1)
                          ? TimetablePage(
                              visible:
                                  _displayedTab == 1 &&
                                  _displayedPluginId == null,
                              account: widget.session.studentId,
                            )
                          : const SizedBox.shrink(),
                      if (showEcode) ...[
                        _visitedTabs.contains(2)
                            ? _buildEcode()
                            : const SizedBox.shrink(),
                        const SizedBox.shrink(),
                      ],
                    ],
                  ),
                ),
                if (_displayedPluginId case final pluginId?)
                  _buildPluginContent(pluginId),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ─────────────────────────── 首页 ───────────────────────────

  Widget _buildHomeTab() {
    final (:section, :plugin) = ref.watch(_homeDestinationProvider);
    final content = switch (section) {
      _HomeSection.overview => _buildHomeOverview(),
      _HomeSection.dorm => _HomeDormDetail(onBack: _returnHome),
      _HomeSection.gallery => HomeCardGallery(
        cards: _homeCards,
        builtins: homeCardCatalog,
        plugins: _catalogPlugins,
        installedVersions: _installedPluginVersions,
        downloading: _downloadProgress,
        failed: _downloadFailed,
        catalogLoading: _catalogLoading,
        catalogError: _catalogError,
        appearances: _appearances,
        onSetAppearance: (id, appearance) =>
            unawaited(_setPluginAppearance(id, appearance)),
        allowPlacementOptions: _allowSidebar,
        onBack: _returnHome,
        onAdd: _addCard,
        onDeleteBuiltin: _deleteCard,
        onDownload: _downloadPlugin,
        onDeletePlugin: (id) => unawaited(_uninstallPlugin(id)),
        onUpdate: _downloadPlugin,
        onRetryCatalog: () => unawaited(_fetchCatalog(force: true)),
      ),
      _HomeSection.mail => MailPage(
        session: widget.session,
        feed: _mailFeed,
        onBack: _returnHome,
      ),
      _HomeSection.notifications => NotificationPage(
        session: widget.session,
        client: _notifications,
        localState: _notificationState,
        isCurrent: _isSessionActive,
        onBack: _returnHome,
      ),
      _HomeSection.network => CampusNetworkPage(
        onBack: _returnHome,
        visible: _displayedTab == 0,
      ),
      _HomeSection.news => NewsPage(onBack: _returnHome),
      _HomeSection.library => PluginRuntimePage(
        manifest: plugin!,
        session: widget.session,
        onBack: _returnHome,
      ),
    };
    return SharedAxisSwitcher(
      forward: section != _HomeSection.overview,
      child: KeyedSubtree(key: ValueKey(section), child: content),
    );
  }

  Widget _buildHomeOverview() {
    final isWide = MediaQuery.sizeOf(context).width >= _wideLayoutMinWidth;
    final owner = AccountScope.scopedName(
      'timetable',
      account: widget.session.studentId,
    );
    final data = ref.watch(timetableAccountProvider) == owner
        ? ref.watch(timetableDataProvider)
        : null;
    int? week;
    if (data != null) {
      try {
        week = TimetableSchedule(data).nowWeek();
      } catch (_) {
        week = null;
      }
    }
    // 侧栏专属插件（sidebar 且未同时放首页）的卡片只在「有侧栏的桌面布局」里隐藏；
    // 同时放首页+侧栏、安卓或窄窗仍显示卡片。
    final cards = (isWide && _allowSidebar)
        ? <HomeCardLayout>[
            for (final card in _homeCards)
              if (!(_appearanceOf(card.id).sidebar &&
                  !_appearanceOf(card.id).home))
                card,
          ]
        : _homeCards;
    return SingleChildScrollView(
      key: const PageStorageKey('home-overview-scroll'),
      padding: EdgeInsets.fromLTRB(
        isWide ? 36 : 20,
        isWide ? 28 : 16,
        isWide ? 36 : 20,
        28,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 2600),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _HomeMasthead(
                accountLabel: widget.session.accountLabel,
                week: week,
                designMode: _designMode,
                onAdd: () => _showHomeSection(_HomeSection.gallery),
                onDone: _exitDesign,
              ),
              const SizedBox(height: 20),
              AnimatedOpacity(
                opacity: _layoutLoaded ? 1 : 0,
                duration: const Duration(milliseconds: 120),
                child: _HomeGrid(
                  cards: cards,
                  unit: _desktopHomeUnit,
                  wideBreakpoint: _wideLayoutMinWidth,
                  columns: 4,
                  designMode: _designMode,
                  buildCard: _buildHomeCard,
                  onReorder: _reorder,
                  onResize: _setSize,
                  onDelete: _deleteCard,
                  onRequestEnterDesign: _enterDesign,
                  onExitDesign: _exitDesign,
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHomeCard(String id) {
    final size = _homeCards
        .firstWhere(
          (c) => c.id == id,
          orElse: () => HomeCardLayout(id: id, size: HomeCardSize.s1x1),
        )
        .size;
    if (id == 'dorm') {
      return KeyedSubtree(
        key: _dormCardKey,
        child: _DormCard(
          size: size,
          prefs: _statusPrefs,
          onOpen: () => _openCardFeature('dorm', _openDormDetail),
        ),
      );
    }
    // 内置卡片优先于远程插件：远程目录里可能存在同名（如 id=news）的旧插件，
    // 内置原生新闻卡必须优先渲染，避免被旧插件占位页覆盖。
    if (id == 'mail') {
      return _MailCard(
        size: size,
        unread: _mailUnread,
        recent: _mailRecent,
        onOpen: () =>
            _openCardFeature('mail', () => _showHomeSection(_HomeSection.mail)),
      );
    }
    if (id == 'notify') {
      return _NotifyCard(
        size: size,
        unread: _notifyUnread,
        recent: _notifyRecent,
        onOpen: () => _openCardFeature(
          'notify',
          () => _showHomeSection(_HomeSection.notifications),
        ),
      );
    }
    if (id == 'news') {
      final notifyOn = ref
          .watch(appSettingsProvider)
          .notifyEnabled('plugin:news');
      return NewsCard(
        size: size,
        unread: notifyOn ? _newsUnread : 0,
        latest: _newsLatest,
        onOpen: () =>
            _openCardFeature('news', () => _showHomeSection(_HomeSection.news)),
      );
    }
    for (final plugin in _installedPlugins) {
      if (plugin.id == id) {
        if (id == campusNetworkPluginId) {
          return CampusNetworkCard(
            size: size,
            visible: _displayedTab == 0,
            onTap: () => _openCardFeature(plugin.id, () => _openPlugin(plugin)),
          );
        }
        return PluginCard(
          size: size,
          manifest: plugin,
          onTap: () => _openCardFeature(plugin.id, () => _openPlugin(plugin)),
        );
      }
    }
    return _PlaceholderCard(id: id, size: size);
  }

  void _showMailSummary(List<MailSummary> items) {
    setState(() {
      _mailRecent = items.take(2).toList(growable: false);
      _mailUnread = items.take(30).where((item) => !item.read).length;
    });
  }

  Future<void> _loadMailSummary() async {
    try {
      final (_, items) = await _mailFeed.refresh();
      if (_isSessionActive()) _showMailSummary(items);
    } catch (_) {
      // Leave the cached summary visible when the mailbox is unavailable.
    }
  }

  void _showNotifySummary(List<AppNotification> items, int unread) {
    setState(() {
      _notifyRecent = items.take(2).toList(growable: false);
      _notifyUnread = unread;
    });
  }

  Future<void> _loadNotifySummary() async {
    try {
      final counts = await _notifications.counts();
      final items = await _notifications.list();
      final state = await _notificationState;
      if (!_isSessionActive()) return;
      final visible = [
        for (final item in items) applyLocalNotificationRead(item, state),
      ];
      // A local read can complete while an older server response is in flight.
      final locallyRead =
          visible.where((item) => item.read).length -
          items.where((item) => item.read).length;
      final unread = (counts.noRead - locallyRead).clamp(0, counts.noRead);
      _showNotifySummary(visible, unread);
      unawaited(
        NotificationCache.instance.save(
          widget.session.studentId,
          visible,
          counts.total,
          unread,
        ),
      );
    } catch (_) {
      // Leave the cached summary visible when the message center is unavailable.
    }
  }

  /// best-effort 拉取新闻摘要供首页卡片展示；失败静默。
  Future<void> _loadNewsSummary() async {
    try {
      final store = const NewsStore();
      final prefs = await store.readPrefs();
      final cid = prefs.selectedCids.isEmpty
          ? NewsPrefs.internalNoticeId
          : prefs.selectedCids.first;
      final client = NewsClient();
      final result = await client.list(cid, page: 1, pageSize: 20);
      final readIds = await store.readReadIds();
      if (!mounted) return;
      final unread = result.items
          .where((item) => !item.hasRead && !readIds.contains(item.id))
          .length;
      setState(() {
        _newsUnread = unread;
        _newsLatest = result.items.take(2).toList(growable: false);
      });
    } catch (_) {
      // 静默失败：新闻卡显示「点开查看新闻」，不影响其它功能。
    }
  }

  /// 根据设置启动/停止「新邮件轮询」。
  ///
  /// 仅在 App 进程存活时用 [Timer.periodic] 每 3 分钟检查一次，不做后台任务、
  /// 不做应用被杀后的推送。设置里关闭邮件通知时不拉取、不通知。
  void _syncMailPoller() {
    // 组件测试环境不启动定时器，避免 "A Timer is still pending"。
    if (Platform.environment.containsKey('FLUTTER_TEST')) return;
    if (!mounted) return;
    final settings = ref.read(appSettingsProvider.notifier);
    final enabled = settings.notifyEnabled('mail');
    if (!enabled) {
      _mailPoller?.stop();
      _mailPoller = null;
      return;
    }
    if (_mailPoller != null) return;
    final poller = MailPoller(
      fetch: _fetchMailForPoll,
      notify: (title, body) =>
          unawaited(SystemNotification.show(title, body, route: 'mail')),
      state: MailPollState(),
      enabled: () => _isSessionActive() && settings.notifyEnabled('mail'),
    );
    _mailPoller = poller;
    unawaited(() async {
      await poller.state.load();
      if (!mounted || _mailPoller != poller) return;
      poller.start();
      // 首次检查只建立基线；恢复上次 knownIds，避免把历史邮件当新邮件刷屏。
      await poller.checkOnce();
    }());
  }

  Future<List<MailSummary>> _fetchMailForPoll() async {
    final (_, items) = await _mailFeed.refresh();
    return items.take(40).toList(growable: false);
  }

  Future<void> _startNotificationPoller() async {
    if (_notifyPollerStarted) return;
    _notifyPollerStarted = true;
    try {
      final store = await _notificationState;
      if (!_isSessionActive()) return;
      final poller = NotificationPoller(
        client: _notifications,
        store: store,
        isCurrent: _isSessionActive,
        notifyEnabled: (key) =>
            ref.read(appSettingsProvider.notifier).notifyEnabled(key),
      );
      _notifyPoller = poller;
      poller.startForegroundPolling();
    } catch (error) {
      debugPrint('[notify] start poller failed: $error');
      _notifyPollerStarted = false;
    }
  }

  /// 同步 Android 后台轮询配置：把 personal.neu.edu.cn 的 cookie 与当前基线交给原生，
  /// 由原生 15 分钟闹钟在应用退出后继续检查「校园通知」。
  Future<void> _syncNotificationBackground() async {
    if (!Platform.isAndroid) return;
    try {
      final enabled = ref
          .read(appSettingsProvider.notifier)
          .notifyEnabled('campus');
      final cookie = NeuServiceSession.cookieHeaderFor(
        NeuServiceSession.parseCookieJar(widget.session.cookies),
        'personal.neu.edu.cn',
      );
      final store = await _notificationState;
      if (!_isSessionActive()) return;
      await NotificationBackground.sync(
        enabled: enabled,
        cookie: cookie,
        last: store.lastNoRead,
      );
    } catch (error) {
      debugPrint('[notify] sync background failed: $error');
    }
  }

  Future<void> _logout() async {
    _endingSession = true;
    ref.read(timetableAccountProvider.notifier).state = null;
    ref.read(timetableDataProvider.notifier).state = null;
    ref.read(timetableOverlayProvider.notifier).state = null;
    ref.invalidate(timetableViewProvider);
    _notifyPoller?.stop();
    _mailFeed.dispose();
    _ecodeFeed?.dispose();
    _notifications.close();
    _mailPoller?.stop();
    _mailPoller = null;
    // 清空本地邮件/通知缓存（无需阻塞退出导航）。
    unawaited(MailCache.instance.clear(widget.session.studentId));
    unawaited(NotificationCache.instance.clear(widget.session.studentId));
    await ref.read(authControllerProvider.notifier).logout();
  }
}
