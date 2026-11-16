/// 本次进程是否由 Windows 开机自启动拉起（Run 项命令带 `--startup`）。
///
/// 由 `lib/main.dart` 在 `main(List<String> args)` 里赋值，供根组件判断
/// 是否需要“开机启动时自动最小化到托盘”。
bool launchedFromWindowsStartup = false;
