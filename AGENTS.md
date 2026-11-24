# AGENTS.md — 给后续 AI 代理的项目交接

**先读这份再改代码。** 面向人类的功能介绍见 [README.md](README.md)，分层规则见 [docs/architecture.md](docs/architecture.md)。

## 项目一句话
东北大学非官方校园客户端，Flutter（Windows + Android，Android 锁竖屏），本地优先、无自建后端。主要模块：课表、寝室用电/网费、e码通、邮件、校园通知、首页卡片与插件、校园网连接。

## 构建与检查（每次改完必须全绿）
```powershell
.\tools\flutter.cmd analyze                 # 必须 No issues found
.\tools\flutter.cmd test                    # 必须全过
.\tools\flutter.cmd build windows --release # build\windows\x64\runner\Release\NEUBetterPro.exe
.\tools\flutter.cmd build apk --release     # build\app\outputs\flutter-apk\app-release.apk
```
- 统一用 `tools\flutter.cmd`（会重定向 APPDATA/PUB_CACHE/TEMP/ANDROID_HOME 等到 `.tools/`）。
- Windows 构建若报 `WebView2Loader.dll 被占用`：`Stop-Process -Name NEUBetterPro` 后重建。
- runner 的 C++ 源文件只能写纯 ASCII（MSVC 按 GBK 读，中文注释会 C4819 + /WX 失败）。

## 插件目录（固定 master）
- 插件目录固定读取 GitHub 仓库 `YYiLiC9/NEU-Better` 的 **master** 分支 `plugins/index.json`（失败走 `ghfast.top` / `gh-proxy.com` 镜像）。
- 缓存为 `plugins_catalog.json`；拉取失败依次回退缓存 → 随包 `assets/plugins/index.json`。
- 功能分支里的 `plugins/index.json` 改动**不会**自动生效，必须先合并进 master 并发版。
- 插件清单 `enabled`：`0` 表示禁用/不上架/不可下载，缺省按 `1`。字段说明见 [plugins/README.md](plugins/README.md)。

## 其它约定
- 提交信息用中文、动词开头（如 `feat: ...`、`fix: ...`）。
- 数据只写本机 `data/`（按账号隔离见 `lib/core/storage/account_scope.dart`）。
- Android 测试机：`adb -P 5070 connect 127.0.0.1:16416`（MuMu test 实例）。
