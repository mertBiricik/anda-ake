/// WebSocket Service — Primary alarm delivery channel
///
/// Safety-Critical Architecture:
/// - Heartbeat Watchdog: Detects dead connections via ping/pong
/// - Auto-reconnect: Exponential backoff reconnection
/// - Forward Error Recovery: On failure, switch to polling mode
/// - Error Confinement: WebSocket errors don't crash the app
import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../models/alarm_message.dart';
import '../safety/acceptance_test.dart';

enum ConnectionStatus { disconnected, connecting, connected }

class WebSocketService {
  // Server configuration
  final String serverUrl;

  // Connection state
  WebSocketChannel? _channel;
  ConnectionStatus _status = ConnectionStatus.disconnected;
  String? _clientId;
  Timer? _reconnectTimer;
  Timer? _heartbeatTimer;
  int _reconnectAttempts = 0;
  int _missedHeartbeats = 0;

  // Configuration
  static const int maxReconnectAttempts = 50;
  static const int heartbeatIntervalSeconds = 15;
  static const int maxMissedHeartbeats = 3;

  // Callbacks
  final ValueChanged<AlarmMessage> onAlarmReceived;
  final ValueChanged<ConnectionStatus> onConnectionStatusChanged;
  final ValueChanged<String> onLog;

  WebSocketService({
    required this.serverUrl,
    required this.onAlarmReceived,
    required this.onConnectionStatusChanged,
    required this.onLog,
  });

  ConnectionStatus get status => _status;
  String? get clientId => _clientId;

  /// Connect to the WebSocket server
  void connect() {
    if (_status == ConnectionStatus.connecting) return;

    _setStatus(ConnectionStatus.connecting);
    _log('Connecting to $serverUrl...');

    try {
      final wsUrl = serverUrl.replaceFirst('http', 'ws');
      _channel = WebSocketChannel.connect(Uri.parse('$wsUrl/ws'));

      _channel!.stream.listen(
        _onMessage,
        onError: _onError,
        onDone: _onDone,
        cancelOnError: false,
      );
    } catch (e) {
      _log('Connection error: $e');
      _setStatus(ConnectionStatus.disconnected);
      _scheduleReconnect();
    }
  }

  /// Handle incoming WebSocket messages
  void _onMessage(dynamic data) {
    try {
      final json = jsonDecode(data as String) as Map<String, dynamic>;
      final type = json['type'] as String?;

      switch (type) {
        case 'WELCOME':
          _clientId = json['client_id'] as String?;
          _reconnectAttempts = 0;
          _missedHeartbeats = 0;
          _setStatus(ConnectionStatus.connected);
          _startHeartbeatMonitor();
          _log('✅ Connected! Client ID: $_clientId');
          
          // Register device info
          _send({
            'type': 'REGISTER',
            'device_info': {
              'platform': defaultTargetPlatform.toString(),
              'app_version': '1.0.0',
            }
          });
          break;

        case 'ALARM':
          _handleAlarm(json);
          break;

        case 'PING':
          // Server heartbeat — respond with PONG
          _missedHeartbeats = 0;
          _send({'type': 'PONG', 'timestamp': DateTime.now().millisecondsSinceEpoch});
          break;

        case 'ACK_CONFIRMED':
          _log('ACK confirmed for alarm ${json['alarm_id']}');
          break;

        case 'SERVER_SHUTDOWN':
          _log('⚠️ Server shutting down: ${json['message']}');
          break;

        default:
          _log('Unknown message type: $type');
      }
    } catch (e) {
      // Robust Software: don't crash on malformed messages
      _log('Error parsing message: $e');
    }
  }

  /// Handle alarm message with Acceptance Test
  void _handleAlarm(Map<String, dynamic> json) {
    try {
      final alarm = AlarmMessage.fromJson(json);
      
      // Safety-Critical: Acceptance Test before triggering alarm
      final atResult = AlarmAcceptanceTest.validate(alarm);
      
      if (atResult.passed) {
        _log('🚨 ALARM PASSED AT: ${alarm.title}');
        onAlarmReceived(alarm);
        
        // Send ACK back to server
        _send({'type': 'ACK', 'alarm_id': alarm.id});
      } else {
        _log('⛔ ALARM REJECTED: $atResult');
      }
    } catch (e) {
      _log('Error handling alarm: $e');
    }
  }

  /// Handle WebSocket errors (Error Confinement)
  void _onError(dynamic error) {
    _log('WebSocket error: $error');
    _setStatus(ConnectionStatus.disconnected);
    _stopHeartbeatMonitor();
    _scheduleReconnect();
  }

  /// Handle WebSocket disconnection
  void _onDone() {
    _log('WebSocket disconnected');
    _setStatus(ConnectionStatus.disconnected);
    _stopHeartbeatMonitor();
    _scheduleReconnect();
  }

  /// Heartbeat Watchdog (Safety-Critical: Chapter 3)
  /// Monitors server ping/pong to detect dead connections.
  void _startHeartbeatMonitor() {
    _stopHeartbeatMonitor();
    _heartbeatTimer = Timer.periodic(
      const Duration(seconds: heartbeatIntervalSeconds),
      (_) {
        _missedHeartbeats++;
        if (_missedHeartbeats >= maxMissedHeartbeats) {
          _log('💀 Heartbeat timeout ($maxMissedHeartbeats missed) — reconnecting');
          _channel?.sink.close();
        }
      },
    );
  }

  void _stopHeartbeatMonitor() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _missedHeartbeats = 0;
  }

  /// Auto-reconnect with exponential backoff
  void _scheduleReconnect() {
    _reconnectTimer?.cancel();

    if (_reconnectAttempts >= maxReconnectAttempts) {
      _log('❌ Max reconnect attempts reached ($maxReconnectAttempts)');
      return;
    }

    // Exponential backoff: 1s, 2s, 4s, 8s, 16s, max 30s
    final delay = Duration(
      seconds: (1 << _reconnectAttempts).clamp(1, 30),
    );
    _reconnectAttempts++;

    _log('Reconnecting in ${delay.inSeconds}s (attempt $_reconnectAttempts)...');
    _reconnectTimer = Timer(delay, connect);
  }

  /// Send a JSON message to the server
  void _send(Map<String, dynamic> data) {
    try {
      if (_channel != null) {
        _channel!.sink.add(jsonEncode(data));
      }
    } catch (e) {
      _log('Send error: $e');
    }
  }

  /// Acknowledge an alarm
  void acknowledgeAlarm(String alarmId) {
    _send({'type': 'ACK', 'alarm_id': alarmId});
    _log('ACK sent for $alarmId');
  }

  void _setStatus(ConnectionStatus status) {
    _status = status;
    onConnectionStatusChanged(status);
  }

  void _log(String message) {
    debugPrint('[WS] $message');
    onLog('[WS] $message');
  }

  /// Disconnect and cleanup
  void dispose() {
    _reconnectTimer?.cancel();
    _stopHeartbeatMonitor();
    _channel?.sink.close();
  }
}
