# NEU Better 首页插件目录

本目录存放「首页插件化 V1」的插件目录与说明。App 的卡片库从 dev 分支的
`plugins/index.json` 拉取目录（失败走 ghfast.top / gh-proxy.com 镜像，并缓存到
本地 `plugins_catalog.json`）。插件页由 App 用**原生 DSL 渲染，不使用 WebView**。

## 目录结构

```json
{
  "version": 1,
  "plugins": [ { "id": "library", "name": "图书馆", "...": "..." } ]
}
```

- `version`：目录格式版本（当前 1）。
- `plugins[]`：插件清单数组，每项见下。

## 插件清单字段

| 字段 | 必填 | 说明 |
| --- | --- | --- |
| `id` | 是 | 插件唯一 id，仅允许 `[a-z0-9_-]+`。 |
| `name` | 是 | 显示名称。 |
| `description` | 否 | 一句话简述（卡片库/2×2 卡片副标题）。 |
| `version` | 是 | 插件版本（用于更新判断）。 |
| `minAppVersion` | 否 | 兼容的 App 最低版本。 |
| `rendererVersion` | 是 | DSL 渲染器版本；高于 App 支持版本时禁用（提示「需更新App」）。 |
| `enabled` | 否 | 远程插件开关：`0` 表示禁用（不上架、不可下载、插件库不显示）；`1` 表示正常可用。缺省按 `1` 处理。 |
| `icon` | 否 | `{ "type": "material", "value": "menu_book" }`。 |
| `card` | 否 | `{ "title": "...", "subtitle": "..." }` 首页卡片文案。 |
| `startPage` | 是 | 入口页 id，必须存在于 `pages`。 |
| `pages` | 是 | `{ pageId: { title, body: [组件...] } }`。 |

## DSL V1 组件

- `list`：`{ "data": 数据源, "item": { "title": "{{field}}", "subtitle": "...", "image": "...", "onTap": 动作 } }`
- `text` / `richText`：`{ "value": "...", "style": "title|body|caption" }`
- `image`：`{ "url": "https://..." }`（网络图，带占位）
- `card`：`{ "title": "...", "body": "..." }`
- `section`：`{ "title": "..." }`
- `divider` / `spacer`：`divider`；`spacer` 可带 `height`
- `button`：`{ "text": "...", "action": 动作 }`
- `form`：`{ "fields": [{ "key": "...", "label": "...", "type": "text|multiline" }], "action": 动作 }`

### 数据源

- `static`：`{ "type": "static", "items": [ { ... } ] }`
- `httpJson`：`{ "type": "httpJson", "url": "https://...", "method": "GET|POST", "itemsPath": "data.list", "headers": { "Accept": "application/json" }, "useSessionCookies": true }`
  - 仅允许 GET/POST；响应上限 2MB；`headers` 只接受 `Accept` / `Content-Type` / `X-Requested-With`；
    `useSessionCookies=true` 时注入 `.neu.edu.cn` 会话 Cookie。

### 模板

`{{field}}` 只做字符串替换（支持 `a.b` 取嵌套键），**不执行表达式或脚本**。

### 动作

- `openPage`：`{ "type": "openPage", "page": "detail", "params": { "id": "{{id}}" } }`
- `openUrl`：`{ "type": "openUrl", "url": "https://..." }`（系统/内嵌浏览器打开）
- `refresh`：`{ "type": "refresh" }`
- `submitForm`：`{ "type": "submitForm", "url": "https://...", "method": "POST" }`

## 版本与安全

- `enabled` 为整数开关：`0` = 禁用（App 插件库不显示、禁止下载），`1` = 正常可用；
  新增插件默认 `enabled: 1`，需要下架时改为 `0`（**不要删除条目**，便于以后恢复）。
- `rendererVersion` 大于 App 支持值时，卡片库显示「需更新App」并禁用。
- 非法 manifest / 重复 id / 非 http(s) URL / 响应过大都会被跳过或报错，不写入登记。
- 所有页面为原生组件渲染，无 WebView、无脚本执行。

## 延期到 renderer v2

分页/下拉刷新、图片上传、评论、点赞、WebSocket、动画、WebView。
