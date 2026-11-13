# NEU Better

> 东北大学**非官方**开源校园客户端 —— 一个用 Flutter 编写的本地优先校园工具，Windows 桌面与 Android 手机共用同一套代码。

当前版本：**0.2.0**　·　最新发布：[GitHub Releases](https://github.com/YYiLiC9/NEU-Better/releases)

## 简介

NEU Better 在不改变学校既有系统的前提下，把分散的校园入口收拢进一个干净、可读的客户端：一次登录、保持会话、数据只留在本机；课表、寝室用电、e码通一屏可达。无自建后端，不上传任何个人数据。

- **桌面（Windows）**：左侧栏 + 内容区，按窗口宽度自适应；支持托盘、开机自启动。
- **手机（Android）**：底部导航（课表 / 寝室用电 / e码通 / 设置），锁定竖屏，支持桌面小部件与系统悬浮通知。

## 功能

### 登录与账号
- 统一身份认证（`pass.neu.edu.cn`）原生 HTTP 登录：`lt/execution` 表单 + RSA 加密。
- 遇到验证码 / 设备二次验证时，可用 WebView 网页登录兜底并回传 Cookie。
- 会话 Cookie 加密保存（Windows DPAPI / Android Keystore），重启自动恢复。
- 可选在本机保存账号密码，下次打开自动登录 / 预填。

### 课表
- 登录后自动同步研究生课表，与本地缓存合并；无缓存时不再显示示例课表，而是「暂无课表数据 / 正在同步」，并自动拉取。
- 周视图 / 日视图、周次切换、当前时刻线、考试安排；「每周起始日」可选周一或周日；周/日视图与所在周会持久化。
- 课程标签重排：名称加粗最大、地点次行，考试卡显示地点与起止时间。
- 点击课程弹出详情（地点、教师、周次、时间等），可添加**课程备注**，已备注课程右上角显示小圆点。
- **课表格子增 / 改 / 删**：长按（手机）或右键（电脑）空白格新增、已有课程打开详情编辑；表单含周次、名称、地点、老师、起止课时，实时冲突检测（含考试），支持「所有周 / 仅本周」删除；同步后本地修改仍保留，设置中可一键清除。
- 同步考试偶发缺失问题已修复：考试接口在部分后端节点不可用时自动重新登录换节点重试，并兼容「待排考」等不同返回结构。

### 寝室用电
- 按楼栋 + 完整房间码查询缴费大厅电费；完整房间码与「校区 / 楼栋 / 寝室号」双向联动。
- 每日自动检查一次；低于提醒线时提醒（Windows 应用内弹窗 / Android 系统悬浮通知，点击跳转用电页）。

### e码通
- 校园动态二维码（打开学校官方 H5 并自动 SSO），登录后后台预热 WebView，点开即显示。
- 轻点二维码刷新；识别失败有超时与「重新加载」兜底，不长时间白屏。

### 设置
- 主题（浅色 / 深色 / 跟随系统）。
- 每周起始日（周一 / 周日）。
- 自动更新开关（从 GitHub Release 检查并安装）。
- 清除课表修改（保留备注）。
- Windows 专属：任务栏托盘图标、关闭窗口最小化到托盘、开机自启动。

### Windows 桌面
- 托盘右键「显示 / 退出」；关闭行为可配置。
- 任务栏 / 窗口图标、应用图标（山峰·水波品牌图）。

## 平台

- Windows 11 x64
- Android 7.0+（API 24+）
- iOS 暂不考虑

## 技术栈

- Flutter 3.47.9 / Dart 3.13.7
- Riverpod（状态管理）、Dio + cookie_jar（网络）
- flutter_secure_storage、Windows DPAPI（本地加密）
- webview_flutter（Android）、webview_flutter_windows（Windows WebView2）
- local_notifier（Windows 通知）
- win32 / 自写原生通道（托盘、窗口、开机启动、Android 桌面小部件）

## 仓库结构

```text
lib/
  app/            应用壳与主题（app.dart、theme/）
  core/           与业务无关的基础能力
    auth/         登录态、凭据、会话、身份
    crypto/       RSA 加密
    electricity/  用电领域模型（楼栋编码表）
    network/      CAS / 教务 / 电费 / 身份 客户端
    platform/     Windows 窗口通道、开机自启动
    settings/     应用设置与持久化
    storage/      Windows DPAPI 文件
    update/       自动更新（GitHub Release）
  features/
    auth/         登录页、WebView 登录、登录状态机
    home/         主界面（桌面侧栏 / 手机底部导航）
    timetable/    课表（周/日视图、同步、增改删、备注、小部件推送）
    dorm/         寝室用电
    ecode/        e码通
    settings/     设置
    landing/      M0 过场
  main.dart       入口
android/          Android 平台工程（含小部件、通知原生代码）
windows/          Windows 平台工程
docs/             架构与设计文档
tools/            构建与调试脚本
test/             Dart / Flutter 测试
```

## 文档

- 架构与分层：[docs/architecture.md](docs/architecture.md)
- 设计规范：[docs/design/spec.md](docs/design/spec.md)

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
.\tools\flutter.cmd analyze                 # 必须 No issues found
.\tools\flutter.cmd test                    # 必须全过（当前 58 个）
.\tools\flutter.cmd build windows --release # 产物 build\windows\x64\runner\Release\neu_better_pro.exe
.\tools\flutter.cmd build apk --release     # 产物 build\app\outputs\flutter-apk\app-release.apk
```

## 数据存储

所有数据只保存在本机，不上传服务器（学校接口通信除外）。运行时数据写入 exe 同目录 `data\`（找不到时依次回退 `cwd\data`、临时目录、`LOCALAPPDATA`）：

- `settings.json` 应用设置
- `session.dat` / `credentials.dat` 加密会话与账号
- `timetable.json` 课表快照
- `course_notes.json` / `course_overrides.json` 课程备注与本地修改
- `electricity.json` 用电偏好与最近读数

Android 端持久数据写入应用私有 `files` 目录（覆盖安装不丢失）。

## 设计

默认「A 静蓝」方向：校识蓝为主色，浅色画布 + 白色内容卡，hairline 分隔，朱红只用于考试卡与当前时刻线。完整颜色令牌与组件规范见 [docs/design/spec.md](docs/design/spec.md)。

## 已知限制

- **Windows 托盘图标**：极少数环境（如仓库目录树或第三方安全软件拦截）会导致 `Shell_NotifyIcon` 注册失败；换到安装目录 / 普通目录通常正常。
- **考试数据依赖学校排考**：某学期尚未排考、或考试接口在个别后端节点不可用时可能暂时取不到，已做自动重登换节点与缓存兜底。
- 需要校园网或学校 VPN 才能访问教务 / 缴费 / e码通等校内服务。
- Android 桌面小部件在不同厂商启动器（Launcher）上的尺寸换算存在差异，实际以手机桌面为准。

## 许可证

AGPL-3.0，详见 [LICENSE](LICENSE)。

## 免责声明

本项目为个人 / 社区开源项目，与东北大学官方无关。使用学校账号登录时请遵守学校相关管理规定；项目不会收集、上传或出售账号、课表、用电等数据，所有数据仅保存在本机。
