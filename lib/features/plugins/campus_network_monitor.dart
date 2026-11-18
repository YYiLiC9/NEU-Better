import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../../core/network/campus_gateway_client.dart';

final campusNetworkMonitorProvider =
    ChangeNotifierProvider<CampusNetworkMonitor>((_) => CampusNetworkMonitor());

typedef InterfaceCounters = ({String id, int received, int sent});

class CampusNetworkMonitor extends ChangeNotifier {
  CampusNetworkMonitor({
    CampusGatewayClient? gateway,
    Future<InterfaceCounters> Function()? readCounters,
  }) : _gateway = gateway ?? CampusGatewayClient(),
       _readCounters = readCounters ?? _readWindowsCounters;

  final CampusGatewayClient _gateway;
  final Future<InterfaceCounters> Function() _readCounters;
  static const _channel = MethodChannel('neu_better/window');
  Timer? _poll;
  int _viewCount = 0;
  bool _disposed = false;
  bool _refreshing = false;
  CampusGatewayStatus? _status;
  InterfaceCounters? _previous;
  int? _connectionBytes;
  bool _statusUnavailable = false;
  bool _partial = false;

  CampusGatewayStatus? get status => _status;
  int? get connectionBytes => _connectionBytes;
  bool get statusUnavailable => _statusUnavailable;
  bool get partial => _partial;
  bool get refreshing => _refreshing;

  void attach() {
    _viewCount++;
    _poll ??= Timer.periodic(
      const Duration(seconds: 5),
      (_) => unawaited(refresh()),
    );
    unawaited(refresh());
  }

  void detach() {
    _viewCount--;
    _stopIfIdle();
  }

  void _stopIfIdle() {
    if (_viewCount == 0 && _status?.online != true) {
      _poll?.cancel();
      _poll = null;
    }
  }

  Future<void> refresh() async {
    if (_disposed || _refreshing) return;
    _refreshing = true;
    notifyListeners();
    try {
      final next = await _gateway.readStatus();
      if (_disposed) return;
      if (!next.online) {
        _previous = null;
      } else {
        if (_status?.online != true ||
            _status?.connectionKey != next.connectionKey) {
          _previous = null;
          _connectionBytes = null;
          _partial = false;
        }
        await _sampleCounters();
      }
      _status = next;
      _statusUnavailable = false;
    } catch (_) {
      _statusUnavailable = true;
      if (_status?.online == true) {
        _previous = null;
        _partial = true;
      }
    } finally {
      _refreshing = false;
      if (!_disposed) {
        _stopIfIdle();
        notifyListeners();
      }
    }
  }

  Future<void> _sampleCounters() async {
    final InterfaceCounters next;
    try {
      next = await _readCounters();
    } catch (_) {
      _previous = null;
      _partial = true;
      return;
    }
    final previous = _previous;
    _previous = next;
    _connectionBytes ??= 0;
    if (previous == null) return;
    if (next.id != previous.id ||
        next.received < previous.received ||
        next.sent < previous.sent) {
      _partial = true;
      return;
    }
    _connectionBytes =
        _connectionBytes! +
        (next.received - previous.received) +
        (next.sent - previous.sent);
  }

  static Future<InterfaceCounters> _readWindowsCounters() async {
    final addresses = await InternetAddress.lookup(
      CampusGatewayClient.host,
      type: InternetAddressType.IPv4,
    ).timeout(const Duration(seconds: 3));
    final values = await _channel.invokeMapMethod<String, Object?>(
      'interfaceCounters',
      addresses.first.address,
    );
    final id = values?['id'];
    final received = values?['received'];
    final sent = values?['sent'];
    if (id is! String ||
        received is! int ||
        sent is! int ||
        received < 0 ||
        sent < 0) {
      throw StateError('无法读取 Windows 网卡计数');
    }
    return (id: id, received: received, sent: sent);
  }

  @override
  void dispose() {
    _disposed = true;
    _poll?.cancel();
    _gateway.close();
    super.dispose();
  }
}
