import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../../app/theme/app_theme.dart';
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
import '../../core/plugins/plugin_service.dart';
import '../dorm/electricity_service.dart';
import '../ecode/ecode_page.dart';
import '../../core/network/notification_client.dart';
import '../mail/mail_format.dart';
import '../mail/mail_page.dart';
import '../plugins/campus_network_page.dart';
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

/// 首页内部的二级分区（0 = 根总览, 1 = 余额中心详情, 2 = 卡片库）。放 ProviderScope 层
/// 以便主题切换重建后仍停留在原二级页。
final homeSectionProvider = StateProvider<int>((ref) => 0);

class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key, required this.session});

  final AuthSession session;

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage>
    with SingleTickerProviderStateMixin {
  final _elecService = DormElectricityService();
  final _homeLayoutStore = const HomeLayoutStore();
  final _pluginService = PluginService();

  /// 已安装的远程插件（完整清单）与已安装版本登记。
  List<PluginManifest> _installedPlugins = const <PluginManifest>[];
  Map<String, String> _installedPluginVersions = const <String, String>{};

  /// 远程插件目录（卡片库「可选插件」列表）。
  List<PluginManifest> _catalogPlugins = const <PluginManifest>[];
  bool _catalogLoading = false;
  String? _catalogError;

  /// 下载/安装进度（0..1）与失败标记，key 为插件 id。
  final Map<String, double> _downloadProgress = <String, double>{};
  final Set<String> _downloadFailed = <String>{};

  /// 0 = 首页, 1 = 课表, 2 = e码通, 3 = 设置。
  int get _tab => ref.watch(homeTabProvider);

  /// 首页卡片布局（顺序 + 尺寸），按账号持久化。
  List<HomeCardLayout> _homeCards = defaultHomeCards();
  bool _layoutLoaded = false;

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

  /// 首页「新闻」卡片展示用（best-effort 拉取，失败不影响首页）。
  int _newsUnread = 0;
  List<NewsItem> _newsLatest = const <NewsItem>[];

  /// e码通页首次进入后常驻（保留 WebView 状态），避免来回切换时重建/闪烁。
  bool _ecodeVisited = false;

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
    // 所有用户数据（课表 / 修改 / 备注 / 寝室号）都按当前账号隔离存储。
    AccountScope.setAccount(widget.session.studentId);
    unawaited(ref.read(appSettingsProvider.notifier).reload());
    // 先用内置卡片集快速读取一次已保存布局，避免首帧闪成默认布局；
    // 已安装插件列表就绪后 `_bootstrapPlugins()` 会再读一次补全插件卡片。
    unawaited(_loadHomeLayout());
    unawaited(_bootstrapPlugins());
    // 监听「点击用电提醒通知 → 打开寝室用电页」：先装 MethodChannel 回调，
    // 再查询冷启动时原生是否已有待处理请求。
    NotificationRouter.ensureHandlerInstalled();
    NotificationRouter.openDormSignal.addListener(_handleOpenDorm);
    NotificationRouter.openTabSignal.addListener(_handleOpenTab);
    unawaited(NotificationRouter.consumePending());
    _loadStatus();
    dormPrefsChanged.addListener(_loadStatus);
    final settings = ref.read(appSettingsProvider);
    unawaited(
      WindowsWindow.setCloseBehavior(
        minimizeToTaskbar: settings.minimizeOnClose && settings.showTrayIcon,
      ),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      _runDailyElectricityCheck();
      // 通知/邮件摘要与轮询不依赖课表同步，先启动，避免课表网络失败阻断它们。
      unawaited(_loadMailSummary());
      unawaited(_loadNotifySummary());
      unawaited(_loadNewsSummary());
      unawaited(_startNotificationPoller());
      unawaited(_syncNotificationBackground());
      await _ensureTimetable();
    });
    // 预热 e码通 WebView：首帧后延迟 1.2s 在后台创建并加载官方 H5，
    // 用户点开 e码通时二维码通常已渲染好，实现「点进去就显示」。
    // 单元/组件测试环境跳过，避免测试里创建 WebView 与悬挂定时器。
    final inTest = Platform.environment.containsKey('FLUTTER_TEST');
    if (!kIsWeb &&
        defaultTargetPlatform == TargetPlatform.android &&
        !inTest) {
      // 首帧后立即预热 e码通（不再延迟 1.2s），让 WebView 与课表同步并行加载，
      // 缩短冷启动首次点开 e码通的等待时间。
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_ecodeVisited) {
          setState(() => _ecodeVisited = true);
        }
      });
    }
  }

  @override
  void didUpdateWidget(covariant HomePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.session.studentId != widget.session.studentId) {
      // 账号变化：切换数据作用域并重新加载该账号的课表 / 用电 / 首页布局。
      AccountScope.setAccount(widget.session.studentId);
      unawaited(ref.read(appSettingsProvider.notifier).reload());
      unawaited(_bootstrapPlugins());
      _loadStatus();
      ref.read(timetableDataProvider.notifier).state = null;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _ensureTimetable();
      });
    }
  }

  Future<void> _loadHomeLayout() async {
    final cards = await _homeLayoutStore.read(allowedIds: _allowedCardIds);
    if (!mounted) return;
    setState(() {
      _homeCards = cards;
      _layoutLoaded = true;
    });
  }

  /// 允许出现在首页的卡片 id：内置 + 已安装插件。
  Set<String> get _allowedCardIds => <String>{
    ...builtinHomeCardIds,
    for (final plugin in _installedPlugins) plugin.id,
  };

  /// 启动/切账号：先读取已安装插件（决定 allowedIds），再加载首页布局，最后拉目录。
  Future<void> _bootstrapPlugins() async {
    try {
      final installed = await _pluginService.readInstalledManifests();
      final versions = await _pluginService.installedVersions();
      if (!mounted) return;
      setState(() {
        _installedPlugins = installed;
        _installedPluginVersions = versions;
      });
      _syncPluginNotifySources(installed);
    } catch (error) {
      debugPrint('[plugins] load installed failed: $error');
    }
    await _loadHomeLayout();
    await _fetchCatalog();
  }

  /// 让「设置 → 通知」里为每个已安装插件出现一个通知开关（默认关）。
  void _syncPluginNotifySources(Iterable<PluginManifest> plugins) {
    final controller = ref.read(appSettingsProvider.notifier);
    for (final plugin in plugins) {
      controller.ensureNotifySource('plugin:${plugin.id}');
    }
  }

  Future<void> _fetchCatalog({bool force = false}) async {
    if (!mounted) return;
    setState(() {
      _catalogLoading = true;
      _catalogError = null;
    });
    try {
      final catalog = await _pluginService.fetchCatalog(force: force);
      if (!mounted) return;
      setState(() {
        _catalogPlugins = catalog.plugins;
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
      final versions = await _pluginService.installedVersions();
      if (!mounted) return;
      setState(() {
        _downloadProgress.remove(manifest.id);
        _installedPlugins = installed;
        _installedPluginVersions = versions;
      });
      ref
          .read(appSettingsProvider.notifier)
          .ensureNotifySource('plugin:${manifest.id}');
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _downloadProgress.remove(manifest.id);
        _downloadFailed.add(manifest.id);
      });
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(content: Text('安装失败：$error')),
      );
    }
  }

  /// 卸载插件：删插件文件 + registry 登记 + 首页卡片。
  Future<void> _uninstallPlugin(String id) async {
    try {
      await _pluginService.uninstall(id);
      final installed = await _pluginService.readInstalledManifests();
      final versions = await _pluginService.installedVersions();
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
      });
      ref.read(appSettingsProvider.notifier).removeNotifySource('plugin:$id');
      await _saveHomeLayout();
    } catch (error) {
      debugPrint('[plugins] uninstall failed: $error');
    }
  }

  void _openPlugin(PluginManifest manifest) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => manifest.id == campusNetworkPluginId
            ? const CampusNetworkPage()
            : PluginRuntimePage(manifest: manifest, session: widget.session),
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

  Future<void> _ensureTimetable() async {    // 测试环境不联网同步（无校园网、且会悬挂网络等待）。
    if (Platform.environment.containsKey('FLUTTER_TEST')) return;
    try {
      final cached = await const TimetableStore().read();
      if (!mounted) return;
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
    if (data != null && mounted) {
      // 同步到的最新课表（含考试）写入共享 Provider，主题切换重挂载时可直接恢复。
      ref.read(timetableDataProvider.notifier).state = data;
      debugPrint('[timetable] auto synced ${data.sessions.length} sessions');
    }
  }

  @override
  void dispose() {
    NotificationRouter.openDormSignal.removeListener(_handleOpenDorm);
    NotificationRouter.openTabSignal.removeListener(_handleOpenTab);
    dormPrefsChanged.removeListener(_loadStatus);
    _notifyPoller?.stop();
    _tabFade.dispose();
    super.dispose();
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
    ref.read(homeTabProvider.notifier).state = 0;
    ref.read(homeSectionProvider.notifier).state = 1;
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
  int _lastSection = 0;

  /// 打开「首页 · 余额中心」二级页。
  void _openDormDetail() {
    ref.read(homeTabProvider.notifier).state = 0;
    ref.read(homeSectionProvider.notifier).state = 1;
  }

  /// 一级标签切换，并实现「首页」标签的返回语义：
  /// 从别的标签点「首页」→ 回到上次的二级页；已在首页二级再点「首页」→ 回根。
  void _selectTab(int value) {
    if (value == 0) {
      if (_tab != 0) {
        ref.read(homeTabProvider.notifier).state = 0; // 保留 section（回上次二级）
      } else if (ref.read(homeSectionProvider) != 0) {
        ref.read(homeSectionProvider.notifier).state = 0;
      }
      return;
    }
    if (value == 2 && !_ecodeVisited) {
      setState(() => _ecodeVisited = true);
    }
    ref.read(homeTabProvider.notifier).state = value;
  }

  /// 系统返回（侧滑/返回键）在二级界面时先回一级根，而不是退出应用。
  /// 优先退出设计模式，其次把首页 section 复位到根卡片。
  void _handleSystemBack(int section) {
    if (_designMode) {
      setState(() => _designMode = false);
      return;
    }
    if (section != 0) {
      ref.read(homeSectionProvider.notifier).state = 0;
    }
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
      setState(() => _displayedTab = next);
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
      scale: Tween<double>(begin: 0.96, end: 1.0).animate(
        CurvedAnimation(parent: _tabFade, curve: Curves.easeOutCubic),
      ),
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
    });
    ref.listen<int>(homeTabProvider, (previous, next) {
      unawaited(_animateToTab(next));
    });
    final section = ref.watch(homeSectionProvider);
    // 一级根 = 首页根卡片、非设计模式。二级界面（余额中心详情 / 卡片库 /
    // 设计模式）时拦截系统返回：先回到一级根，再返回才退出应用。
    final atHomeRoot = section == 0 && !_designMode;
    return PopScope(
      canPop: atHomeRoot,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _handleSystemBack(section);
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
        index: _displayedTab,
        children: [
          _buildHomeTab(),
          TimetablePage(compact: true, mobile: true),
          // e码通首次进入后常驻，避免来回切换重建闪烁。
          (_ecodeVisited || _tab == 2)
              ? EcodePage(session: widget.session, active: _tab == 2)
              : const SizedBox.shrink(),
          MobileSettingsPage(onLogout: _logout),
        ],
      ),
    );
  }

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
                active: _tab == 0,
                onTap: () => _selectTab(0),
              ),
              _NavItem(
                icon: Icons.calendar_month_outlined,
                label: '课表',
                active: _tab == 1,
                onTap: () => _selectTab(1),
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
            IndexedStack(
              index: !showEcode && _displayedTab > 1 ? 0 : _displayedTab,
              children: [
                _buildHomeTab(),
                TimetablePage(),
                if (showEcode) ...[
                  (_ecodeVisited || _tab == 2)
                      ? EcodePage(session: widget.session, active: _tab == 2)
                      : const SizedBox.shrink(),
                  const SizedBox.shrink(),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ─────────────────────────── 首页 ───────────────────────────

  Widget _buildHomeTab() {
    final section = ref.watch(homeSectionProvider);
    final Widget content;
    if (section == 1) {
      content = _HomeDormDetail(
        onBack: () => ref.read(homeSectionProvider.notifier).state = 0,
      );
    } else if (section == 2) {
      content = HomeCardGallery(
        cards: _homeCards,
        builtins: homeCardCatalog,
        plugins: _catalogPlugins,
        installedVersions: _installedPluginVersions,
        downloading: _downloadProgress,
        failed: _downloadFailed,
        catalogLoading: _catalogLoading,
        catalogError: _catalogError,
        onBack: () => ref.read(homeSectionProvider.notifier).state = 0,
        onAdd: _addCard,
        onDeleteBuiltin: _deleteCard,
        onDownload: _downloadPlugin,
        onDeletePlugin: (id) => unawaited(_uninstallPlugin(id)),
        onUpdate: _downloadPlugin,
        onRetryCatalog: () => unawaited(_fetchCatalog(force: true)),
      );
    } else if (section == 3) {
      content = MailPage(
        session: widget.session,
        onBack: () {
          ref.read(homeSectionProvider.notifier).state = 0;
          unawaited(_loadMailSummary());
        },
      );
    } else if (section == 4) {
      content = NotificationPage(
        session: widget.session,
        onBack: () {
          ref.read(homeSectionProvider.notifier).state = 0;
          unawaited(_loadNotifySummary());
        },
      );
    } else {
      content = _buildHomeOverview();
    }
    // 新旧页面采用两段式水平平移（先退出、再进入），不会出现文字重叠；
    // 余额中心 / 邮件 / 通知 / 新闻保持同一套节奏。
    final forward = section >= _lastSection;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _lastSection = section;
    });
    return SharedAxisSwitcher(
      forward: forward,
      child: KeyedSubtree(key: ValueKey<int>(section), child: content),
    );
  }

  Widget _buildHomeOverview() {
    final isWide = MediaQuery.sizeOf(context).width >= _wideLayoutMinWidth;
    final data = ref.watch(timetableDataProvider);
    int? week;
    if (data != null) {
      try {
        week = TimetableSchedule(data).nowWeek();
      } catch (_) {
        week = null;
      }
    }
    return SingleChildScrollView(
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
                onAdd: () => ref.read(homeSectionProvider.notifier).state = 2,
                onDone: _exitDesign,
              ),
              const SizedBox(height: 20),
              AnimatedOpacity(
                opacity: _layoutLoaded ? 1 : 0,
                duration: const Duration(milliseconds: 120),
                child: _HomeGrid(
                  cards: _homeCards,
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
          onOpen: _openDormDetail,
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
        onOpen: _openMail,
      );
    }
    if (id == 'notify') {
      return _NotifyCard(
        size: size,
        unread: _notifyUnread,
        recent: _notifyRecent,
        onOpen: _openNotifications,
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
        onOpen: _openNews,
      );
    }
    for (final plugin in _installedPlugins) {
      if (plugin.id == id) {
        if (id == campusNetworkPluginId) {
          return CampusNetworkCard(
            size: size,
            visible: _displayedTab == 0,
            onTap: () => _openPlugin(plugin),
          );
        }
        return PluginCard(
          size: size,
          manifest: plugin,
          onTap: () => _openPlugin(plugin),
        );
      }
    }
    return _PlaceholderCard(id: id, size: size);
  }

  void _openMail() {
    ref.read(homeSectionProvider.notifier).state = 3;
  }

  /// best-effort 拉取邮件摘要供首页卡片展示；任何失败都静默忽略。
  Future<void> _loadMailSummary() async {
    try {
      MailClient client;
      try {
        client = await MailClient.fromSession(widget.session);
      } catch (_) {
        // 会话换票失败时，若本地保存了密码则用密码再走一次 CAS（与邮件页一致）。
        final credentials = await ref.read(credentialStoreProvider).read();
        final password = credentials?.password;
        if (credentials == null || password == null || password.isEmpty) {
          rethrow;
        }
        client = await MailClient.fromCredentials(
          username: credentials.username,
          password: password,
        );
      }
      final items = await client.list(limit: 30);
      if (!mounted) return;
      // 邮件卡只展示「最近两封未读」：已读邮件不出现在卡片上。
      final unread = items.where((m) => !m.read).toList(growable: false);
      setState(() {
        _mailRecent = unread.take(2).toList(growable: false);
        _mailUnread = unread.length;
      });
    } catch (_) {
      // 静默失败：首页卡片显示「点开查看邮件」，不影响其它功能。
    }
  }

  void _openNotifications() {
    ref.read(homeSectionProvider.notifier).state = 4;
  }

  /// best-effort 拉取通知摘要供首页卡片展示；失败静默。
  Future<void> _loadNotifySummary() async {
    try {
      final client = NotificationClient.fromSession(widget.session);
      final counts = await client.counts();
      final items = await client.list(page: 1);
      if (!mounted) return;
      final unread = items.where((n) => !n.read).toList(growable: false);
      setState(() {
        _notifyRecent = unread.take(2).toList(growable: false);
        _notifyUnread = counts.noRead;
      });
    } catch (_) {
      // 静默失败：通知卡显示「点开查看通知」，不影响其它功能。
    }
  }

  /// 打开新闻插件页；返回后刷新首页新闻卡摘要。
  void _openNews() {
    Navigator.of(context)
        .push(
          MaterialPageRoute<void>(builder: (_) => const NewsPage()),
        )
        .whenComplete(() {
      if (mounted) unawaited(_loadNewsSummary());
    });
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

  Future<void> _startNotificationPoller() async {
    if (_notifyPollerStarted) return;
    _notifyPollerStarted = true;
    try {
      final client = NotificationClient.fromSession(widget.session);
      final store = NotificationStore();
      await store.load();
      final poller = NotificationPoller(
        client: client,
        store: store,
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
      final store = NotificationStore();
      await store.load();
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
    await ref.read(authControllerProvider.notifier).logout();
  }
}
