import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../../app/theme/app_theme.dart';
import '../../core/app_labels.dart';
import '../../core/auth/auth_session.dart';
import '../../core/platform/windows_window.dart';
import '../../core/settings/app_settings.dart';
import '../../core/storage/account_scope.dart';
import '../auth/auth_controller.dart';
import '../dorm/dorm_page.dart';
import '../dorm/electricity_alert.dart';
import '../../core/electricity/electricity_models.dart';
import '../dorm/electricity_service.dart';
import '../ecode/ecode_page.dart';
import '../settings/settings_page.dart';
import '../timetable/timetable_page.dart';
import '../timetable/timetable_store.dart';
import '../timetable/timetable_sync.dart';
import '../timetable/timetable_schedule.dart';
import 'home_card_catalog.dart';
import 'home_card_layout.dart';
import 'home_layout_store.dart';

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

  /// 0 = 首页, 1 = 课表, 2 = e码通, 3 = 设置。
  int get _tab => ref.watch(homeTabProvider);

  /// 首页卡片布局（顺序 + 尺寸），按账号持久化。
  List<HomeCardLayout> _homeCards = defaultHomeCards();

  /// 安卓「设计模式」：长按进入后可拖动/删除/改尺寸；桌面无此状态。
  bool _designMode = false;

  /// 桌面卡片固定像素单元尺寸（不随窗口缩放）。
  static const double _desktopHomeUnit = 88;

  DormPrefs? _statusPrefs;

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
    unawaited(_loadHomeLayout());
    // 监听「点击用电提醒通知 → 打开寝室用电页」：先装 MethodChannel 回调，
    // 再查询冷启动时原生是否已有待处理请求。
    NotificationRouter.ensureHandlerInstalled();
    NotificationRouter.openDormSignal.addListener(_handleOpenDorm);
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
      await _ensureTimetable();
    });
    // 预热 e码通 WebView：首帧后延迟 1.2s 在后台创建并加载官方 H5，
    // 用户点开 e码通时二维码通常已渲染好，实现「点进去就显示」。
    // 单元/组件测试环境跳过，避免测试里创建 WebView 与悬挂定时器。
    final inTest = Platform.environment.containsKey('FLUTTER_TEST');
    if (!kIsWeb &&
        defaultTargetPlatform == TargetPlatform.android &&
        !inTest) {
      Future<void>.delayed(const Duration(milliseconds: 1200), () {
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
      unawaited(_loadHomeLayout());
      _loadStatus();
      ref.read(timetableDataProvider.notifier).state = null;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _ensureTimetable();
      });
    }
  }

  Future<void> _loadHomeLayout() async {
    final cards = await _homeLayoutStore.read();
    if (!mounted) return;
    setState(() => _homeCards = cards);
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
    dormPrefsChanged.removeListener(_loadStatus);
    _tabFade.dispose();
    super.dispose();
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
    await DormAlertPresenter.present(
      context,
      reading: reading,
      prefs: prefs,
      onView: _openDormDetail,
    );
  }

  final GlobalKey _dormCardKey = GlobalKey();
  Rect? _dormCardRect;
  int _lastSection = 0;

  /// 打开「首页 · 余额中心」二级页；先记录被点卡片的屏幕矩形，
  /// 用于二级页从卡片处放大、返回时缩回卡片处（类 Android 转场）。
  void _openDormDetail() {
    final rb = _dormCardKey.currentContext?.findRenderObject() as RenderBox?;
    if (rb != null && rb.hasSize) {
      _dormCardRect = rb.localToGlobal(Offset.zero) & rb.size;
    }
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
    return Scaffold(
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
              ? EcodePage(session: widget.session)
              : const SizedBox.shrink(),
          MobileSettingsPage(onLogout: _logout),
        ],
      ),
    );
  }

  /// 底部导航栏：首页 / 课表 / e码通 / 设置，配色沿用静蓝令牌。
  Widget _buildMobileNav(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.line)),
      ),
      child: NavigationBarTheme(
        data: NavigationBarThemeData(
          backgroundColor: AppColors.surface,
          // 去掉选中项背后的“胶囊/操场”指示器，只靠图标与文字变深区分。
          indicatorColor: Colors.transparent,
          iconTheme: WidgetStateProperty.resolveWith((states) {
            final selected = states.contains(WidgetState.selected);
            return IconThemeData(
              color: selected ? AppColors.ink : AppColors.muted,
              size: 22,
            );
          }),
          labelTextStyle: WidgetStateProperty.resolveWith((states) {
            final selected = states.contains(WidgetState.selected);
            return TextStyle(
              fontSize: 11,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              color: selected ? AppColors.ink : AppColors.muted,
            );
          }),
        ),
        child: NavigationBar(
          height: 62,
          selectedIndex: _tab,
          labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
          onDestinationSelected: _selectTab,
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.home_outlined),
              selectedIcon: Icon(Icons.home_rounded),
              label: '首页',
            ),
            NavigationDestination(
              icon: Icon(Icons.calendar_month_outlined),
              selectedIcon: Icon(Icons.calendar_month),
              label: '课表',
            ),
            NavigationDestination(
              icon: Icon(Icons.qr_code_2_outlined),
              selectedIcon: Icon(Icons.qr_code_2),
              label: 'e码通',
            ),
            NavigationDestination(
              icon: Icon(Icons.settings_outlined),
              selectedIcon: Icon(Icons.settings),
              label: '设置',
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
              index: _displayedTab,
              children: [
                _buildHomeTab(),
                TimetablePage(),
                (_ecodeVisited || _tab == 2)
                    ? EcodePage(session: widget.session)
                    : const SizedBox.shrink(),
                const SizedBox.shrink(),
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
    // 卡片库（section 2）不做任何转场；只有「余额中心」二级页(1) 与首页(0)
    // 之间做「从所点卡片处放大 / 缩回卡片处」的转场。
    final galleryInvolved = section == 2 || _lastSection == 2;
    final detailInvolved = section == 1 || _lastSection == 1;
    final Widget content;
    if (section == 1) {
      content = _HomeDormDetail(
        onBack: () => ref.read(homeSectionProvider.notifier).state = 0,
      );
    } else if (section == 2) {
      content = HomeCardGallery(
        cards: _homeCards,
        onBack: () => ref.read(homeSectionProvider.notifier).state = 0,
        onAdd: _addCard,
      );
    } else {
      content = _buildHomeOverview();
    }
    const Duration duration = Duration(milliseconds: 300);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _lastSection = section;
    });
    return LayoutBuilder(
      builder: (context, constraints) {
        var alignment = Alignment.center;
        var beginScale = 0.9;
        if (!galleryInvolved && detailInvolved && _dormCardRect != null) {
          final rb = context.findRenderObject() as RenderBox?;
          final boxTopLeft = rb?.localToGlobal(Offset.zero) ?? Offset.zero;
          final localCenter = _dormCardRect!.center - boxTopLeft;
          final w = constraints.maxWidth <= 0 ? 1.0 : constraints.maxWidth;
          final h = constraints.maxHeight <= 0 ? 1.0 : constraints.maxHeight;
          final ax = (localCenter.dx / w * 2 - 1).clamp(-1.0, 1.0);
          final ay = (localCenter.dy / h * 2 - 1).clamp(-1.0, 1.0);
          alignment = Alignment(ax, ay);
          // 从「卡片实际尺寸」开始放大，而不是从 0（从点缩放会显得很怪）。
          beginScale = (_dormCardRect!.width / w).clamp(0.22, 0.6);
        }
        return AnimatedSwitcher(
          duration: duration,
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          // 关键：旧/新页面按「同一全尺寸、左上对齐」叠放，避免两者高度不同
          // 时 AnimatedSwitcher 默认居中布局导致整页上下跳动 / 瞬移。
          layoutBuilder: (currentChild, previousChildren) => Stack(
            fit: StackFit.expand,
            alignment: Alignment.topLeft,
            children: [...previousChildren, ?currentChild],
          ),
          transitionBuilder: galleryInvolved
              ? (child, animation) => FadeTransition(
                  opacity: animation,
                  child: SlideTransition(
                    position: Tween<Offset>(
                      begin: const Offset(0.04, 0),
                      end: Offset.zero,
                    ).animate(
                      CurvedAnimation(
                        parent: animation,
                        curve: Curves.easeOutCubic,
                      ),
                    ),
                    child: child,
                  ),
                )
              : (child, animation) => FadeTransition(
                  opacity: animation,
                  child: ScaleTransition(
                    scale: Tween<double>(begin: beginScale, end: 1.0).animate(
                      CurvedAnimation(
                        parent: animation,
                        curve: Curves.easeOutCubic,
                      ),
                    ),
                    alignment: alignment,
                    child: child,
                  ),
                ),
          child: KeyedSubtree(key: ValueKey<int>(section), child: content),
        );
      },
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
              _HomeGrid(
                cards: _homeCards,
                unit: isWide ? _desktopHomeUnit : null,
                columns: 4,
                designMode: _designMode,
                buildCard: _buildHomeCard,
                onReorder: _reorder,
                onResize: _setSize,
                onDelete: _deleteCard,
                onRequestEnterDesign: _enterDesign,
                onExitDesign: _exitDesign,
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
    return _PlaceholderCard(id: id, size: size);
  }

  Future<void> _logout() async {
    await ref.read(authControllerProvider.notifier).logout();
  }
}
