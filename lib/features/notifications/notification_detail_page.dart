import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/theme/app_theme.dart';
import 'notification_models.dart';

/// 单条通知详情（只读正文，支持长按选择复制）。
class NotificationDetailPage extends StatelessWidget {
  const NotificationDetailPage({super.key, required this.item, this.onBack});

  final AppNotification item;

  /// 非空表示内嵌在首页二级页中，返回时调用它（而不是 Navigator.pop）。
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(
        backgroundColor: AppColors.canvas,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        automaticallyImplyLeading: false,
        leading: onBack == null
            ? null
            : IconButton(
                tooltip: '返回',
                onPressed: onBack,
                icon: const Icon(Icons.arrow_back_rounded, size: 20),
              ),
        title: Text(
          '通知详情',
          style: TextStyle(
            color: AppColors.ink,
            fontSize: 17,
            fontWeight: FontWeight.w700,
          ),
        ),
        actions: [
          if (item.url.isNotEmpty)
            IconButton(
              tooltip: '复制链接',
              icon: Icon(Icons.link_rounded, color: AppColors.muted),
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: item.url));
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('链接已复制')),
                  );
                }
              },
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          Text(
            item.title.isEmpty ? '（无标题）' : item.title,
            style: TextStyle(
              color: AppColors.ink,
              fontSize: 19,
              height: 1.35,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            [
              if (item.sourceName.isNotEmpty) item.sourceName,
              if (item.typeName.isNotEmpty && item.typeName != item.sourceName)
                item.typeName,
              if (item.time != null) _format(item.time!),
            ].join(' · '),
            style: TextStyle(fontSize: 11.5, color: AppColors.faint),
          ),
          const SizedBox(height: 14),
          Divider(color: AppColors.line, height: 1),
          const SizedBox(height: 16),
          SelectableText(
            item.content.trim().isEmpty ? '（无正文）' : item.content.trim(),
            style: TextStyle(
              color: AppColors.ink,
              fontSize: 14.5,
              height: 1.65,
            ),
          ),
          if (item.url.isNotEmpty) ...[
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.line),
              ),
              child: SelectableText(
                item.url,
                style: TextStyle(fontSize: 11.5, color: AppColors.campusBlue),
              ),
            ),
          ],
        ],
      ),
    );
  }

  static String _format(DateTime time) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${time.year}-${two(time.month)}-${two(time.day)} '
        '${two(time.hour)}:${two(time.minute)}';
  }
}
