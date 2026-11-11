part of '../webview_login_page.dart';

class _AndroidWebViewLoginPage extends StatefulWidget {
  const _AndroidWebViewLoginPage();

  @override
  State<_AndroidWebViewLoginPage> createState() =>
      _AndroidWebViewLoginPageState();
}

class _AndroidWebViewLoginPageState extends State<_AndroidWebViewLoginPage> {
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
            unawaited(_captureAndroidUsername(_controller));
          },
          onWebResourceError: (_) {
            if (mounted) setState(() => _loading = false);
          },
        ),
      )
      ..loadRequest(NeuCasClient.loginUri);
  }

  Future<StudentIdentity?> _readIdentity() async {
    try {
      final raw = await _controller.runJavaScriptReturningResult(
        _localIdentityScript,
      );
      return _parseIdentityPayload(raw);
    } catch (_) {
      return null;
    }
  }

  Future<void> _finish() async {
    if (_reading) return;
    setState(() => _reading = true);
    try {
      final identityFuture = _readIdentity();
      final result = <String, String>{};
      final allCookies = <dynamic>[];
      for (final host in const ['pass.neu.edu.cn', 'personal.neu.edu.cn']) {
        final cookies = await mobile.WebViewCookieManager().getCookies(
          domain: Uri.parse('https://$host'),
        );
        if (cookies.isEmpty) continue;
        allCookies.addAll(cookies);
        final pairs = <String, String>{};
        for (final cookie in cookies) {
          pairs[cookie.name] = cookie.value;
        }
        result[host] = pairs.entries
            .map((entry) => '${entry.key}=${entry.value}')
            .join('; ');
      }

      if (!mounted) return;
      if (result.isEmpty) {
        _showEmptyCookieMessage();
        return;
      }

      // A localStorage read is local and fast; it gives the real name without
      // adding a visible pause. If the portal has not stored it yet, the
      // shell refreshes identity from /site/user_info in the background.
      final identity = await identityFuture.timeout(
        const Duration(milliseconds: 500),
        onTimeout: () => null,
      );
      final studentId = identity?.studentId ?? _cookieStudentId(allCookies);
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

  void _showEmptyCookieMessage() {
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('还没有取得登录会话，请先在网页中完成登录。')));
  }

  @override
  Widget build(BuildContext context) {
    return _WebViewScaffold(
      reading: _reading,
      onFinish: _finish,
      body: Stack(
        children: [
          mobile.WebViewWidget(controller: _controller),
          if (_loading)
            ColoredBox(
              color: AppColors.canvas.withValues(alpha: 0.62),
              child: const Center(child: CircularProgressIndicator()),
            ),
        ],
      ),
    );
  }
}
