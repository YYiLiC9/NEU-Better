# NEU Better 架构说明

这份文档描述项目的分层与依赖边界。目标是让功能继续增长时，页面、业务编排、平台能力各自有明确位置，同时不改变现有行为。

## 分层

```text
lib/
  main.dart                 应用入口：ProviderScope + Windows 通知初始化
  app/                      应用壳：主题、MaterialApp、页面分流入口
  core/                     跨 feature 的纯能力与协议模型
    auth/                   登录会话、凭据、身份模型、会话存储
    crypto/                 CAS 密码加密
    electricity/            电费领域模型（楼栋表、房间码、读数、偏好）
    network/                CAS、身份解析、服务登录、电费/课表客户端
    platform/               Windows 原生能力接口（窗口、托盘、任务栏标题）
    settings/               本机设置模型与持久化
    storage/                Windows DPAPI 文件原语
  features/                 面向用户的功能模块
    auth/                   登录页、WebView 登录、登录状态机
    home/                   主界面外壳、导航、状态栏
    timetable/              课表模型、解析、同步、周/日视图
    dorm/                   寝室用电页与用电编排
    settings/               设置弹窗
    landing/                启动过场
```

依赖方向固定为：

```text
features/*  →  core/*
features/*  →  app/theme（只取设计令牌）
core/*      ✗→  features/*（core 不得反向依赖 UI feature）
```

`core/electricity/electricity_models.dart` 是电费领域模型，供
`core/network/neu_elec_client.dart` 与 `features/dorm/*` 共同使用；不要把该模型再放回 UI feature 内。

## 页面与组件

- 页面只负责“状态 + 编排 + 布局入口”；大块展示组件放到同 feature 的 `widgets/` 下。
- 课表页已拆为 `timetable_page.dart` + `widgets/timetable_{chrome,week_grid,exam_widgets,day_agenda}.dart`，并使用 `part` 文件共享私有组件。
- 登录页、设置弹窗、寝室页、WebView 登录页采用同样的 `part` 方式拆分展示组件。
- `part` 文件里的私有组件仍属于原页面库，不能反向被其他库导入。

## 业务编排

- 纯计算放在无副作用的类中，例如 `features/timetable/timetable_schedule.dart`（`TimetableSchedule`）。
- 需要网络/持久化的操作放在 service 中，例如 `DormElectricityService`、`TimetableSyncService`。
- 页面通过 Riverpod provider 获取状态机或控制器，不直接在 UI 里复制业务规则。

## 网络与认证

- CAS 登录、会话 cookie、按 service 换票统一由 `core/network/` 承担。
- `NeuServiceSession` 只负责用已保存的 CAS 会话换取目标域 cookies，不持有页面状态。
- 电费、课表、身份解析分别由独立 client 处理；请求失败时向外抛业务异常，页面只负责展示。

## 持久化

- 运行时数据写到 exe 同目录的 `data/`，失败时依次回退到 cwd、临时目录、LOCALAPPDATA。
- Windows 凭据/会话文件通过 DPAPI 加密；不要绕过 `SecureCredentialStore` / `SecureSessionStore` 直接写明文。
- 设置和电费偏好使用 JSON 文件，读取失败必须回退到默认值，不能让页面无法启动。

## Windows 平台边界

- `lib/core/platform/windows_window.dart` 是 Dart 侧唯一窗口能力入口。
- 托盘、关闭行为、任务栏标题由 `windows/runner/flutter_window.cpp` 的 `neu_better/window` MethodChannel 实现。
- 平台相关代码不可泄漏到 feature 页面；页面只调用 `WindowsWindow` / `AppSettings` 接口。

## 验证

任何结构调整都必须保持：

```text
./tools/flutter.cmd analyze   → No issues found!
./tools/flutter.cmd test      → 全过
./tools/flutter.cmd build windows --release
```

结构调整只做“移动/拆分/提取”，不改变用户可见行为；提交时写中文、动词开头的说明。
