part of '../webview_login_page.dart';

class _WindowsWebViewLoginPage extends StatefulWidget {
  const _WindowsWebViewLoginPage();

  @override
  State<_WindowsWebViewLoginPage> createState() =>
      _WindowsWebViewLoginPageState();
}

class _WindowsWebViewLoginPageState extends State<_WindowsWebViewLoginPage> {
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
      debugPrint('[webview] initializing Windows WebView2');
      Directory dataDir;
      try {
        dataDir = Directory(
          '${Directory.systemTemp.path}\\NEU Better\\WebView2',
        );
        await dataDir.create(recursive: true);
      } on FileSystemException {
        // Some locked-down Windows accounts deny writes under AppData/Temp.
        // Keep the webview usable by falling back next to the executable.
        dataDir = Directory('${Directory.current.path}\\data\\webview2');
        await dataDir.create(recursive: true);
      }
      await desktop.WebviewController.initializeEnvironment(
        userDataPath: dataDir.path,
      );
      await controller.initialize();
      await controller.addScriptToExecuteOnDocumentCreated(
        _captureUsernameScript,
      );
      debugPrint('[webview] controller initialized');
      await controller.loadUrl(NeuCasClient.loginUri.toString());
      debugPrint('[webview] loaded CAS page');
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() => _controller = controller);
    } catch (error) {
      debugPrint('[webview] initialization failed: $error');
      if (!mounted) return;
      setState(() => _error = '无法初始化 Windows WebView2：$error');
      await controller.dispose();
    }
  }

  Future<StudentIdentity?> _readIdentity() async {
    try {
      final raw = await _controller?.executeScript(_localIdentityScript);
      return _parseIdentityPayload(raw);
    } catch (_) {
      return null;
    }
  }

  Future<void> _finish() async {
    final controller = _controller;
    if (controller == null || _reading) return;
    setState(() => _reading = true);
    try {
      final identityFuture = _readIdentity();
      final cookies = await controller.getCookies();
      final byDomain = <String, List<String>>{};
      for (final cookie in cookies) {
        if (!cookie.domain.contains('neu.edu.cn')) continue;
        final domain = cookie.domain.replaceFirst(RegExp(r'^\.'), '');
        byDomain
            .putIfAbsent(domain, () => <String>[])
            .add('${cookie.name}=${cookie.value}');
      }

      final result = <String, String>{
        for (final entry in byDomain.entries)
          if (entry.value.isNotEmpty) entry.key: entry.value.join('; '),
      };
      if (!mounted) return;
      if (result.isEmpty) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('还没有取得登录会话，请先在网页中完成登录。')));
        return;
      }

      // Read the portal's cached userInfo before popping; this is local and
      // bounded, so it does not hold the page open on a network round trip.
      final identity = await identityFuture.timeout(
        const Duration(milliseconds: 500),
        onTimeout: () => null,
      );
      final studentId = identity?.studentId ?? _cookieStudentId(cookies);
      if (!mounted) return;
      Navigator.of(context).pop(
        WebViewLoginResult(
          cookies: result,
          studentId: studentId,
          displayName: identity?.displayName,
        ),
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
    return _WebViewScaffold(
      reading: _reading,
      onFinish: controller == null ? null : _finish,
      body: controller == null
          ? Center(
              child: _error == null
                  ? const CircularProgressIndicator()
                  : Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        _error!,
                        style: TextStyle(
                          color: AppColors.danger,
                          fontSize: 13,
                          height: 1.6,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
            )
          : desktop.Webview(controller),
    );
  }
}
