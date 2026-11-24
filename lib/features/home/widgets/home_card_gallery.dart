part of '../home_page.dart';

// ─────────────────────────── 二级：卡片库 ───────────────────────────

/// 「＋」进入的卡片库：列出「内置卡片 + 远程插件目录」。
///
/// 内置卡片：未添加 [添加]；已添加 [已添加(灰)] [删除]（仅从首页移除）。
/// 远程插件四态：未下载 [下载]（带版本/进度/失败重试）；已下载未添加
/// [添加] [删除(=卸载)]；已添加 [已添加] [删除]；有更新 [更新]；
/// rendererVersion 过高 [需更新App]（禁用）。
class HomeCardGallery extends StatelessWidget {
  const HomeCardGallery({
    super.key,
    required this.cards,
    this.builtins = homeCardCatalog,
    this.plugins = const <PluginManifest>[],
    this.installedVersions = const <String, String>{},
    this.downloading = const <String, double>{},
    this.failed = const <String>{},
    this.catalogLoading = false,
    this.catalogError,
    required this.onBack,
    required this.onAdd,
    this.onDeleteBuiltin,
    this.onDownload,
    this.onDeletePlugin,
    this.onUpdate,
    this.onRetryCatalog,
    this.placements = const <String, PluginPlacement>{},
    this.onSetPlacement,
    this.allowSidebar = false,
  });

  final List<HomeCardLayout> cards;
  final List<HomeCardInfo> builtins;
  final List<PluginManifest> plugins;
  final Map<String, String> installedVersions;
  final Map<String, double> downloading;
  final Set<String> failed;
  final bool catalogLoading;
  final String? catalogError;
  final VoidCallback onBack;
  final void Function(String id) onAdd;
  final void Function(String id)? onDeleteBuiltin;
  final void Function(PluginManifest manifest)? onDownload;
  final void Function(String id)? onDeletePlugin;
  final void Function(PluginManifest manifest)? onUpdate;
  final VoidCallback? onRetryCatalog;
  final Map<String, PluginPlacement> placements;
  final void Function(String id, PluginPlacement placement)? onSetPlacement;

  /// 是否允许「添加到侧栏」（仅 Windows 桌面为 true；其它平台沿用原行为）。
  final bool allowSidebar;

  bool _added(String id) => cards.any((card) => card.id == id);

  @override
  Widget build(BuildContext context) {
    // 远程目录里若存在与内置卡片同 id 的旧插件（例如 id=news 的占位新闻插件），
    // 不再重复展示，避免内置卡与插件行同名混淆。
    final pluginList = <PluginManifest>[
      for (final plugin in plugins)
        if (!builtins.any((info) => info.id == plugin.id)) plugin,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SecondaryPageHeader(title: '插件库', onBack: onBack),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            itemCount: builtins.length + pluginList.length + 1,
            separatorBuilder: (_, _) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              if (index < builtins.length) {
                final info = builtins[index];
                return _buildBuiltinItem(context, info);
              }
              final pluginIndex = index - builtins.length - 1;
              if (pluginIndex < 0) return _buildCatalogHeader(context);
              return _buildPluginItem(context, pluginList[pluginIndex]);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildCatalogHeader(BuildContext context) {
    if (catalogLoading) {
      return const Padding(
        padding: EdgeInsets.only(top: 6),
        child: Row(
          children: [
            SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 8),
            Text('正在获取插件目录…', style: TextStyle(fontSize: 12)),
          ],
        ),
      );
    }
    if (catalogError != null && plugins.isEmpty) {
      return Row(
        children: [
          Expanded(
            child: Text(
              '暂时无法获取插件目录，请检查网络后重试。',
              style: TextStyle(fontSize: 12, color: AppColors.muted),
            ),
          ),
          TextButton(onPressed: onRetryCatalog, child: const Text('重试')),
        ],
      );
    }
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Text(
        '可选插件',
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: AppColors.muted,
        ),
      ),
    );
  }

  Widget _buildBuiltinItem(BuildContext context, HomeCardInfo info) {
    final added = _added(info.id);
    return _GalleryItem(
      icon: info.icon,
      badge: info.id == 'news' ? '闻' : null,
      name: info.name,
      description: info.description,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (added)
            _addedButton()
          else
            _primaryAddButton(onPressed: () => onAdd(info.id)),
          const SizedBox(width: 8),
          SizedBox(
            width: 64,
            // 常驻内置插件不可卸载：删除按钮恒置灰。
            child: onDeleteBuiltin != null
                ? _deleteAction(null, key: ValueKey('delete-builtin-${info.id}'))
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }

  Widget _buildPluginItem(BuildContext context, PluginManifest manifest) {
    final added = _added(manifest.id);
    final installedVersion = installedVersions[manifest.id];
    final installed = installedVersion != null;
    final progress = downloading[manifest.id];
    final hasFailed = failed.contains(manifest.id);
    final unsupported = !manifest.rendererSupported;
    final updateAvailable =
        installed && installedVersion != manifest.version;
    // 「下载」态没有删除按钮：把版本号放在右侧同一列（与删除按钮对齐），
    // 描述行不再重复显示版本号。
    final versionInColumn =
        !installed && !unsupported && progress == null && !hasFailed;

    // 远程已下载、非内置、且平台允许摆放时，用摆放选择器取代「添加/已添加」。
    final showPlacement =
        installed &&
        !unsupported &&
        !updateAvailable &&
        onSetPlacement != null &&
        allowSidebar;
    if (showPlacement) {
      return _PlacementGalleryItem(
        manifest: manifest,
        placement: placements[manifest.id] ?? PluginPlacement.none,
        allowSidebar: allowSidebar,
        onSetPlacement: (placement) =>
            onSetPlacement!(manifest.id, placement),
        onDelete: onDeletePlugin != null
            ? () => _confirmUninstall(context, manifest)
            : null,
      );
    }

    Widget trailing;
    if (unsupported) {
      trailing = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 96,
            child: Text(
              '需更新App',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: AppColors.faint),
            ),
          ),
          const SizedBox(width: 8),
          const SizedBox(width: 64),
        ],
      );
    } else if (progress != null) {
      trailing = _actionColumns(
        SizedBox(
          width: 96,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              LinearProgressIndicator(value: progress.clamp(0.0, 1.0)),
              const SizedBox(height: 4),
              Text(
                '${(progress * 100).round()}%',
                style: TextStyle(fontSize: 11, color: AppColors.muted),
              ),
            ],
          ),
        ),
      );
    } else if (hasFailed) {
      trailing = _actionColumns(
        _actionButton(label: '重试', onPressed: () => onDownload?.call(manifest)),
      );
    } else if (updateAvailable) {
      trailing = _actionColumns(
        _actionButton(label: '更新', onPressed: () => onUpdate?.call(manifest)),
        delete: onDeletePlugin != null
            ? _deleteAction(
                () => _confirmUninstall(context, manifest),
                key: ValueKey('delete-plugin-${manifest.id}'),
              )
            : null,
      );
    } else if (installed) {
      trailing = _actionColumns(
        added
            ? _addedButton()
            : _primaryAddButton(onPressed: () => onAdd(manifest.id)),
        delete: onDeletePlugin != null
            ? _deleteAction(
                () => _confirmUninstall(context, manifest),
                key: ValueKey('delete-plugin-${manifest.id}'),
              )
            : null,
      );
    } else {
      trailing = _actionColumns(
        _actionButton(label: '下载', onPressed: () => onDownload?.call(manifest)),
        delete: Center(
          child: Text(
            'v${manifest.version}',
            maxLines: 1,
            style: TextStyle(fontSize: 11, color: AppColors.faint),
          ),
        ),
      );
    }

    return _GalleryItem(
      icon: resolvePluginIcon(manifest.icon),
      badge: manifest.icon?.type == 'text' ? manifest.icon!.value : null,
      name: manifest.name,
      description: unsupported
          ? '${manifest.description}（需更新 App 以支持）'
          : (versionInColumn
                ? manifest.description
                : '${manifest.description} · v${manifest.version}'),
      trailing: trailing,
    );
  }

  Future<void> _confirmDelete(
    BuildContext context, {
    required String title,
    required String message,
    required VoidCallback onConfirm,
  }) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('确认'),
          ),
        ],
      ),
    );
    if (ok == true) onConfirm();
  }

  Future<void> _confirmUninstall(
    BuildContext context,
    PluginManifest manifest,
  ) async {
    await _confirmDelete(
      context,
      title: '卸载插件',
      message: '卸载「${manifest.name}」将删除其数据并从首页移除，确定吗？',
      onConfirm: () => onDeletePlugin!(manifest.id),
    );
  }
}

Widget _actionColumns(Widget primary, {Widget? delete}) {
  return Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      primary,
      const SizedBox(width: 8),
      SizedBox(width: 64, child: delete ?? const SizedBox.shrink()),
    ],
  );
}

Widget _actionButton({required String label, VoidCallback? onPressed}) {
  return SizedBox(
    width: 96,
    height: 40,
    child: FilledButton(
      onPressed: onPressed,
      style: FilledButton.styleFrom(padding: EdgeInsets.zero),
      child: Text(label),
    ),
  );
}

Widget _primaryAddButton({VoidCallback? onPressed}) {
  return SizedBox(
    width: 96,
    height: 40,
    child: FilledButton(
      onPressed: onPressed,
      style: FilledButton.styleFrom(padding: EdgeInsets.zero),
      child: const Text('添加'),
    ),
  );
}

Widget _addedButton() => SizedBox(
  width: 96,
  height: 40,
  child: const FilledButton(
    onPressed: null,
    child: Text('已添加'),
  ),
);

Widget _deleteAction(VoidCallback? onPressed, {Key? key}) {
  return OutlinedButton(
    key: key,
    onPressed: onPressed,
    style: OutlinedButton.styleFrom(
      foregroundColor: AppColors.nowRed,
      side: BorderSide(
        color: onPressed == null
            ? AppColors.line
            : AppColors.nowRed.withValues(alpha: 0.55),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      minimumSize: const Size(64, 40),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
      disabledForegroundColor: AppColors.faint,
    ),
    child: const Text('删除'),
  );
}

class _GalleryItem extends StatelessWidget {
  const _GalleryItem({
    required this.icon,
    required this.name,
    required this.description,
    required this.trailing,
    this.badge,
  });

  final IconData icon;
  final String name;
  final String description;
  final Widget trailing;
  final String? badge;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.line),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppColors.campusBlue.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
            ),
            child: badge != null
                ? Center(
                    child: Text(
                      badge!,
                      style: TextStyle(
                        fontSize: 18,
                        height: 1,
                        fontWeight: FontWeight.w700,
                        color: AppColors.campusBlue,
                      ),
                    ),
                  )
                : Icon(icon, size: 22, color: AppColors.campusBlue),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.ink,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  description,
                  style: TextStyle(fontSize: 11, color: AppColors.muted),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          trailing,
        ],
      ),
    );
  }
}

/// 远程已下载插件的「摆放位置」选择器。
///
/// 收起时在 trailing 主列显示 96×40 的当前选择；点击后在本行下方内联展开
/// 3 个紧凑单选（未添加 / 添加到首页 / 添加到侧栏），选择后立即回调并收起。
class _PlacementGalleryItem extends StatefulWidget {
  const _PlacementGalleryItem({
    required this.manifest,
    required this.placement,
    required this.allowSidebar,
    required this.onSetPlacement,
    required this.onDelete,
  });

  final PluginManifest manifest;
  final PluginPlacement placement;
  final bool allowSidebar;
  final void Function(PluginPlacement placement) onSetPlacement;
  final VoidCallback? onDelete;

  @override
  State<_PlacementGalleryItem> createState() => _PlacementGalleryItemState();
}

class _PlacementGalleryItemState extends State<_PlacementGalleryItem> {
  bool _expanded = false;

  String get _currentLabel => switch (widget.placement) {
    PluginPlacement.none => '未添加',
    PluginPlacement.home => '首页卡片',
    PluginPlacement.sidebar => '侧栏',
  };

  void _toggle() => setState(() => _expanded = !_expanded);

  void _select(PluginPlacement? placement) {
    if (placement == null) return;
    widget.onSetPlacement(placement);
    setState(() => _expanded = false);
  }

  @override
  Widget build(BuildContext context) {
    final manifest = widget.manifest;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _GalleryItem(
          icon: resolvePluginIcon(manifest.icon),
          badge: manifest.icon?.type == 'text' ? manifest.icon!.value : null,
          name: manifest.name,
          description: '${manifest.description} · v${manifest.version}',
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 96,
                height: 40,
                child: OutlinedButton(
                  key: ValueKey('placement-${manifest.id}'),
                  onPressed: _toggle,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.ink,
                    side: BorderSide(color: AppColors.line),
                    padding: EdgeInsets.zero,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    textStyle: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  child: Text(
                    _currentLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 64,
                child: widget.onDelete != null
                    ? _deleteAction(
                        widget.onDelete,
                        key: ValueKey('delete-plugin-${manifest.id}'),
                      )
                    : const SizedBox.shrink(),
              ),
            ],
          ),
        ),
        if (_expanded) _buildOptions(),
      ],
    );
  }

  Widget _buildOptions() {
    final options = <(PluginPlacement, String)>[
      (PluginPlacement.none, '未添加'),
      (PluginPlacement.home, '添加到首页'),
      if (widget.allowSidebar) (PluginPlacement.sidebar, '添加到侧栏'),
    ];
    return Padding(
      padding: const EdgeInsets.only(top: 8, left: 8, right: 8),
      child: Material(
        color: AppColors.canvas,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: AppColors.line),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: RadioGroup<PluginPlacement>(
            groupValue: widget.placement,
            onChanged: _select,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final (value, label) in options)
                  RadioListTile<PluginPlacement>(
                    value: value,
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    visualDensity: VisualDensity.compact,
                    title: Text(label, style: const TextStyle(fontSize: 13)),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
