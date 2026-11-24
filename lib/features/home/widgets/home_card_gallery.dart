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
    this.appearances = const <String, PluginAppearance>{},
    this.onSetAppearance,
    this.allowPlacementOptions = false,
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
  final Map<String, PluginAppearance> appearances;
  final void Function(String id, PluginAppearance appearance)? onSetAppearance;

  /// 是否展示「首页 / 侧栏」多选（仅 Windows 桌面为 true；其它平台沿用原行为）。
  final bool allowPlacementOptions;

  bool _added(String id) => cards.any((card) => card.id == id);

  PluginAppearance _appearanceFor(String id) =>
      appearances[id] ?? defaultPluginAppearance(id);

  bool get _showOptions => allowPlacementOptions && onSetAppearance != null;

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
    if (_showOptions) {
      return _PlacementGalleryItem(
        icon: info.icon,
        badge: info.id == 'news' ? '闻' : null,
        name: info.name,
        description: info.description,
        trailingActions: const <Widget>[],
        id: info.id,
        appearance: _appearanceFor(info.id),
        allowSidebar: true,
        onChanged: (appearance) => onSetAppearance!(info.id, appearance),
      );
    }
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

    // 远程已下载、非内置、且平台允许多选摆放时：描述下方展示三选项，
    // 右侧仅保留「更新 / 删除」。
    final showAppearance = installed && !unsupported && _showOptions;
    if (showAppearance) {
      return _PlacementGalleryItem(
        icon: resolvePluginIcon(manifest.icon),
        badge: manifest.icon?.type == 'text' ? manifest.icon!.value : null,
        name: manifest.name,
        description: '${manifest.description} · v${manifest.version}',
        trailingActions: <Widget>[
          if (updateAvailable) ...[
            _actionButton(
              label: '更新',
              onPressed: () => onUpdate?.call(manifest),
            ),
            const SizedBox(width: 8),
          ],
          SizedBox(
            width: 64,
            child: onDeletePlugin != null
                ? _deleteAction(
                    () => _confirmUninstall(context, manifest),
                    key: ValueKey('delete-plugin-${manifest.id}'),
                  )
                : const SizedBox.shrink(),
          ),
        ],
        id: manifest.id,
        appearance: _appearanceFor(manifest.id),
        allowSidebar: true,
        onChanged: (appearance) =>
            onSetAppearance!(manifest.id, appearance),
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
    this.footer,
  });

  final IconData icon;
  final String name;
  final String description;
  final Widget trailing;
  final String? badge;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
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
          ?footer,
        ],
      ),
    );
  }
}

/// 三选项「不添加 / 添加到首页 / 添加到侧栏」。
///
/// 折叠时摘要按钮与「删除/更新」同一行，展开后在下方显示三个选项。
class _PlacementGalleryItem extends StatefulWidget {
  const _PlacementGalleryItem({
    required this.icon,
    this.badge,
    required this.name,
    required this.description,
    this.trailingActions = const <Widget>[],
    required this.id,
    required this.appearance,
    required this.allowSidebar,
    required this.onChanged,
  });

  final IconData icon;
  final String? badge;
  final String name;
  final String description;
  final List<Widget> trailingActions;
  final String id;
  final PluginAppearance appearance;
  final bool allowSidebar;
  final ValueChanged<PluginAppearance> onChanged;

  @override
  State<_PlacementGalleryItem> createState() => _PlacementGalleryItemState();
}

class _PlacementGalleryItemState extends State<_PlacementGalleryItem> {
  bool _open = false;

  String get _summary {
    final a = widget.appearance;
    if (a.none) return '不添加';
    if (a.home && a.sidebar) return '添加到首页 + 添加到侧栏';
    if (a.home) return '添加到首页';
    return '添加到侧栏';
  }

  @override
  Widget build(BuildContext context) {
    return _GalleryItem(
      icon: widget.icon,
      badge: widget.badge,
      name: widget.name,
      description: widget.description,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            key: ValueKey<String>('placement-dropdown-${widget.id}'),
            borderRadius: BorderRadius.circular(8),
            onTap: () => setState(() => _open = !_open),
            child: Container(
              height: 40,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                color: AppColors.canvas,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.line),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _summary,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: widget.appearance.none
                          ? AppColors.muted
                          : AppColors.campusBlue,
                    ),
                  ),
                  const SizedBox(width: 3),
                  AnimatedRotation(
                    turns: _open ? 0.5 : 0,
                    duration: const Duration(milliseconds: 180),
                    curve: Curves.easeOutCubic,
                    child: Icon(
                      Icons.expand_more_rounded,
                      size: 16,
                      color: AppColors.muted,
                    ),
                  ),
                ],
              ),
            ),
          ),
          for (final action in widget.trailingActions) ...[
            const SizedBox(width: 8),
            action,
          ],
        ],
      ),
      footer: AnimatedSize(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        alignment: Alignment.topCenter,
        clipBehavior: Clip.hardEdge,
        child: _open
            ? Padding(
                padding: const EdgeInsets.only(top: 10),
                child: _AppearanceOptions(
                  id: widget.id,
                  appearance: widget.appearance,
                  allowSidebar: widget.allowSidebar,
                  onChanged: widget.onChanged,
                ),
              )
            : const SizedBox(width: double.infinity),
      ),
    );
  }
}

class _AppearanceOptions extends StatelessWidget {
  const _AppearanceOptions({
    required this.id,
    required this.appearance,
    required this.allowSidebar,
    required this.onChanged,
  });

  final String id;
  final PluginAppearance appearance;
  final bool allowSidebar;
  final ValueChanged<PluginAppearance> onChanged;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _AppearanceChip(
          key: ValueKey('appearance-none-$id'),
          label: '不添加',
          selected: appearance.none,
          onTap: () => onChanged(const PluginAppearance()),
        ),
        _AppearanceChip(
          key: ValueKey('appearance-home-$id'),
          label: '添加到首页',
          selected: appearance.home,
          onTap: () => onChanged(appearance.copyWith(home: !appearance.home)),
        ),
        if (allowSidebar)
          _AppearanceChip(
            key: ValueKey('appearance-sidebar-$id'),
            label: '添加到侧栏',
            selected: appearance.sidebar,
            onTap: () =>
                onChanged(appearance.copyWith(sidebar: !appearance.sidebar)),
          ),
      ],
    );
  }
}

class _AppearanceChip extends StatelessWidget {
  const _AppearanceChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected
          ? AppColors.campusBlue.withValues(alpha: 0.08)
          : AppColors.canvas,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(
          color: selected ? AppColors.campusBlue : AppColors.line,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
              color: selected ? AppColors.campusBlue : AppColors.muted,
            ),
          ),
        ),
      ),
    );
  }
}
