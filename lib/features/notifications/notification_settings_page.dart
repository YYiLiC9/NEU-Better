import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/app_theme.dart';
import '../../core/settings/app_settings.dart';

/// 二级「通知设置」：按来源开关系统通知。
///
/// 来源键：`campus` / `dorm` / `mail` / `plugin:<id>`；缺省内置来源开、插件来源关。
class NotificationSettingsPage extends ConsumerWidget {
  const NotificationSettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(appSettingsProvider);
    final controller = ref.read(appSettingsProvider.notifier);

    final sources = <_SourceItem>[
      const _SourceItem('campus', '校园通知', '个人门户消息中心的新通知', Icons.campaign_outlined),
      const _SourceItem('dorm', '寝室用电提醒', '电量低于提醒线时提醒', Icons.bolt_outlined),
      const _SourceItem('mail', '新邮件提醒', '收件箱有新邮件时提醒', Icons.mail_outline_rounded),
      for (final key in settings.notifySources.keys)
        if (key.startsWith('plugin:'))
          _SourceItem(
            key,
            '插件通知 · ${key.substring('plugin:'.length)}',
            '来自插件 ${key.substring('plugin:'.length)} 的通知',
            Icons.extension_outlined,
          ),
    ];

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
                    secondary: Icon(
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
            '提示：系统通知依赖应用在前台或托盘运行（Android 后台常驻轮询将在后续版本提供）。',
            style: TextStyle(fontSize: 11, height: 1.5, color: AppColors.faint),
          ),
        ],
      ),
    );
  }
}

class _SourceItem {
  const _SourceItem(this.key, this.title, this.subtitle, this.icon);

  final String key;
  final String title;
  final String subtitle;
  final IconData icon;
}
