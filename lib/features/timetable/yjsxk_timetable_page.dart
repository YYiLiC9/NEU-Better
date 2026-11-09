import 'dart:convert';
import 'dart:io' show Directory, FileSystemException, Platform;

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart' as mobile;
import 'package:webview_flutter_windows/webview_flutter_windows.dart'
    as desktop;

import '../../app/theme/app_theme.dart';
import 'timetable_import.dart';
import 'timetable_models.dart';

/// Manual-login bridge for the graduate course-selection system.
///
/// The old system uses its own username/password/captcha form rather than CAS,
/// so the safest client-side integration is to let the student log in inside a
/// real WebView and read the same `loadKbxx.do` payload the page itself uses.
class YjsxkTimetablePage extends StatelessWidget {
  const YjsxkTimetablePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Platform.isWindows
        ? const _WindowsYjsxkTimetablePage()
        : const _AndroidYjsxkTimetablePage();
  }
}

const String _yjsxkIndexUrl =
    'https://yjsxk.neu.edu.cn/yjsxkapp/sys/xsxkapp/index.html';

const String _fetchTimetableScript = r'''
(function () {
  try {
    var request = new XMLHttpRequest();
    request.open('GET', '/yjsxkapp/sys/xsxkapp/xsxkCourse/loadKbxx.do?_=' + Date.now(), false);
    request.withCredentials = true;
    request.send(null);
    if (request.status < 200 || request.status >= 300) {
      return JSON.stringify({error: 'HTTP ' + request.status});
    }
    return request.responseText;
  } catch (error) {
    return JSON.stringify({error: String(error)});
  }
})();
''';

TimetableData _parsePayload(Object? raw) {
  if (raw == null) throw const FormatException('课表接口没有返回数据');
  var value = raw;
  for (var i = 0; i < 2; i++) {
    if (value is Map) {
      final map = Map<String, dynamic>.from(value);
      if (map.containsKey('error')) {
        throw FormatException('${map['error']}');
      }
      return YjsxkTimetableParser.parse(jsonEncode(map));
    }
    if (value is! String || value.trim().isEmpty) {
      throw const FormatException('课表接口返回为空');
    }
    final decoded = jsonDecode(value);
    if (decoded is String) {
      value = decoded;
    } else if (decoded is Map) {
      final map = Map<String, dynamic>.from(decoded);
      if (map.containsKey('error')) {
        throw FormatException('${map['error']}');
      }
      return YjsxkTimetableParser.parse(jsonEncode(map));
    } else {
      value = decoded;
    }
  }
  throw const FormatException('无法解析课表数据');
}

class _AndroidYjsxkTimetablePage extends StatefulWidget {
  const _AndroidYjsxkTimetablePage();

  @override
  State<_AndroidYjsxkTimetablePage> createState() =>
      _AndroidYjsxkTimetablePageState();
}

class _AndroidYjsxkTimetablePageState
    extends State<_AndroidYjsxkTimetablePage> {
  late final mobile.WebViewController _controller;
  bool _loading = true;
  bool _reading = false;

  @override
  void initState() {
    super.initState();
    _controller = mobile.WebViewController()
      ..setJavaScriptMode(mobile.JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        mobile.NavigationDelegate(
          onPageStarted: (_) {
            if (mounted) setState(() => _loading = true);
          },
          onPageFinished: (_) {
            if (mounted) setState(() => _loading = false);
          },
          onWebResourceError: (_) {
            if (mounted) setState(() => _loading = false);
          },
        ),
      )
      ..loadRequest(Uri.parse(_yjsxkIndexUrl));
  }

  Future<void> _read() async {
    if (_reading) return;
    setState(() => _reading = true);
    try {
      final raw = await _controller.runJavaScriptReturningResult(
        _fetchTimetableScript,
      );
      final data = _parsePayload(raw);
      if (!mounted) return;
      Navigator.of(context).pop(data);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('读取课表失败：$error')),
      );
    } finally {
      if (mounted) setState(() => _reading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _SyncScaffold(
      reading: _reading,
      onRead: _read,
      body: Stack(
        children: [
          mobile.WebViewWidget(controller: _controller),
          if (_loading)
            const ColoredBox(
              color: Color(0x66FFFFFF),
              child: Center(child: CircularProgressIndicator()),
            ),
        ],
      ),
    );
  }
}

class _WindowsYjsxkTimetablePage extends StatefulWidget {
  const _WindowsYjsxkTimetablePage();

  @override
  State<_WindowsYjsxkTimetablePage> createState() =>
      _WindowsYjsxkTimetablePageState();
}

class _WindowsYjsxkTimetablePageState
    extends State<_WindowsYjsxkTimetablePage> {
  desktop.WebviewController? _controller;
  String? _error;
  bool _reading = false;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    final controller = desktop.WebviewController();
    try {
      Directory dataDir;
      try {
        dataDir = Directory('${Directory.systemTemp.path}\\NEU Better\\WebView2');
        await dataDir.create(recursive: true);
      } on FileSystemException {
        dataDir = Directory('${Directory.current.path}\\data\\webview2');
        await dataDir.create(recursive: true);
      }
      await desktop.WebviewController.initializeEnvironment(
        userDataPath: dataDir.path,
      );
      await controller.initialize();
      await controller.loadUrl(_yjsxkIndexUrl);
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() => _controller = controller);
    } catch (error) {
      await controller.dispose();
      if (!mounted) return;
      setState(() => _error = '无法初始化 Windows WebView2：$error');
    }
  }

  Future<void> _read() async {
    final controller = _controller;
    if (controller == null || _reading) return;
    setState(() => _reading = true);
    try {
      final raw = await controller.executeScript(_fetchTimetableScript);
      final data = _parsePayload(raw);
      if (!mounted) return;
      Navigator.of(context).pop(data);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('读取课表失败：$error')),
      );
    } finally {
      if (mounted) setState(() => _reading = false);
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    return _SyncScaffold(
      reading: _reading,
      onRead: controller == null ? null : _read,
      body: controller == null
          ? Center(
              child: _error == null
                  ? const CircularProgressIndicator()
                  : Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        _error!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: AppColors.danger,
                          height: 1.6,
                        ),
                      ),
                    ),
            )
          : desktop.Webview(controller),
    );
  }
}

class _SyncScaffold extends StatelessWidget {
  const _SyncScaffold({
    required this.reading,
    required this.onRead,
    required this.body,
  });

  final bool reading;
  final VoidCallback? onRead;
  final Widget body;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(
        title: const Text('同步研究生课表'),
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        actions: [
          TextButton(
            onPressed: reading ? null : onRead,
            child: reading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('读取课表'),
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
                color: Colors.white.withValues(alpha: 0.94),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.line),
              ),
              child: const Text(
                '请先在网页中完成研究生选课系统的登录，再点右上角“读取课表”。验证码由学校页面生成。',
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
