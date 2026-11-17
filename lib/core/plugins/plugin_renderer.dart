import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../auth/auth_session.dart';
import 'plugin_models.dart';

/// 插件运行时提供给 DSL 的导航/动作回调。由 `PluginRuntimePage` 注入；
/// 单独渲染（测试）时可缺省，openPage/openUrl 将静默忽略。
class PluginRuntimeScope extends InheritedWidget {
  const PluginRuntimeScope({
    super.key,
    required this.openPage,
    required this.openUrl,
    required this.refresh,
    required super.child,
  });

  final void Function(String page, Map<String, Object?> params) openPage;
  final void Function(String url) openUrl;
  final VoidCallback refresh;

  static PluginRuntimeScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<PluginRuntimeScope>();

  @override
  bool updateShouldNotify(PluginRuntimeScope oldWidget) => false;
}

/// 原生 DSL 渲染入口：渲染 manifest 中指定 page。绝不使用 WebView。
Widget buildPluginPage(
  BuildContext context,
  PluginManifest manifest,
  String pageId,
  Map<String, Object?> params,
  AuthSession? session,
) {
  final page = manifest.pages[pageId];
  if (page == null) {
    return const Center(child: Text('页面不存在'));
  }
  return _PluginPageView(
    manifest: manifest,
    page: page,
    params: Map<String, Object?>.from(params),
    session: session,
  );
}

class _PluginPageView extends StatelessWidget {
  const _PluginPageView({
    required this.manifest,
    required this.page,
    required this.params,
    required this.session,
  });

  final PluginManifest manifest;
  final PluginPageSpec page;
  final Map<String, Object?> params;
  final AuthSession? session;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: [
        for (final component in page.body)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _PluginComponentView(
              component: component,
              params: params,
              session: session,
              theme: theme,
            ),
          ),
      ],
    );
  }
}

class _PluginComponentView extends StatelessWidget {
  const _PluginComponentView({
    required this.component,
    required this.params,
    required this.session,
    required this.theme,
  });

  final PluginComponentSpec component;
  final Map<String, Object?> params;
  final AuthSession? session;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    switch (component.type) {
      case 'text':
      case 'richText':
        return _buildText(context);
      case 'divider':
        return Divider(color: theme.dividerColor, height: 1);
      case 'spacer':
        return SizedBox(height: (num.tryParse('${component.json['height'] ?? 12}') ?? 12).toDouble());
      case 'image':
        return _buildImage(context);
      case 'section':
        return _buildSection(context);
      case 'card':
        return _buildCard(context);
      case 'button':
        return _buildButton(context);
      case 'list':
        return _PluginList(
          component: component,
          params: params,
          session: session,
          theme: theme,
        );
      case 'form':
        return _PluginForm(component: component, params: params, theme: theme);
      default:
        return Text(
          '不支持的组件：${component.type}',
          style: TextStyle(fontSize: 12, color: theme.disabledColor),
        );
    }
  }

  TextStyle? _textStyle() {
    switch (component.style) {
      case 'title':
        return theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700);
      case 'caption':
        return theme.textTheme.bodySmall?.copyWith(color: theme.hintColor);
      default:
        return theme.textTheme.bodyMedium;
    }
  }

  Widget _buildText(BuildContext context) {
    final text = interpolateTemplate(component.value ?? '', params);
    return Text(text, style: _textStyle());
  }

  Widget _buildImage(BuildContext context) {
    final url = interpolateTemplate(
      component.json['url']?.toString() ?? component.value ?? '',
      params,
    );
    if (url.isEmpty) return const SizedBox.shrink();
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Image.network(
        url,
        height: 160,
        width: double.infinity,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => Container(
          height: 120,
          color: theme.colorScheme.surfaceContainerHighest,
          alignment: Alignment.center,
          child: Icon(Icons.image_not_supported_outlined, color: theme.hintColor),
        ),
      ),
    );
  }

  Widget _buildSection(BuildContext context) {
    final title = interpolateTemplate(
      component.json['title']?.toString() ?? component.value ?? '',
      params,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 6),
      ],
    );
  }

  Widget _buildCard(BuildContext context) {
    final title = interpolateTemplate(
      component.json['title']?.toString() ?? '',
      params,
    );
    final body = interpolateTemplate(component.json['body']?.toString() ?? '', params);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: theme.dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title.isNotEmpty)
            Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
          if (title.isNotEmpty && body.isNotEmpty) const SizedBox(height: 6),
          if (body.isNotEmpty) Text(body, style: theme.textTheme.bodyMedium),
        ],
      ),
    );
  }

  Widget _buildButton(BuildContext context) {
    final label = interpolateTemplate(
      component.text ?? component.json['label']?.toString() ?? '按钮',
      params,
    );
    final action = component.action;
    return Align(
      alignment: Alignment.centerLeft,
      child: FilledButton(
        onPressed: action == null ? null : () => _runAction(context, action, params),
        child: Text(label),
      ),
    );
  }
}

// ─────────────────────────── 列表 ───────────────────────────

class _PluginList extends StatefulWidget {
  const _PluginList({
    required this.component,
    required this.params,
    required this.session,
    required this.theme,
  });

  final PluginComponentSpec component;
  final Map<String, Object?> params;
  final AuthSession? session;
  final ThemeData theme;

  @override
  State<_PluginList> createState() => _PluginListState();
}

class _PluginListState extends State<_PluginList> {
  late Future<List<Map<String, Object?>>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<Map<String, Object?>>> _load() async {
    final data = widget.component.data;
    final sourceType = data['type']?.toString() ?? 'static';
    if (sourceType == 'httpJson') {
      final raw = await PluginHttp.fetch(
        url: data['url']?.toString() ?? '',
        method: data['method']?.toString() ?? 'GET',
        itemsPath: data['itemsPath']?.toString(),
        headers: data['headers'],
        session: data['useSessionCookies'] == true ? widget.session : null,
      );
      return raw;
    }
    final items = data['items'];
    if (items is List) {
      return <Map<String, Object?>>[
        for (final item in items)
          if (item is Map)
            <String, Object?>{
              for (final entry in item.entries) entry.key.toString(): entry.value,
            },
      ];
    }
    return const <Map<String, Object?>>[];
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, Object?>>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          );
        }
        if (snapshot.hasError) {
          return _LoadError(
            message: '加载失败：${snapshot.error}',
            onRetry: () => setState(() => _future = _load()),
          );
        }
        final items = snapshot.data ?? const <Map<String, Object?>>[];
        if (items.isEmpty) {
          return Text('暂无数据', style: TextStyle(color: widget.theme.hintColor));
        }
        final itemTemplate = widget.component.item;
        return Column(
          children: [
            for (final item in items)
              _buildRow(context, item, itemTemplate),
          ],
        );
      },
    );
  }

  Widget _buildRow(
    BuildContext context,
    Map<String, Object?> item,
    Map<String, Object?>? template,
  ) {
    final merged = <String, Object?>{...widget.params, ...item};
    final title = interpolateTemplate(
      template?['title']?.toString() ?? '${item['title'] ?? ''}',
      merged,
    );
    final subtitle = interpolateTemplate(
      template?['subtitle']?.toString() ?? '${item['subtitle'] ?? ''}',
      merged,
    );
    final imageUrl = interpolateTemplate(
      template?['image']?.toString() ?? '${item['image'] ?? ''}',
      merged,
    );
    final action = PluginActionSpec.fromJson(template?['onTap']);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: widget.theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: action == null ? null : () => _runAction(context, action, merged),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                if (imageUrl.isNotEmpty)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.network(
                      imageUrl,
                      width: 42,
                      height: 42,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => Icon(
                        Icons.image_outlined,
                        color: widget.theme.hintColor,
                      ),
                    ),
                  ),
                if (imageUrl.isNotEmpty) const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      if (subtitle.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          subtitle,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            color: widget.theme.hintColor,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (action != null)
                  Icon(Icons.chevron_right, color: widget.theme.hintColor),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────── 表单 ───────────────────────────

class _PluginForm extends StatefulWidget {
  const _PluginForm({required this.component, required this.params, required this.theme});

  final PluginComponentSpec component;
  final Map<String, Object?> params;
  final ThemeData theme;

  @override
  State<_PluginForm> createState() => _PluginFormState();
}

class _PluginFormState extends State<_PluginForm> {
  final Map<String, TextEditingController> _controllers = <String, TextEditingController>{};
  bool _submitting = false;

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  TextEditingController _controllerFor(String key) =>
      _controllers.putIfAbsent(key, TextEditingController.new);

  Future<void> _submit() async {
    final action = widget.component.action;
    final values = <String, Object?>{
      for (final entry in _controllers.entries) entry.key: entry.value.text,
    };
    final merged = <String, Object?>{...widget.params, ...values};
    if (action == null) return;
    if (action.type == 'submitForm' && action.url != null && action.url!.isNotEmpty) {
      setState(() => _submitting = true);
      try {
        await PluginHttp.submit(
          url: interpolateTemplate(action.url!, merged),
          method: widget.component.json['method']?.toString() ?? 'POST',
          values: values,
        );
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('提交成功')),
        );
      } catch (error) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('提交失败：$error')),
        );
      } finally {
        if (mounted) setState(() => _submitting = false);
      }
      return;
    }
    await _runAction(context, action, merged);
  }

  @override
  Widget build(BuildContext context) {
    final fields = widget.component.fields;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final field in fields)
          if (field is Map)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: TextField(
                controller: _controllerFor(field['key']?.toString() ?? ''),
                maxLines: field['type'] == 'multiline' ? 3 : 1,
                decoration: InputDecoration(
                  labelText: field['label']?.toString() ?? field['key']?.toString(),
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ),
        FilledButton(
          onPressed: _submitting ? null : _submit,
          child: _submitting
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(widget.component.componentLabel),
        ),
      ],
    );
  }
}

extension on PluginComponentSpec {
  String get componentLabel => this.json['submitText']?.toString() ?? '提交';
}

class _LoadError extends StatelessWidget {
  const _LoadError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(message, style: TextStyle(color: Theme.of(context).colorScheme.error)),
        TextButton(onPressed: onRetry, child: const Text('重试')),
      ],
    );
  }
}

// ─────────────────────────── 动作 ───────────────────────────

Future<void> _runAction(
  BuildContext context,
  PluginActionSpec action,
  Map<String, Object?> params,
) async {
  final scope = PluginRuntimeScope.maybeOf(context);
  switch (action.type) {
    case 'openPage':
      final page = action.page;
      if (page == null) return;
      scope?.openPage(page, <String, Object?>{
        ...params,
        ...{
          for (final entry in action.params.entries)
            entry.key: entry.value is String
                ? interpolateTemplate(entry.value.toString(), params)
                : entry.value,
        },
      });
      return;
    case 'openUrl':
      final url = interpolateTemplate(action.url ?? '', params);
      if (url.isNotEmpty) scope?.openUrl(url);
      return;
    case 'refresh':
      scope?.refresh();
      return;
    case 'submitForm':
      // 无 url 的 submitForm 由表单自身处理。
      return;
  }
}

// ─────────────────────────── HTTP ───────────────────────────

class PluginHttp {
  PluginHttp._();

  static final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 12),
      receiveTimeout: const Duration(seconds: 20),
      responseType: ResponseType.plain,
      validateStatus: (status) => status != null && status >= 200 && status < 300,
    ),
  );

  static const Set<String> _allowedHeaders = <String>{
    'accept',
    'content-type',
    'x-requested-with',
  };

  static Future<List<Map<String, Object?>>> fetch({
    required String url,
    String method = 'GET',
    String? itemsPath,
    Object? headers,
    AuthSession? session,
  }) async {
    final uri = Uri.tryParse(url);
    if (uri == null || !(uri.scheme == 'http' || uri.scheme == 'https')) {
      throw const FormatException('非法的 http(s) 地址');
    }
    final requestHeaders = <String, String>{};
    if (headers is Map) {
      headers.forEach((key, value) {
        if (_allowedHeaders.contains(key.toString().toLowerCase())) {
          requestHeaders[key.toString()] = value.toString();
        }
      });
    }
    if (session != null) {
      final cookie = _cookieForHost(session, uri.host);
      if (cookie.isNotEmpty) requestHeaders['Cookie'] = cookie;
    }
    final response = await _dio.request<String>(
      uri.toString(),
      options: Options(method: method.toUpperCase(), headers: requestHeaders),
    );
    if (response.data != null && response.data!.length > 2 * 1024 * 1024) {
      throw const FormatException('响应超过 2MB');
    }
    final decoded = _decode(response.data);
    final list = _extractList(decoded, itemsPath);
    return <Map<String, Object?>>[
      for (final item in list)
        if (item is Map)
          <String, Object?>{
            for (final entry in item.entries) entry.key.toString(): entry.value,
          },
    ];
  }

  static Future<void> submit({
    required String url,
    String method = 'POST',
    required Map<String, Object?> values,
  }) async {
    await _dio.request<String>(
      url,
      data: values,
      options: Options(method: method.toUpperCase()),
    );
  }

  static String _cookieForHost(AuthSession session, String host) {
    for (final entry in session.cookies.entries) {
      final domain = entry.key.trim();
      if (domain.isEmpty) continue;
      if (host == domain || host.endsWith('.$domain') || domain.endsWith(host)) {
        final value = entry.value.trim();
        if (value.isNotEmpty) return value;
      }
    }
    return '';
  }

  static Object? _decode(Object? data) {
    if (data is String) {
      try {
        return jsonDecode(data);
      } catch (_) {
        return data;
      }
    }
    return data;
  }

  static List<Object?> _extractList(Object? decoded, String? itemsPath) {
    if (itemsPath != null && itemsPath.trim().isNotEmpty) {
      Object? current = decoded;
      for (final key in itemsPath.split('.')) {
        if (current is Map && current.containsKey(key)) {
          current = current[key];
        } else {
          current = null;
          break;
        }
      }
      if (current is List) return current;
    }
    if (decoded is List) return decoded;
    if (decoded is Map) {
      for (final value in decoded.values) {
        if (value is List) return value;
      }
    }
    return const <Object?>[];
  }
}
