import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'secondary_page_title.dart';

/// 次级页面（从首页进入的嵌入页）统一头部。
///
/// 返回箭头 + 标题 + 自定义 actions，统一 padding 与间距；
/// 供邮件、通知、校刊、插件库、网络连接等页面复用，避免各页各自手写一行。
class SecondaryPageHeader extends StatelessWidget {
  const SecondaryPageHeader({
    super.key,
    required this.title,
    this.onBack,
    this.actions = const <Widget>[],
  });

  /// 标题文本（经由 [SecondaryPageTitle] 渲染）。
  final String title;

  /// 返回回调；为 null 时不显示返回箭头（如作为侧栏内容嵌入时）。
  final VoidCallback? onBack;

  /// 右侧操作按钮。
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 16, 4),
      child: Row(
        children: [
          if (onBack != null) ...[
            IconButton(
              tooltip: '返回',
              onPressed: onBack,
              color: AppColors.ink,
              icon: const Icon(Icons.arrow_back_rounded, size: 20),
            ),
            const SizedBox(width: 2),
          ],
          Expanded(child: SecondaryPageTitle(title)),
          ...actions,
        ],
      ),
    );
  }
}
