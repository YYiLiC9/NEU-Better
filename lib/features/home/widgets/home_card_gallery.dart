part of '../home_page.dart';

// ─────────────────────────── 二级：卡片库 ───────────────────────────

/// 「＋」进入的卡片库：列出 [homeCardCatalog] 全部卡片，已在首页的显示灰色
/// 「已添加」不可点，其余可「添加」（追加到首页末尾）。
class HomeCardGallery extends StatelessWidget {
  const HomeCardGallery({
    super.key,
    required this.cards,
    required this.onBack,
    required this.onAdd,
  });

  final List<HomeCardLayout> cards;
  final VoidCallback onBack;
  final void Function(String id) onAdd;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 16, 4),
          child: Row(
            children: [
              IconButton(
                onPressed: onBack,
                icon: const Icon(Icons.arrow_back_rounded),
                color: AppColors.ink,
                tooltip: '返回首页',
              ),
              const SizedBox(width: 2),
              Text(
                '卡片库',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: AppColors.ink,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            itemCount: homeCardCatalog.length,
            separatorBuilder: (_, _) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final info = homeCardCatalog[index];
              final added = cards.any((card) => card.id == info.id);
              return _GalleryItem(
                info: info,
                added: added,
                onAdd: () => onAdd(info.id),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _GalleryItem extends StatelessWidget {
  const _GalleryItem({
    required this.info,
    required this.added,
    required this.onAdd,
  });

  final HomeCardInfo info;
  final bool added;
  final VoidCallback onAdd;

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
            child: Icon(info.icon, size: 22, color: AppColors.campusBlue),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  info.name,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.ink,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  info.description,
                  style: TextStyle(fontSize: 11, color: AppColors.muted),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          if (added)
            TextButton(
              onPressed: null,
              child: Text(
                '已添加',
                style: TextStyle(color: AppColors.faint, fontSize: 12),
              ),
            )
          else
            FilledButton(
              onPressed: onAdd,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.campusBlue,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                textStyle: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              child: const Text('添加'),
            ),
        ],
      ),
    );
  }
}
