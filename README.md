# NEU Better

> 东北大学**非官方**开源校园客户端 —— 一个用 Flutter 编写的本地优先校园工具，Windows 桌面与 Android 手机共用一套代码。

## 简介

NEU Better 在不改变学校既有系统的前提下，把分散的校园入口收拢进一个干净、可读的客户端：一次登录、保持会话、数据只留在本机；课表与寝室用电一屏可达。无自建后端。Windows 用左侧栏 + 内容区（按窗口宽度自适应），Android 用底部导航并锁定竖屏。

## 功能

- **统一身份认证登录**：`pass.neu.edu.cn` 原生 HTTP 登录（`lt/execution` 表单 + RSA 加密）；遇到验证码 / 设备二次验证时可用 WebView 网页登录兜底并回传 Cookie。
- **会话与凭据**：会话 Cookie 加密保存（Windows DPAPI / Android Keystore），重启自动恢复；可选在本机保存账号密码，下次打开自动预填或自动登录。
- **研究生课表**：登录后自动同步并与本地缓存合并；周视图 / 日视图、周次切换、当前时刻线、考试安排；「每周起始日」可选周一或周日。
- **寝室用电**：按楼栋与完整房间码查询缴费大厅电费；完整房间码与「校区 / 楼栋 / 寝室号」双向联动；低于提醒线时提醒（Windows 应用内弹窗，Android 悬浮通知）。
- **设置与外观**：主题（浅色 / 深色 / 跟随系统）、每周起始日；Windows 另有托盘图标与关闭行为。
- **响应式界面**：桌面按窗口宽度在「侧栏」与「手机布局」之间自适应；手机底部导航、锁定竖屏。

## 平台

- Windows 11 x64
- Android 7.0+（API 24+）
- iOS 暂不考虑

## 技术栈

- Flutter 3.47.9 / Dart 3.13.7
- Riverpod（状态）、go_router（路由）、Dio + cookie_jar（网络）
- flutter_secure_storage、Windows DPAPI（本地加密）
- webview_flutter（Android）/ webview_flutter_windows（Windows WebView2）
- local_notifier（Windows 通知）

## 仓库结构

```text
lib/        Flutter 应用源码（app / core / features 分层）
android/    Android 平台工程
windows/    Windows 平台工程
docs/       架构、设计文档
tools/      构建与调试脚本
test/       Dart / Flutter 测试
```

## 文档

- 架构与分层：[docs/architecture.md](docs/architecture.md)
- 设计规范：[docs/design/spec.md](docs/design/spec.md)
- 开发交接（贡献者 / AI）：[AGENTS.md](AGENTS.md)

## 本地开发

仓库使用仓库内的本地工具链目录 `.tools/`（不提交）：

```powershell
.\tools\flutter.cmd pub get
.\tools\flutter.cmd run -d windows          # 桌面
.\tools\flutter.cmd run -d <android-device> # 安卓
```

> `tools/flutter.cmd` 会把 `APPDATA / PUB_CACHE / TEMP / ANDROID_HOME / ANDROID_USER_HOME / GRADLE_USER_HOME` 重定向到 `.tools/`，避免 Flutter 写入用户目录失败。PowerShell 版 `tools/flutter.ps1` 需先 `Set-ExecutionPolicy -Scope Process Bypass`。

### 构建与检查

```powershell
.\tools\flutter.cmd analyze           # 必须 No issues found
.\tools\flutter.cmd test              # 必须全过（当前 35 个）
.\tools\flutter.cmd build windows --release
.\tools\flutter.cmd build apk --release
```

## 设计

默认「A 静蓝」方向：校识蓝为主色，浅色画布 + 白色内容卡，hairline 分隔，朱红只用于考试卡与当前时刻线。完整颜色令牌与组件规范见 [docs/design/spec.md](docs/design/spec.md)。

## 许可证

AGPL-3.0，详见 [LICENSE](LICENSE)。

## 免责声明

本项目为个人 / 社区开源项目，与东北大学官方无关。使用学校账号登录时请遵守学校相关管理规定；项目不会收集、上传或出售账号、课表与用电数据，所有数据仅保存在本机。
