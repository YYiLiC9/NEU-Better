import 'dart:convert';

import 'package:flutter/material.dart';

import '../../app/theme/app_theme.dart';
import '../../core/auth/credential_store.dart';
import '../../core/network/yjs_timetable_client.dart';
import 'timetable_import.dart';
import 'timetable_models.dart';

/// Fetches the real timetable from the new graduate platform's
/// "培养 — 学生课程表" application (`wdkbapp/xskcb`).
///
/// The sync runs over plain HTTP with the cookies from a native CAS login
/// (service bound to `yjs.neu.edu.cn`), so it works on every desktop and
/// mobile platform without WebView2. A saved account/password is required.
class YjsTimetablePage extends StatefulWidget {
  const YjsTimetablePage({super.key});

  @override
  State<YjsTimetablePage> createState() => _YjsTimetablePageState();
}

class _YjsTimetablePageState extends State<YjsTimetablePage> {
  bool _busy = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _sync();
  }

  Future<void> _sync() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final credentials = await const SecureCredentialStore().read();
      if (credentials == null ||
          credentials.username.trim().isEmpty ||
          credentials.password == null ||
          credentials.password!.isEmpty) {
        throw const FormatException('请先在登录页勾选“保存账号密码”并完成一次登录');
      }
      final raw = await YjsTimetableClient().fetch(
        username: credentials.username,
        password: credentials.password!,
      );
      if (raw == null) {
        throw const FormatException('研究生系统没有返回响应');
      }
      final envelope = jsonDecode(raw);
      if (envelope is! Map) {
        throw const FormatException('研究生系统返回格式不正确');
      }
      final error = envelope['error'];
      if (error is String && error.trim().isNotEmpty) {
        throw FormatException(error);
      }
      final body = envelope['body'];
      if (body is! String || body.trim().isEmpty) {
        throw const FormatException('研究生系统没有返回课表数据');
      }
      final data = YjsTimetableParser.parse(
        body,
        fallbackTermName: '研究生课程表',
        currentWeek: (envelope['currentWeek'] as num?)?.toInt(),
      );
      if (!mounted) return;
      Navigator.of(context).pop<TimetableData>(data);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = _shortError(error);
      });
    }
  }

  String _shortError(Object error) {
    final text = error.toString();
    if (text.contains('grouplist 为空') || text.contains('研究生系统身份')) {
      return '当前账号没有研究生系统身份，请先确认学校已开通“研究生系统（新）”。';
    }
    if (text.contains('保存账号密码')) return text;
    if (text.length > 180) return '${text.substring(0, 180)}…';
    return text;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(title: const Text('同步研究生课表')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: _busy
                ? const Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(),
                      SizedBox(height: 18),
                      Text(
                        '正在读取“培养 — 学生课程表”…',
                        style: TextStyle(color: AppColors.muted),
                      ),
                      SizedBox(height: 6),
                      Text(
                        '首次同步需要启动学校网页会话，约 10–30 秒',
                        style: TextStyle(color: AppColors.faint, fontSize: 11),
                      ),
                    ],
                  )
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.cloud_off_rounded,
                        color: AppColors.danger,
                        size: 36,
                      ),
                      const SizedBox(height: 14),
                      Text(
                        _error ?? '同步失败',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: AppColors.ink,
                          height: 1.5,
                        ),
                      ),
                      const SizedBox(height: 18),
                      FilledButton.icon(
                        onPressed: _sync,
                        icon: const Icon(Icons.refresh_rounded),
                        label: const Text('重试'),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}
