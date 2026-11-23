import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'campus_wifi.dart';

class WindowsWifiException extends CampusWifiException {
  const WindowsWifiException(super.message);
}

class WindowsWifi implements CampusWifi {
  WindowsWifi({Future<ProcessResult> Function(List<String>)? run})
    : _run = run == null ? _runNetsh : ((args, _) => run(args));

  static const _securedMessage = '该 Wi-Fi 需要密码。请先在 Windows 的 Wi-Fi 设置中连接一次。';
  static const _commandTimeout = Duration(seconds: 5);
  final Future<ProcessResult> Function(List<String>, Duration) _run;

  static bool isValidSsid(String ssid) =>
      ssid.trim().isNotEmpty &&
      utf8.encode(ssid).length <= 32 &&
      !RegExp(r'[\x00-\x1f\x7f"]').hasMatch(ssid);

  @override
  Future<String?> currentSsid({String? preferred}) async {
    final radios = _interfaces(await _command(['show', 'interfaces']));
    final connected = radios.map((radio) => radio.ssid).whereType<String>();
    return preferred != null && connected.contains(preferred)
        ? preferred
        : connected.firstOrNull;
  }

  @override
  Future<String?> ipv4Address(String ssid) async {
    final radios = _interfaces(await _command(['show', 'interfaces']));
    final radio = radios.where((radio) => radio.ssid == ssid).firstOrNull;
    if (radio == null) return null;
    final config = await _command([
      'interface',
      'ipv4',
      'show',
      'addresses',
      'name=${radio.name}',
    ]);
    if (config.exitCode != 0) {
      throw const WindowsWifiException('无法读取 Wi-Fi 网卡的 IPv4 地址。');
    }
    final addresses = RegExp(
      r'^[ \t]*(?:IP Address|IP 地址|IP 位址)[ \t]*[:：][ \t]*([0-9.]+)',
      caseSensitive: false,
      multiLine: true,
    ).allMatches(_output(config));
    for (final match in addresses) {
      final address = InternetAddress.tryParse(match.group(1)!);
      if (address != null &&
          address.type == InternetAddressType.IPv4 &&
          !address.isLoopback &&
          !address.isLinkLocal &&
          address.address != '0.0.0.0') {
        return address.address;
      }
    }
    return null;
  }

  Future<void> connect(String ssid) async {
    if (!isValidSsid(ssid)) {
      throw const WindowsWifiException('请输入有效的 Wi-Fi 名称（最多 32 字节）。');
    }
    final clock = Stopwatch()..start();
    const timeout = Duration(seconds: 15);
    final timedOut = WindowsWifiException(
      '连接 Wi-Fi「$ssid」超时。请检查网络信号，若需要密码请先在 Windows 中连接一次。',
    );
    Future<ProcessResult> command(List<String> args) {
      final remaining = timeout - clock.elapsed;
      if (remaining <= Duration.zero) throw timedOut;
      return _command(args, remaining: remaining, deadlineError: timedOut);
    }

    final radios = _interfaces(await command(['show', 'interfaces']));
    if (radios.any((radio) => radio.ssid == ssid)) return;
    final available = radios.where((radio) => !radio.off).toList();
    if (available.isEmpty) {
      throw const WindowsWifiException('Wi-Fi 无线电已关闭，请打开 Wi-Fi 或关闭飞行模式。');
    }

    String? interface;
    for (final radio in available) {
      final profile = await command([
        'show',
        'profile',
        'name=$ssid',
        'interface=${radio.name}',
      ]);
      if (profile.exitCode == 0) {
        interface = radio.name;
        break;
      }
      if (!RegExp(
        r'not found|不存在|找不到|未找到|没有[^\r\n]*找到',
        caseSensitive: false,
      ).hasMatch(_output(profile))) {
        throw const WindowsWifiException('无法读取 Windows Wi-Fi 配置。');
      }
    }
    if (interface == null) {
      var secured = false;
      for (final radio in available) {
        final scan = await command([
          'show',
          'networks',
          'interface=${radio.name}',
        ]);
        if (scan.exitCode != 0) {
          throw const WindowsWifiException('Windows 未能列出附近的 Wi-Fi。');
        }
        final open = _visibleSecurity(_output(scan), ssid);
        if (open == null) continue;
        if (!open) {
          secured = true;
          continue;
        }
        await _addOpenProfile(ssid, radio.name, command);
        interface = radio.name;
        break;
      }
      if (interface == null) {
        if (secured) throw const WindowsWifiException(_securedMessage);
        throw WindowsWifiException('找不到 Wi-Fi「$ssid」。请确认网络名称和信号覆盖。');
      }
    }

    final result = await command([
      'connect',
      'name=$ssid',
      'ssid=$ssid',
      'interface=$interface',
    ]);
    if (result.exitCode != 0) {
      final message = _output(result);
      if (RegExp(
        r'key|password|credential|密钥|密碼|密码|凭据',
        caseSensitive: false,
      ).hasMatch(message)) {
        throw const WindowsWifiException(_securedMessage);
      }
      if (RegExp(
        r'not available|not found|网络不可用|不在范围|找不到',
        caseSensitive: false,
      ).hasMatch(message)) {
        throw WindowsWifiException('找不到 Wi-Fi「$ssid」。请确认网络名称和信号覆盖。');
      }
      throw WindowsWifiException('Windows 无法连接 Wi-Fi「$ssid」。请确认网络可用。');
    }

    while (clock.elapsed < timeout) {
      final current = _interfaces(await command(['show', 'interfaces']));
      if (current.any((radio) => radio.ssid == ssid)) return;
      if (current.every((radio) => radio.off)) {
        throw const WindowsWifiException('Wi-Fi 无线电已关闭，请打开 Wi-Fi 或关闭飞行模式。');
      }
      const interval = Duration(milliseconds: 650);
      final remaining = timeout - clock.elapsed;
      if (remaining <= Duration.zero) break;
      await Future<void>.delayed(remaining < interval ? remaining : interval);
    }
    throw timedOut;
  }

  static List<({String name, String? ssid, bool off})> _interfaces(
    ProcessResult result,
  ) {
    final text = _output(result);
    if (RegExp(r'not running|未运行|未執行', caseSensitive: false).hasMatch(text)) {
      throw const WindowsWifiException('Windows 无线网络服务未运行。');
    }
    final names = RegExp(
      r'^[ \t]*(?:Name|名称|名稱)[ \t]*[:：][ \t]*(.+)$',
      caseSensitive: false,
      multiLine: true,
    ).allMatches(text).toList();
    if (names.isEmpty) {
      throw const WindowsWifiException('Windows 未找到可用的 Wi-Fi 网卡。');
    }
    return [
      for (var i = 0; i < names.length; i++)
        _readInterface(
          names[i].group(1)!.trim(),
          text.substring(
            names[i].end,
            i + 1 == names.length ? text.length : names[i + 1].start,
          ),
        ),
    ];
  }

  static ({String name, String? ssid, bool off}) _readInterface(
    String name,
    String text,
  ) {
    final state = _field(text, r'State|状态|狀態')?.toLowerCase();
    return (
      name: name,
      ssid: const {'connected', '已连接', '已連線'}.contains(state)
          ? _field(text, 'SSID')
          : null,
      off: RegExp(
        r'(?:Hardware|Software)[ \t]+Off|(?:硬件|软件|硬體|軟體)\s*(?:已)?(?:关闭|關閉)',
        caseSensitive: false,
      ).hasMatch(text),
    );
  }

  static bool? _visibleSecurity(String text, String ssid) {
    final rows = RegExp(
      r'^[ \t]*SSID[ \t]+\d+[ \t]*[:：][ \t]*(.*)$',
      multiLine: true,
    ).allMatches(text).toList();
    for (var i = 0; i < rows.length; i++) {
      if (rows[i].group(1)?.trim() != ssid) continue;
      final block = text.substring(
        rows[i].end,
        i + 1 == rows.length ? text.length : rows[i + 1].start,
      );
      final auth = _field(
        block,
        r'Authentication|身份验证|身份驗證|验证|驗證',
      )?.toLowerCase();
      final encryption = _field(block, r'Encryption|加密')?.toLowerCase();
      return const {'open', '开放式', '开放', '開放式', '開放'}.contains(auth) &&
          const {'none', '无', '無'}.contains(encryption);
    }
    return null;
  }

  static String? _field(String text, String keys) => RegExp(
    '^[ \\t]*(?:$keys)[ \\t]*[:：][ \\t]*(.+)',
    caseSensitive: false,
    multiLine: true,
  ).firstMatch(text)?.group(1)?.trim();

  Future<void> _addOpenProfile(
    String ssid,
    String interface,
    Future<ProcessResult> Function(List<String>) command,
  ) async {
    final dir = await Directory.systemTemp.createTemp('neu_wifi_');
    final file = File('${dir.path}${Platform.pathSeparator}wlan.xml');
    final name = const HtmlEscape(HtmlEscapeMode.element).convert(ssid);
    final hex = utf8
        .encode(ssid)
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join()
        .toUpperCase();
    try {
      await file.writeAsString('''<?xml version="1.0" encoding="UTF-8"?>
<WLANProfile xmlns="http://www.microsoft.com/networking/WLAN/profile/v1">
  <name>$name</name>
  <SSIDConfig><SSID><hex>$hex</hex><name>$name</name></SSID></SSIDConfig>
  <connectionType>ESS</connectionType>
  <connectionMode>manual</connectionMode>
  <MSM><security><authEncryption>
    <authentication>open</authentication>
    <encryption>none</encryption>
    <useOneX>false</useOneX>
  </authEncryption></security></MSM>
</WLANProfile>''', flush: true);
      final result = await command([
        'add',
        'profile',
        'filename=${file.path}',
        'interface=$interface',
        'user=current',
      ]);
      if (result.exitCode != 0) {
        throw const WindowsWifiException('Windows 无法保存开放 Wi-Fi 配置。');
      }
    } finally {
      if (await file.exists()) await file.delete();
      await dir.delete();
    }
  }

  Future<ProcessResult> _command(
    List<String> args, {
    Duration remaining = _commandTimeout,
    WindowsWifiException? deadlineError,
  }) async {
    final limit = remaining < _commandTimeout ? remaining : _commandTimeout;
    final ProcessResult result;
    try {
      result = await _run(args, limit);
    } on TimeoutException {
      throw (remaining <= _commandTimeout ? deadlineError : null) ??
          const WindowsWifiException('Windows Wi-Fi 命令响应超时。');
    }
    if (RegExp(
      r'location (?:permission|access)|access is denied|拒绝访问|拒絕存取|位置[^。\r\n]*(?:权限|權限)',
      caseSensitive: false,
    ).hasMatch(_output(result))) {
      throw const WindowsWifiException(
        'Windows 未授权读取 Wi-Fi 信息。请在系统的「隐私和安全性 → 位置」中允许桌面应用访问位置。',
      );
    }
    return result;
  }

  static String _output(ProcessResult result) =>
      '${_decodeOutput(result.stdout)}\n${_decodeOutput(result.stderr)}';

  static String _decodeOutput(Object? output) {
    if (output is String) return output;
    if (output is! List<int>) return '';
    try {
      // With redirected output, current netsh can emit UTF-8 even when
      // the Windows legacy code page is GBK or another local encoding.
      return utf8.decode(output);
    } on FormatException {
      return systemEncoding.decode(output);
    }
  }

  static Future<ProcessResult> _runNetsh(
    List<String> args,
    Duration timeout,
  ) async {
    if (!Platform.isWindows) {
      throw const WindowsWifiException('此 Wi-Fi 工具仅支持 Windows。');
    }
    try {
      final systemRoot = Platform.environment['SystemRoot'] ?? r'C:\Windows';
      final process = await Process.start('$systemRoot\\System32\\netsh.exe', [
        if (args.first != 'interface') 'wlan',
        ...args,
      ]);
      final output =
          await Future.wait<Object>([
            process.exitCode,
            process.stdout.expand((chunk) => chunk).toList(),
            process.stderr.expand((chunk) => chunk).toList(),
          ]).timeout(
            timeout,
            onTimeout: () {
              process.kill();
              throw TimeoutException('netsh', timeout);
            },
          );
      return ProcessResult(process.pid, output[0] as int, output[1], output[2]);
    } on ProcessException {
      throw const WindowsWifiException('无法启动 Windows Wi-Fi 工具。');
    }
  }
}
