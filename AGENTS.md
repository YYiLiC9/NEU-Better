# AGENTS.md — NEU Better 项目交接手册

写给继续开发本项目的 AI 智能体：读完这一份即可上手改代码。面向人类的介绍见 [README.md](README.md)，设计规范见 [docs/design/spec.md](docs/design/spec.md)。

## 项目一句话

东北大学非官方校园客户端，Flutter 3.47.9（Dart 3.13.7），目标平台 Windows + Android（iOS 暂缓）。本地优先、无自建后端、A 静蓝视觉。当前状态：**登录、课表+同步、寝室用电、设置、Windows 托盘与通知、Android 端（竖屏 / 底部导航 / 课表完整显示 / 悬浮通知）均已完成**（dev 分支）。

## 构建与验证（每次改完必须全绿再提交）

```powershell
.\tools\flutter.cmd analyze     # 必须 No issues found
.\tools\flutter.cmd test        # 必须 35 个全过
.\tools\flutter.cmd build windows --debug   # 或 --release
```

- `tools/flutter.cmd` 会把 `APPDATA/PUB_CACHE/TEMP/ANDROID_HOME/GRADLE_USER_HOME` 等重定向到仓库内 `.tools/`（不提交），避免写用户目录失败。**始终用它调用 flutter**。
- Windows 构建失败 `MSB3021/MSB3027 WebView2Loader.dll 被占用` = 应用还在运行，先 `Stop-Process -Name neu_better_pro` 再构建。
- 构建/启动前若旧实例占用端口或文件，先停进程；不要并行跑两个 flutter 命令（build 目录冲突）。
- 产出：Debug `build\windows\x64\runner\Debug\neu_better_pro.exe`；Release `build\windows\x64\runner\Release\neu_better_pro.exe`。

## 工作纪律

- 多步任务先写 todo，完成一项立刻标 completed；关键节点 1–2 行播报。
- 提交信息用中文、动词开头（如 `feat: 界面设计统一与寝室用电查询`）。
- 探查网络接口用的临时脚本/抓包文件（`.elec_*`、`.shot_*`、`test/probe_*.dart` 等）**用完必须删干净再提交**，不要进 git。
- 本地开发用的账号文件（如 `账号.txt`）**已被 .gitignore，绝不提交**；`git log` 里也不应出现。
- UI 改动要用构建后的真实窗口截图验证（PrintWindow），不要只看代码就说「应该没问题」。
- 临时驱动 UI 时不要靠模拟点击（DPI 偏移不可靠），可直接改状态重建再还原。

## 架构地图（lib/）

完整的依赖边界与分层规则见 [docs/architecture.md](docs/architecture.md)。核心约束：`features/*` 可以依赖 `core/*`，但 `core/*` 不得反向依赖任何 feature。

```text
lib/
  main.dart                     入口：ProviderScope；本地通知在首帧后初始化(仅 Windows)
  app/app.dart                  NeuBetterApp 根组件、主题模式、页面分流
  app/theme/app_theme.dart      全部设计令牌（见下节），唯一取色处
  core/
    auth/credential_store.dart      SecureCredentialStore：账号密码 DPAPI 加密存取
    auth/session_store.dart         SecureSessionStore：会话 Cookie 加密存取
    auth/saved_credentials.dart     保存的账号密码模型
    auth/student_identity.dart      姓名/学号身份模型
    auth/auth_exception.dart        AuthException 等异常类型
    auth/webview_login_result.dart  WebView 登录结果模型
    electricity/electricity_models.dart 电费领域模型：楼栋表/房间码/读数/DormPrefs
    storage/windows_dpapi_file.dart Windows DPAPI 文件加解密原语
    network/neu_cas_client.dart  统一身份认证 CAS 登录核心（详见下文数据流）
    network/neu_elec_client.dart 缴费大厅电费查询客户端
    network/neu_service_session.dart 用 CAS 会话换取目标服务 cookies
    network/yjs_timetable_client.dart 研究生课表/考试抓取客户端
    network/portal_identity_client.dart / cas_identity_client.dart / windows_portal_identity_client.dart  身份解析辅助
    crypto/rsa_encryptor.dart    CAS 密码 RSA(PKCS1) 加密，公钥常量
    settings/app_settings.dart   主题/托盘偏好 + settings.json 持久化
    platform/windows_window.dart MethodChannel：任务栏标题/关闭行为/托盘显隐
  features/
    auth/login_page.dart         登录页外壳（状态与动作）；widgets/login_widgets.dart 为品牌/表单组件
    auth/webview_login_page.dart WebView 登录分发；widgets/webview_login_{android,windows,widgets}.dart 为平台页与共用脚手架
    auth/auth_gate.dart          登录态分流（未登录→登录页）
    auth/auth_controller.dart    Riverpod 登录状态机 + 会话恢复/身份刷新
    landing/m0_landing_page.dart M0 过场页
    home/home_page.dart          桌面侧栏 + 页面切换 + 每日电费检查入口（widgets/home_chrome.dart 为品牌/导航/账号块）
    timetable/timetable_page.dart      课表页控制器与外壳（状态、加载、周切换、摘要）
    timetable/widgets/timetable_chrome.dart     工具栏：周步进、周/日视图切换、周分页动画
    timetable/widgets/timetable_week_grid.dart  周网格、时间轴、午/晚休带、课程卡、单日列
    timetable/widgets/timetable_exam_widgets.dart 考试卡、考试安排列表与筛选
    timetable/widgets/timetable_day_agenda.dart 日视图议程与日卡片
    timetable/timetable_schedule.dart  纯领域计算：周起点/当前周/周考试/下一节课
    timetable/yjs_timetable_page.dart  研究生课表同步页
    timetable/timetable_import.dart    教务 HTML → TimetableData 解析
    timetable/timetable_store.dart     timetable.json 持久化
    timetable/timetable_models.dart    CourseSession/TimetableData/PeriodTimes
    timetable/timetable_sync.dart      TimetableSyncService：登录后自动同步课表
    dorm/dorm_page.dart          寝室用电页外壳（状态/加载/查询入口）
    dorm/widgets/dorm_cards.dart 寝室页的读数卡、设置卡、错误条、阈值步进器
    dorm/electricity_service.dart 查询编排 + 每日一次 + dormPrefsChanged 通知
    dorm/electricity_store.dart   electricity.json 持久化
    settings/settings_page.dart  设置弹窗外壳（showSettingsDialog 居中小窗）
    settings/widgets/settings_widgets.dart 设置页的主题选择/开关/小节组件
test/widget_test.dart            23 个测试（界面、解析器、存储、凭据往返等）
test/timetable_data_test.dart    12 个课表解析/领域计算测试
tools/flutter.cmd                唯一 flutter 入口
```

## 数据流要点

### CAS 登录（neu_cas_client.dart）
`NeuCasClient.login(username, password, service?)`：GET 门户 → `/tpass/login?service=…` 抽 `lt/execution` → RSA 加密 → POST → 逐跳手动跟随重定向并吸收 Set-Cookie（`followRedirects:false`）。返回 `CasLoginResult{cookies(按 host 分组), finalUri, serviceTicket}`。
**坑**：对自引用 CAS filter 的服务（如 `https://pay.neu.edu.cn/drCasLogin`），login 可能在最后一个 302 停住，必须**自己再 GET finalUri 跟随到 `/openPortal` 200** 才能调业务接口，否则拿到 200 空响应。

### 课表同步（yjs_timetable_client.dart）
研究生系统：CAS(service=研究生门户) → getUserInfo.do → changeAppRole_yjs.do → getCanVisitAppList.do → wdkbapp 列表 → POST `xspkjgcx.do`（`XNXQDM=20261`）→ 解析行（KCMC/XQJ/KSJC/JSJC/ZCMC/SKJS/SKDD/周次）→ `TimetableData`。当前周从欢迎词「第N周」正则取。

### 电费查询（neu_elec_client.dart）
缴费大厅 `https://pay.neu.edu.cn/`：CAS(service=`…/drCasLogin`) → 手动跟到 `/openPortal` → POST `/queryRommInfo`（form：`elecroomno=<7-8位房间码>&factorycode=E039`）→ JSON `{elecroominfo, elecRemain("148 度"), mAddr, lastReadTime, returncode}`。房间码 = 楼栋缴费编号(3位,空调楼4位)+寝室号(4位补零)，全表在 `core/electricity/electricity_models.dart` 的 `dormCampusNames`。每日一次逻辑在 `electricity_service.dart dailyCheck()`，由 `home_page.dart` 启动后触发；低于提醒线 → Windows toast（尽力而为）+ AlertDialog。

## 持久化文件（exe 同目录 data\，找不到再依次退到 cwd\data、systemTemp\NEU Better、LOCALAPPDATA\NEU Better）

| 文件 | 内容 |
| --- | --- |
| `credentials.dat` | 加密账号密码（DPAPI）。**注意**：会话恢复后的身份刷新必须 `saveCredentials: true`，否则每次启动都会清掉密码文件（auth_controller.dart 已修，勿回退） |
| `session.dat` | 加密会话 Cookie，启动自动恢复登录 |
| `timetable.json` | 课表快照（sessions/termName/currentWeek/termStartDate） |
| `electricity.json` | `{roomCode, alertThreshold, lastQueryDate, lastReading{...}}` |

## 设计系统（app_theme.dart，改样式先看这里）

- 底 `canvas 0xFFF6F8FB`、字 `ink 0xFF14243B`、次级 `muted 0xFF5D7392`、线 `line 0xFFD9E2EE`、主色静蓝 `campusBlue 0xFF0B4F9C`、强调红 `nowRed 0xFFC2402A`（只用于考试卡与当前时刻线）。
- 课程卡配色：`AppColors.pigmentFor(name)` 从 6 组传统色（靛蓝/竹青/赭石/绛紫/砖红/黛青，淡底+深字）取，配 3px 左边条、r8、hairline 边框、不用阴影。
- 组件规范：hairline 1px 分隔替代阴影；工具栏统一 h36；数字用 `FontFeature.tabularFigures`；「朱红当前时刻线」是课表页的记忆点（今日列 + 上下课时间段内 2px 红线+圆点）。
- 动效只响应用户操作：周切换 280ms 滑动、视图切换 160-200ms、无环境动画。

## Windows 平台坑（windows/runner/main.cpp 已配好，勿删）

机器上有多个虚拟显示适配器（向日葵/ToDesk/MuMu/GameViewer），DXGI 把它们排在前面 → Flutter 交换链建到虚拟适配器上 → **窗口白屏**。`main.cpp` 里 `project.set_gpu_preference(flutter::GpuPreference::HighPerformancePreference)` 强制独显是修复手段，删掉必复现白屏。截图验证用 PrintWindow（`PW_RENDERFULLCONTENT`）而非 CopyFromScreen。

## 已知问题 / 后续路线

- **托盘图标在本仓库目录树下无法注册**：`Shell_NotifyIconW(NIM_ADD)` 对仓库目录树下的 exe 一律返回失败（同一份 exe 复制到 Temp/D 盘其他目录即成功，explorer 启动也一样失败，注册表 `NotifyIconSettings` 不建项）。已排除：图标句柄、uID 冲突、flags、manifest DPI、SRP/AppLocker（均为空）。疑似第三方安全软件针对该目录的规则，机器环境问题、非代码问题——把 exe 复制到仓库外运行托盘即正常。
- Windows toast 通知：本机 WinToast AUMI 快捷方式注册失败（`Error while attaching the AUMID...`），toast 发不出；应用内弹窗是主提醒通道，不受影响。后续可研究开机后重试注册或换 flutter_local_notifications。
- 侧栏「通知」「邮件」是占位（后续），点击无动作。
- 寝室用电早期仅在 Windows 实测；Android 端 DPAPI / Keystore 路径与 UI 响应式需持续回归。
- 课表页无开学日期数据时会从「当前周」反推学期起点（`_inferTermStartFromCurrentWeek`），教务未提供时是合理近似。
