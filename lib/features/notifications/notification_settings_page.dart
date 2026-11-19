import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/app_theme.dart';
import '../../core/plugins/plugin_icon_resolver.dart';
import '../../core/plugins/plugin_models.dart';
import '../../core/plugins/plugin_service.dart';
import '../../core/settings/app_settings.dart';

/// 二级「通知设置」：按来源开关系统通知。
///
/// 来源键：`campus` / `dorm` / `mail` / `plugin:<id>`；缺省内置来源开、插件来源关。
class NotificationSettingsPage extends ConsumerWidget {
  const NotificationSettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(
        backgroundColor: AppColors.canvas,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: Text(
          '通知设置',
          style: TextStyle(
            color: AppColors.ink,
            fontSize: 17,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
        children: const [NotificationSettingsContent()],
      ),
    );
  }
}

/// 桌面端：以与「设置」弹窗同尺寸的小窗打开通知设置。
Future<void> showNotificationSettingsDialog(BuildContext context) {
  final isDark = AppColors.isDark;
  return showDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierColor: isDark ? const Color(0x66000000) : const Color(0x2E14243B),
    builder: (dialogContext) => Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        width: 460,
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(dialogContext).height * 0.82,
        ),
        padding: const EdgeInsets.fromLTRB(22, 18, 22, 16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.line),
          boxShadow: AppColors.isDark
              ? null
              : const [
                  BoxShadow(
                    color: Color(0x140B2E5C),
                    blurRadius: 32,
                    offset: Offset(0, 16),
                  ),
                ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: AppColors.campusBlue.withValues(
                      alpha: AppColors.isDark ? 0.22 : 0.10,
                    ),
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Icon(
                    Icons.notifications_active_outlined,
                    size: 16,
                    color: AppColors.campusBlue,
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  '通知',
                  style: TextStyle(
                    color: AppColors.ink,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                Tooltip(
                  message: '关闭',
                  waitDuration: const Duration(milliseconds: 500),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: () => Navigator.of(dialogContext).pop(),
                    child: Padding(
                      padding: const EdgeInsets.all(5),
                      child: Icon(
                        Icons.close_rounded,
                        size: 17,
                        color: AppColors.muted,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.only(right: 14),
                child: const NotificationSettingsContent(),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class NotificationSettingsContent extends ConsumerStatefulWidget {
  const NotificationSettingsContent({super.key});

  @override
  ConsumerState<NotificationSettingsContent> createState() =>
      _NotificationSettingsContentState();
}

class _NotificationSettingsContentState
    extends ConsumerState<NotificationSettingsContent> {
  Map<String, PluginManifest> _plugins = const <String, PluginManifest>{};

  @override
  void initState() {
    super.initState();
    _loadPlugins();
  }

  Future<void> _loadPlugins() async {
    try {
      final list = await PluginService().readInstalledManifests();
      if (!mounted) return;
      setState(() {
        _plugins = <String, PluginManifest>{
          for (final plugin in list) plugin.id: plugin,
        };
      });
    } catch (error) {
      debugPrint('[notify-settings] load plugins failed: $error');
    }
  }

  _SourceItem _pluginSource(String key) {
    final id = key.substring('plugin:'.length);
    final plugin = _plugins[id];
    final rawName = plugin?.name.trim() ?? '';
    final name = rawName.isEmpty ? id : rawName;
    final desc = plugin?.description.trim() ?? '';
    return _SourceItem(
      key,
      '$name通知',
      desc.isEmpty ? '来自插件 $name 的通知' : desc,
      resolvePluginIcon(plugin?.icon),
      badge: plugin?.icon?.type == 'text' ? plugin!.icon!.value : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(appSettingsProvider);
    final controller = ref.read(appSettingsProvider.notifier);

    final sources = <_SourceItem>[
      const _SourceItem(
        'campus',
        '校园通知',
        '个人门户消息中心的新通知',
        Icons.notifications_none_rounded,
      ),
      const _SourceItem('dorm', '寝室用电提醒', '电量低于提醒线时提醒', Icons.bolt_outlined),
      const _SourceItem('mail', '新邮件提醒', '收件箱有新邮件时提醒', Icons.mail_outline_rounded),
      for (final key in settings.notifySources.keys)
        if (key.startsWith('plugin:')) _pluginSource(key),
    ];

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '选择需要弹出系统通知的来源。关闭某来源后，仍可在 App 内查看。',
          style: TextStyle(fontSize: 12, height: 1.5, color: AppColors.muted),
        ),
        const SizedBox(height: 14),
        Container(
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.line),
          ),
          child: Column(
            children: [
              for (var i = 0; i < sources.length; i++) ...[
                if (i > 0) Divider(height: 1, color: AppColors.line),
                SwitchListTile.adaptive(
                  value: controller.notifyEnabled(sources[i].key),
                  onChanged: (value) =>
                      controller.setNotifyEnabled(sources[i].key, value),
                  activeTrackColor: AppColors.campusBlue,
                  secondary: sources[i].badge != null
                      ? Container(
                          width: 22,
                          height: 22,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: AppColors.campusBlue.withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            sources[i].badge!,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: AppColors.campusBlue,
                            ),
                          ),
                        )
                      : Icon(
                          sources[i].icon,
                          size: 19,
                          color: AppColors.muted,
                        ),
                  title: Text(
                    sources[i].title,
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                      color: AppColors.ink,
                    ),
                  ),
                  subtitle: Text(
                    sources[i].subtitle,
                    style: TextStyle(fontSize: 11, color: AppColors.muted),
                  ),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 16),
        Text(
          '提示：安卓后台约每 15 分钟检查一次校园通知（系统省电可能延后）；邮件/插件通知目前仅提供开关。',
          style: TextStyle(fontSize: 11, height: 1.5, color: AppColors.faint),
        ),
      ],
    );
  }
}

class _SourceItem {
  const _SourceItem(this.key, this.title, this.subtitle, this.icon, {this.badge});

  final String key;
  final String title;
  final String subtitle;
  final IconData icon;
  final String? badge;
}
