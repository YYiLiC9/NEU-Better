part of '../webview_login_page.dart';

class _WebViewScaffold extends StatelessWidget {
  const _WebViewScaffold({
    required this.reading,
    required this.onFinish,
    required this.body,
  });

  final bool reading;
  final VoidCallback? onFinish;
  final Widget body;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(
        title: const Text('学校网页登录'),
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.ink,
        surfaceTintColor: Colors.transparent,
        actions: [
          TextButton(
            onPressed: reading ? null : onFinish,
            child: reading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('完成'),
          ),
        ],
      ),
      body: Stack(
        children: [
          Positioned.fill(child: body),
          Positioned(
            left: 16,
            right: 16,
            bottom: 16,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.surface.withValues(
                  alpha: AppColors.isDark ? 0.96 : 0.94,
                ),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.line),
              ),
              child: Text(
                '登录完成后点右上角“完成”。如果页面停在二次验证，请按学校提示完成验证。',
                style: TextStyle(
                  color: AppColors.muted,
                  fontSize: 12,
                  height: 1.5,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
