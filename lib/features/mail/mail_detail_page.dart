import 'package:flutter/material.dart';

import '../../app/theme/app_theme.dart';
import '../../core/auth/auth_session.dart';
import '../../core/network/mail_client.dart';
import 'mail_format.dart';

/// 邮件详情：原生展示元数据（发件人/收件人/主题/时间/附件）+ 原生正文
/// （由 getMessageData 的 MIME 解析而来，HTML 转纯文本）。只读。
class MailDetailPage extends StatefulWidget {
  const MailDetailPage({
    super.key,
    required this.client,
    required this.summary,
    required this.session,
  });

  final MailClient client;
  final MailSummary summary;

  /// 保留用于上层统一传参；详情已不再依赖 WebView。
  final AuthSession session;

  @override
  State<MailDetailPage> createState() => _MailDetailPageState();
}

class _MailDetailPageState extends State<MailDetailPage> {
  MailDetail? _detail;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final detail = await widget.client.read(widget.summary.id);
      if (!mounted) return;
      setState(() {
        _detail = detail;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '$error';
      });
    }
  }

  String get _subject {
    final detail = _detail;
    if (detail != null && detail.subject.isNotEmpty) return detail.subject;
    return widget.summary.subject.isEmpty ? '(无主题)' : widget.summary.subject;
  }

  String get _from {
    final detail = _detail;
    if (detail != null && detail.from.isNotEmpty) return detail.from;
    return widget.summary.from;
  }

  String get _to {
    final detail = _detail;
    if (detail != null && detail.to.isNotEmpty) return detail.to;
    return widget.summary.to;
  }

  DateTime? get _date => _detail?.date ?? widget.summary.receivedDate;

  List<MailAttachment> get _attachments => _detail?.attachments ?? const [];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        foregroundColor: AppColors.ink,
        title: const Text('邮件详情', style: TextStyle(fontSize: 16)),
        actions: [
          IconButton(
            tooltip: '重新加载',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh_rounded, size: 20),
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final header = _buildHeader(context);
          final content = _buildBody(context);
          if (constraints.maxWidth >= 900) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  width: 380,
                  child: SingleChildScrollView(child: header),
                ),
                const VerticalDivider(width: 1),
                Expanded(child: content),
              ],
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              header,
              const Divider(height: 1),
              Expanded(child: content),
            ],
          );
        },
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    final detail = _detail;
    if (_loading && detail == null) {
      return const Center(
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    final raw = detail?.body ?? '';
    final text = (detail?.isHtml ?? false) ? stripHtmlToText(raw) : raw;
    final trimmed = text.trim();
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
      child: trimmed.isEmpty
          ? Text(
              '（无正文）',
              style: TextStyle(fontSize: 14, color: AppColors.muted),
            )
          : SelectableText(
              trimmed,
              style: TextStyle(
                fontSize: 15,
                height: 1.6,
                color: AppColors.ink,
              ),
            ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final attachments = _attachments;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _subject,
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: AppColors.ink,
              height: 1.3,
            ),
          ),
          const SizedBox(height: 12),
          _MetaRow(label: '发件人', value: _from.isEmpty ? '—' : _from),
          _MetaRow(label: '收件人', value: _to.isEmpty ? '—' : _to),
          _MetaRow(
            label: '时间',
            value: formatMailDate(_date).isEmpty
                ? '—'
                : formatMailDate(_date),
          ),
          if (_loading)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Row(
                children: [
                  SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(strokeWidth: 1.6),
                  ),
                  const SizedBox(width: 8),
                  Text('正在获取邮件信息…',
                      style: TextStyle(fontSize: 11, color: AppColors.muted)),
                ],
              ),
            ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(
                '邮件获取失败：$_error',
                style: TextStyle(fontSize: 11, color: AppColors.danger),
              ),
            ),
          if (attachments.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              '附件（${attachments.length}）',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.muted,
              ),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                for (final attachment in attachments)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.line),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.attach_file_rounded,
                            size: 13, color: AppColors.muted),
                        const SizedBox(width: 4),
                        Text(
                          attachment.name,
                          style: TextStyle(
                              fontSize: 11, color: AppColors.ink),
                        ),
                        if (formatMailSize(attachment.size).isNotEmpty) ...[
                          const SizedBox(width: 4),
                          Text(
                            formatMailSize(attachment.size),
                            style: TextStyle(
                                fontSize: 10, color: AppColors.faint),
                          ),
                        ],
                      ],
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _MetaRow extends StatelessWidget {
  const _MetaRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 52,
            child: Text(
              label,
              style: TextStyle(fontSize: 12, color: AppColors.muted),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(fontSize: 12.5, color: AppColors.ink),
            ),
          ),
        ],
      ),
    );
  }
}
