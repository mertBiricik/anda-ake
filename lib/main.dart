/// ANDA AKE — Safety-Critical SAR Alarm Application
///
/// Architecture: WebSocket-based, Firebase-independent
/// Safety-Critical Principles Applied:
/// - Acceptance Tests: Validate all alarm payloads (Ch.4)
/// - Heartbeat Watchdog: Detect dead connections (Ch.3)
/// - Recovery Block: WebSocket primary, HTTP polling fallback (Ch.4)
/// - Forward Error Recovery: Auto-reconnect on failure (Ch.3)
/// - Error Confinement: Isolate component failures (Ch.2)
/// - Robust Software: Handle all invalid inputs gracefully (Ch.2)
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'alarm_screen.dart';
import 'models/alarm_message.dart';
import 'services/websocket_service.dart';
import 'services/notification_service.dart';
import 'safety/acceptance_test.dart';

// ============================================================
// Configuration
// ============================================================
const String serverUrl = 'http://anda.biricik.de';

// Global navigator key for navigation from anywhere
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

// ============================================================
// Main Entry Point
// ============================================================
void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize notifications (Firebase-free)
  await NotificationService.initialize(
    onNotificationTapped: (payload) {
      if (payload != null) {
        navigatorKey.currentState?.pushNamed('/alarm', arguments: payload);
      }
    },
  );

  // Check if launched from notification
  final initialPayload = await NotificationService.getInitialPayload();
  String? initialRoute = '/';
  String? alarmPayload;

  if (initialPayload != null) {
    debugPrint('🚨 App launched via Notification');
    initialRoute = '/alarm';
    alarmPayload = initialPayload;
  }

  runApp(AndaAkeApp(initialRoute: initialRoute, alarmPayload: alarmPayload));
}

// ============================================================
// App Root
// ============================================================
class AndaAkeApp extends StatelessWidget {
  final String? initialRoute;
  final String? alarmPayload;

  const AndaAkeApp({super.key, this.initialRoute, this.alarmPayload});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      title: 'ANDA AKE',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.deepOrange,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      initialRoute: initialRoute ?? '/',
      routes: {
        '/': (context) => const HomeScreen(),
        '/alarm': (context) {
          final message = alarmPayload ??
              ModalRoute.of(context)?.settings.arguments as String? ??
              'CRITICAL MISSION';
          return AlarmScreen(missionMessage: message);
        },
      },
    );
  }
}

// ============================================================
// Home Screen — Connection status + test controls
// ============================================================
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late WebSocketService _wsService;
  ConnectionStatus _connectionStatus = ConnectionStatus.disconnected;
  final List<String> _logs = [];
  Timer? _pollingTimer;
  int _lastPollTimestamp = 0;

  @override
  void initState() {
    super.initState();
    _initWebSocket();
    _loadLastPollTimestamp();
  }

  void _initWebSocket() {
    _wsService = WebSocketService(
      serverUrl: serverUrl,
      onAlarmReceived: _onAlarmReceived,
      onConnectionStatusChanged: (status) {
        setState(() => _connectionStatus = status);

        // Recovery Block: if WebSocket disconnects, start polling fallback
        if (status == ConnectionStatus.disconnected) {
          _startPollingFallback();
        } else if (status == ConnectionStatus.connected) {
          _stopPollingFallback();
        }
      },
      onLog: (log) {
        setState(() {
          _logs.add('[${_timeStr()}] $log');
          if (_logs.length > 50) _logs.removeAt(0);
        });
      },
    );
    _wsService.connect();
  }

  /// Handle incoming alarm — navigate to AlarmScreen
  void _onAlarmReceived(AlarmMessage alarm) {
    // Show notification (for background awareness)
    NotificationService.showAlarmNotification(
      id: alarm.hashCode,
      title: alarm.title,
      body: alarm.body,
      payload: alarm.body,
    );

    // Navigate to alarm screen
    navigatorKey.currentState?.push(
      MaterialPageRoute(
        builder: (_) => AlarmScreen(
          missionMessage: '${alarm.title}\n\n${alarm.body}',
          alarmId: alarm.missionId,
          onAcknowledge: (id) {
            _wsService.acknowledgeAlarm(alarm.id);
            NotificationService.cancelAll();
          },
        ),
      ),
    );
  }

  // ============================================================
  // Recovery Block — Polling Fallback (Alternate Channel)
  // If WebSocket is down, poll the server for pending alarms.
  // ============================================================
  void _startPollingFallback() {
    _stopPollingFallback();
    _addLog('📡 Starting polling fallback (Recovery Block: Alternate 1)');

    _pollingTimer = Timer.periodic(const Duration(seconds: 10), (_) async {
      try {
        final response = await http.get(
          Uri.parse('$serverUrl/api/pending-alarms?since=$_lastPollTimestamp&apiKey=anda-ake-secret-key-change-me'),
        ).timeout(const Duration(seconds: 5));

        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          final alarms = data['alarms'] as List? ?? [];

          for (final alarmJson in alarms) {
            final alarm = AlarmMessage.fromJson(alarmJson);
            final atResult = AlarmAcceptanceTest.validate(alarm);

            if (atResult.passed) {
              _addLog('📡 Polling found alarm: ${alarm.title}');
              _onAlarmReceived(alarm);
            }
          }

          _lastPollTimestamp = data['server_time'] as int? ?? _lastPollTimestamp;
          _saveLastPollTimestamp();
        }
      } catch (e) {
        _addLog('📡 Polling error: $e');
      }
    });
  }

  void _stopPollingFallback() {
    _pollingTimer?.cancel();
    _pollingTimer = null;
  }

  Future<void> _loadLastPollTimestamp() async {
    final prefs = await SharedPreferences.getInstance();
    _lastPollTimestamp = prefs.getInt('last_poll_timestamp') ?? 0;
  }

  Future<void> _saveLastPollTimestamp() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('last_poll_timestamp', _lastPollTimestamp);
  }

  void _addLog(String log) {
    setState(() {
      _logs.add('[${_timeStr()}] $log');
      if (_logs.length > 50) _logs.removeAt(0);
    });
  }

  String _timeStr() {
    final now = DateTime.now();
    return '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}';
  }

  @override
  void dispose() {
    _wsService.dispose();
    _stopPollingFallback();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('ANDA AKE'),
        centerTitle: true,
        actions: [
          // Connection status indicator
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: _buildStatusIndicator(),
          ),
        ],
      ),
      body: Column(
        children: [
          // Connection card
          _buildConnectionCard(),

          // Test button
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton.icon(
                onPressed: () {
                  navigatorKey.currentState?.push(
                    MaterialPageRoute(
                      builder: (_) => AlarmScreen(
                        missionMessage: 'TEST MISSION: RED ALERT\n\nBu bir test alarmıdır.',
                        alarmId: 'TEST-${DateTime.now().millisecondsSinceEpoch}',
                        onAcknowledge: (id) {
                          debugPrint('Test alarm acknowledged: $id');
                        },
                      ),
                    ),
                  );
                },
                icon: const Icon(Icons.warning_amber_rounded, size: 28),
                label: const Text('TEST ALARM', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red.shade700,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
          ),

          // Log panel
          Expanded(
            child: Container(
              margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              decoration: BoxDecoration(
                color: Colors.black87,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        const Icon(Icons.terminal, color: Colors.green, size: 16),
                        const SizedBox(width: 8),
                        const Text(
                          'System Log',
                          style: TextStyle(
                            color: Colors.green,
                            fontWeight: FontWeight.bold,
                            fontFamily: 'monospace',
                          ),
                        ),
                        const Spacer(),
                        if (_pollingTimer != null)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.orange.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Text(
                              'POLLING',
                              style: TextStyle(color: Colors.orange, fontSize: 10, fontFamily: 'monospace'),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const Divider(color: Colors.green, height: 1),
                  Expanded(
                    child: ListView.builder(
                      padding: const EdgeInsets.all(8),
                      itemCount: _logs.length,
                      reverse: true,
                      itemBuilder: (context, index) {
                        final log = _logs[_logs.length - 1 - index];
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 1),
                          child: Text(
                            log,
                            style: TextStyle(
                              color: log.contains('ERROR') || log.contains('❌')
                                  ? Colors.red.shade300
                                  : log.contains('🚨') || log.contains('ALARM')
                                      ? Colors.yellow
                                      : log.contains('✅')
                                          ? Colors.green.shade300
                                          : log.contains('⚠️') || log.contains('⛔')
                                              ? Colors.orange.shade300
                                              : Colors.green.shade100,
                              fontSize: 11,
                              fontFamily: 'monospace',
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusIndicator() {
    final color = switch (_connectionStatus) {
      ConnectionStatus.connected => Colors.green,
      ConnectionStatus.connecting => Colors.orange,
      ConnectionStatus.disconnected => Colors.red,
    };
    final label = switch (_connectionStatus) {
      ConnectionStatus.connected => 'LIVE',
      ConnectionStatus.connecting => '...',
      ConnectionStatus.disconnected => 'OFF',
    };

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(label, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.bold)),
      ],
    );
  }

  Widget _buildConnectionCard() {
    return Card(
      margin: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(
              _connectionStatus == ConnectionStatus.connected
                  ? Icons.cell_tower
                  : Icons.signal_cellular_off,
              size: 40,
              color: _connectionStatus == ConnectionStatus.connected
                  ? Colors.green
                  : Colors.red,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _connectionStatus == ConnectionStatus.connected
                        ? 'Ready for alerts'
                        : _connectionStatus == ConnectionStatus.connecting
                            ? 'Connecting...'
                            : 'Disconnected',
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    serverUrl,
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade400),
                  ),
                  if (_wsService.clientId != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      'ID: ${_wsService.clientId}',
                      style: TextStyle(
                        fontSize: 10,
                        color: Colors.grey.shade500,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ],
                ],
              ),
            ),
            // Reconnect button
            if (_connectionStatus == ConnectionStatus.disconnected)
              IconButton(
                onPressed: () {
                  _wsService.dispose();
                  _initWebSocket();
                },
                icon: const Icon(Icons.refresh, color: Colors.orange),
              ),
          ],
        ),
      ),
    );
  }
}
