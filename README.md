# NEU Better

东北大学校园客户端（非官方，开源）。目标是用一套 Flutter 代码库覆盖 Windows 与 Android，先解决登录与课表，再逐步扩展其他校园功能。

> 当前阶段：**M1 登录与持久会话已完成**。M0 工程底座与 A 静蓝设计方向已完成；M2 课表待开始。

## 为什么做

学校现有系统入口分散、Web 端体验割裂。NEU Better 希望在不改变学校系统的前提下，提供：

- 一次登录、保持会话；
- 干净、可读的周课表；
- 多端一致的界面与操作逻辑；
- 本地优先、可导入导出、无自建后端。

## 当前能力

- 统一身份认证（pass.neu.edu.cn）原生 HTTP 登录，支持 `lt/execution` 表单与 RSA 加密；
- 登录会话本地加密保存（`flutter_secure_storage`），重启后自动恢复；
- 可勾选在本机安全保存账号密码，下次打开登录页自动预填；
- 遇到验证码 / 设备二次验证时，提供 WebView 网页登录兜底，并回传 Cookie；
- 网页登录不要求预先填写学号，登录后从会话/CAS 页面识别学号或姓名；
- Windows 双栏登录页 / Android 移动端 Hero + 浮层表单，统一 A 静蓝视觉；
- 登录成功后的 M1 状态主页，为 M2 课表预留入口。

## 平台

- Windows 11 x64
- Android 7.0+（API 24+）
- iOS 后续版本再考虑

## 技术栈

- Flutter 3.47.9 / Dart 3.13.7
- Riverpod、go_router、Dio + CookieJar
- Drift（SQLite）、flutter_secure_storage
- webview_flutter（Android WebView） / webview_flutter_windows（Windows WebView2）
- Windows 系统字体：Microsoft YaHei UI

## 仓库结构

```text
lib/                 Flutter 应用源码
android/              Android 平台工程
windows/              Windows 平台工程
docs/                 架构、接口、设计与构建文档
packaging/            Windows 安装包脚本
tools/                辅助脚本
```

## 本地开发

### 1. 准备工具链

仓库使用本地工具链目录 `.tools/`（不提交）：

```powershell
# Flutter 3.47.9
# https://storage.googleapis.com/flutter_infra_release/releases/stable/windows/flutter_windows_3.47.9-stable.zip

# Android command-line tools
# https://dl.google.com/android/repository/commandlinetools-win-16111833_latest.zip
```

### 2. 安装依赖并运行

```powershell
.\tools\flutter.cmd pub get
.\tools\flutter.cmd run -d windows
```

> `tools/flutter.cmd` 会把 `APPDATA`、`PUB_CACHE`、`TEMP`、`ANDROID_HOME`、`ANDROID_USER_HOME`、`GRADLE_USER_HOME` 指向仓库内的 `.tools/`，避免 Flutter 写入用户目录失败。PowerShell 版 `tools/flutter.ps1` 需要 `Set-ExecutionPolicy -Scope Process Bypass`。

### 3. 检查

```powershell
.\tools\flutter.cmd analyze
.\tools\flutter.cmd test
.\tools\flutter.cmd build windows --release
.\tools\flutter.cmd build apk --debug
```

M1 已验证：

- `flutter analyze`：No issues found
- `flutter test`：10 个测试通过
- Windows release：`build\windows\x64\runner\Release\neu_better_pro.exe`
- Android debug APK：`build\app\outputs\flutter-apk\app-debug.apk`

## 设计

已选定 **A 静蓝** 作为默认方向，B 流光 / C 纸感保留为后续可选主题。设计令牌与组件规范见 [`docs/design/spec.md`](docs/design/spec.md)；三套概念稿位于 `docs/design/concepts/`。

## 许可证

AGPL-3.0。详见 [LICENSE](LICENSE)。

## 免责声明

本项目为个人/社区开源项目，与东北大学官方无关。使用学校账号登录时，请遵守学校相关管理规定；项目不会收集、上传或出售账号与课表数据。
