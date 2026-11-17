import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../core/auth/auth_session.dart';
import '../../core/plugins/plugin_models.dart';
import '../../core/plugins/plugin_renderer.dart';

/// 原生插件运行时页：Scaffold + 返回 + 标题 + DSL 渲染（无 WebView）。
///
/// openPage 以新的路由打开子页面（自然支持系统返回）；openUrl 用内嵌
/// WebView 单页展示（项目未引入 url_launcher，不新增依赖）。
class PluginRuntimePage extends StatefulWidget {
  const PluginRuntimePage({
    super.key,
    required this.manifest,
    required this.session,
    this.pageId,
    this.params = const <String, Object?>{},
  });

  final PluginManifest manifest;
  final AuthSession? session;
  final String? pageId;
  final Map<String, Object?> params;

  @override
  State<PluginRuntimePage> createState() => _PluginRuntimePageState();
}

class _PluginRuntimePageState extends State<PluginRuntimePage> {
  late String _pageId;
  late Map<String, Object?> _params;

  @override
  void initState() {
    super.initState();
    _pageId = widget.pageId ?? widget.manifest.startPage;
    _params = Map<String, Object?>.from(widget.params);
  }

  void _openPage(String page, Map<String, Object?> params) {
    if (!widget.manifest.pages.containsKey(page)) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PluginRuntimePage(
          manifest: widget.manifest,
          session: widget.session,
          pageId: page,
          params: params,
        ),
      ),
    );
  }

  void _openUrl(String url) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => _PluginWebPage(url: url)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final page = widget.manifest.pages[_pageId];
    final title = page?.title ?? widget.manifest.name;
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: PluginRuntimeScope(
        openPage: _openPage,
        openUrl: _openUrl,
        refresh: () => setState(() {}),
        child: buildPluginPage(
          context,
          widget.manifest,
          _pageId,
          _params,
          widget.session,
        ),
      ),
    );
  }
}

class _PluginWebPage extends StatefulWidget {
  const _PluginWebPage({required this.url});

  final String url;

  @override
  State<_PluginWebPage> createState() => _PluginWebPageState();
}

class _PluginWebPageState extends State<_PluginWebPage> {
  late final WebViewController _controller;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..loadRequest(Uri.parse(widget.url));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('网页')),
      body: WebViewWidget(controller: _controller),
    );
  }
}
