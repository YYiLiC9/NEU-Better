part of '../settings_page.dart';

class _FontSettings extends ConsumerStatefulWidget {
  const _FontSettings();

  @override
  ConsumerState<_FontSettings> createState() => _FontSettingsState();
}

class _FontSettingsState extends ConsumerState<_FontSettings> {
  bool _importing = false;
  String? _importError;

  Future<void> _importFont() async {
    final account = AccountScope.id;
    setState(() {
      _importing = true;
      _importError = null;
    });
    try {
      final font = await ref.read(windowsFontLibraryProvider).pickAndImport();
      if (!mounted || font == null || AccountScope.id != account) return;
      final family = importedFontFamilyProvider(font.id);
      ref.invalidate(family);
      await ref.read(family.future);
      if (!mounted || AccountScope.id != account) return;
      ref.read(appSettingsProvider.notifier).setImportedFont(font);
    } on FormatException catch (error) {
      if (mounted) setState(() => _importError = error.message);
    } catch (_) {
      if (mounted) setState(() => _importError = '无法导入字体，请检查文件后重试。');
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(appSettingsProvider);
    final imported = settings.importedFont;
    final loadFailed =
        settings.fontPreference == AppFontPreference.imported &&
        imported != null &&
        ref.watch(importedFontFamilyProvider(imported.id)).hasError;
    final message = _importError ?? (loadFailed ? '已导入的字体不可用，请重新导入。' : null);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 10,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SegmentedButton<AppFontPreference>(
              segments: [
                const ButtonSegment(
                  value: AppFontPreference.bundled,
                  label: Text('内置字体'),
                ),
                const ButtonSegment(
                  value: AppFontPreference.system,
                  label: Text('系统默认'),
                ),
                if (imported != null)
                  const ButtonSegment(
                    value: AppFontPreference.imported,
                    label: Text('已导入'),
                  ),
              ],
              showSelectedIcon: false,
              selected: {settings.fontPreference},
              onSelectionChanged: _importing
                  ? null
                  : (selection) {
                      setState(() => _importError = null);
                      ref
                          .read(appSettingsProvider.notifier)
                          .setFontPreference(selection.single);
                    },
            ),
            TextButton.icon(
              onPressed: _importing ? null : _importFont,
              icon: const Icon(Icons.file_open_outlined, size: 16),
              label: Text(_importing ? '正在导入' : '从文件导入'),
            ),
          ],
        ),
        if (imported != null)
          Text(imported.name, maxLines: 1, overflow: TextOverflow.ellipsis),
        if (message != null)
          Text(message, style: TextStyle(color: AppColors.danger)),
      ],
    );
  }
}
