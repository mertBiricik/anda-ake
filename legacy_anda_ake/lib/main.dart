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
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'config.dart';
import 'login_screen.dart';
import 'user_management_screen.dart';
import 'alarm_screen.dart';
import 'models/alarm_message.dart';
import 'services/websocket_service.dart';
import 'services/notification_service.dart';
import 'safety/acceptance_test.dart';

import 'background/foreground_task_handler.dart';

// Global navigator key for navigation from anywhere
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

// ============================================================
// Main Entry Point
// ============================================================
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize Foreground Task System
  BackgroundManager.initForegroundTask();

  // Initialize notifications (Firebase-free)
  await NotificationService.initialize(
    onNotificationTapped: (payload) {
      if (payload != null) {
        navigatorKey.currentState?.pushNamed('/alarm', arguments: payload);
      }
    },
  );

  final prefs = await SharedPreferences.getInstance();
  final hasToken = prefs.getString('jwt_token') != null && prefs.getString('jwt_token')!.isNotEmpty;

  // Check if launched from notification
  final initialPayload = await NotificationService.getInitialPayload();
  String? initialRoute = hasToken ? '/' : '/login';
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
      title: AppConfig.appName,
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF3B82F6), // Blue accent
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
        textTheme: GoogleFonts.interTextTheme(ThemeData.dark().textTheme),
      ),
      initialRoute: initialRoute ?? '/',
      routes: {
        '/login': (context) => const LoginScreen(),
        '/users': (context) => const UserManagementScreen(),
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
// Tactical Color Palette
// ============================================================
class TacticalColors {
  static const Color bg = Color(0xFF0B1120);
  static const Color surface = Color(0xFF1E293B);
  static const Color panel = Color(0xFF0F172A);
  static const Color border = Color(0xFF334155);
  static const Color borderActive = Color(0xFF475569);
  static const Color textPrimary = Color(0xFFF8FAFC);
  static const Color textSecondary = Color(0xFF94A3B8);
  static const Color textMuted = Color(0xFF475569);
  static const Color green = Color(0xFF10B981);
  static const Color amber = Color(0xFFF59E0B);
  static const Color red = Color(0xFFEF4444);
  static const Color cyan = Color(0xFF06B6D4);
  static const Color orange = Color(0xFF3B82F6); // Reused as Primary Blue
}

// ============================================================
// Home Screen — Tactical C2 Dashboard
// ============================================================
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  WebSocketService? _wsService;
  ConnectionStatus _connectionStatus = ConnectionStatus.disconnected;
  final List<String> _logs = [];
  Timer? _pollingTimer;
  int _lastPollTimestamp = 0;
  late AnimationController _pulseController;
  DateTime _sessionStart = DateTime.now();
  int _alarmsReceived = 0;
  int _alarmsAcked = 0;

  String _jwtToken = '';
  String _userRole = 'RESCUER';
  String _userName = '';

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
    
    _loadUserData().then((_) {
      _initWebSocket();
      _loadLastPollTimestamp();
      BackgroundManager.startForegroundTask(onMessage: _handleBackgroundMessage);
    });
  }

  Future<void> _loadUserData() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _jwtToken = prefs.getString('jwt_token') ?? '';
      _userRole = prefs.getString('user_role') ?? 'RESCUER';
      _userName = prefs.getString('user_name') ?? '';
    });
  }

  void _handleBackgroundMessage(Map<String, dynamic> message) {
    final type = message['type'];
    
    if (type == 'ALARM' && message['data'] != null) {
      final alarm = AlarmMessage.fromJson(message['data']);
      _onAlarmReceived(alarm);
    } else if (type == 'LOG' && message['message'] != null) {
      _addLog('[BG] ${message['message']}');
    } else if (type == 'NAVIGATION' && message['payload'] != null) {
      navigatorKey.currentState?.pushNamed('/alarm', arguments: message['payload']);
    }
  }

  void _initWebSocket() {
    if (_jwtToken.isEmpty) return;

    _wsService = WebSocketService(
      serverUrl: AppConfig.serverUrl,
      token: _jwtToken,
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
        _addLog(log);
      },
    );
    _wsService!.connect();
  }

  /// Handle incoming alarm — navigate to AlarmScreen
  void _onAlarmReceived(AlarmMessage alarm) {
    setState(() => _alarmsReceived++);

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
            setState(() => _alarmsAcked++);
            _wsService?.acknowledgeAlarm(alarm.id);
            NotificationService.cancelAll();
          },
        ),
      ),
    );
  }

  // ============================================================
  // Recovery Block — Polling Fallback (Alternate Channel, Ch.4)
  // ============================================================
  void _startPollingFallback() {
    _stopPollingFallback();
    _addLog('📡 Recovery Block ACTIVE — polling fallback engaged');

    _pollingTimer = Timer.periodic(
      Duration(seconds: AppConfig.pollingIntervalSeconds),
      (_) async {
        try {
          final response = await http.get(
            Uri.parse('${AppConfig.pendingAlarmsUrl}?since=$_lastPollTimestamp'),
            headers: {'Authorization': 'Bearer $_jwtToken'},
          ).timeout(Duration(seconds: AppConfig.pollingTimeoutSeconds));

          if (response.statusCode == 200) {
            final data = jsonDecode(response.body);
            final alarms = data['alarms'] as List? ?? [];

            for (final alarmJson in alarms) {
              final alarm = AlarmMessage.fromJson(alarmJson);
              final atResult = AlarmAcceptanceTest.validate(alarm);

              if (atResult.passed) {
                _addLog('📡 Polling recovered alarm: ${alarm.title}');
                _onAlarmReceived(alarm);
              }
            }

            _lastPollTimestamp = data['server_time'] as int? ?? _lastPollTimestamp;
            _saveLastPollTimestamp();
          }
        } catch (e) {
          _addLog('📡 Poll error: $e');
        }
      },
    );
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
    if (!mounted) return;
    setState(() {
      _logs.add('[${_timeStr()}] $log');
      if (_logs.length > 100) _logs.removeAt(0);
    });
  }

  String _timeStr() {
    final now = DateTime.now();
    return '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}';
  }

  String _uptimeStr() {
    final diff = DateTime.now().difference(_sessionStart);
    final h = diff.inHours.toString().padLeft(2, '0');
    final m = (diff.inMinutes % 60).toString().padLeft(2, '0');
    final s = (diff.inSeconds % 60).toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  @override
  void dispose() {
    _wsService?.dispose();
    _stopPollingFallback();
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: TacticalColors.bg,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            _buildStatusBar(),
            _buildMetricsRow(),
            if (_userRole == 'MERKEZ' || _userRole == 'IL_BASKANI') _buildAlarmButton(),
            Expanded(child: _buildLogPanel()),
            _buildFooter(),
          ],
        ),
      ),
    );
  }

  // ── Header ──────────────────────────────────────────────────
  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: const BoxDecoration(
        color: TacticalColors.surface,
        border: Border(bottom: BorderSide(color: TacticalColors.border, width: 1)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: TacticalColors.orange.withOpacity(0.1),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: TacticalColors.orange.withOpacity(0.3)),
            ),
            child: const Icon(Icons.radar, color: TacticalColors.orange, size: 24),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'ANDA AKE',
                style: TextStyle(
                  fontSize: 18, fontWeight: FontWeight.w900,
                  letterSpacing: 3.0, color: TacticalColors.textPrimary,
                ),
              ),
              Text(
                _userName.isNotEmpty ? _userName.toUpperCase() : 'ARAMA KURTARMA // K2 TERMİNALİ',
                style: const TextStyle(
                  fontSize: 10, letterSpacing: 1.5,
                  color: TacticalColors.textSecondary,
                ),
              ),
            ],
          ),
          const Spacer(),
          if (_userRole == 'MERKEZ' || _userRole == 'IL_BASKANI')
            IconButton(
              icon: const Icon(Icons.people, color: TacticalColors.cyan),
              onPressed: () => Navigator.pushNamed(context, '/users'),
              tooltip: 'Personel Yönetimi',
            ),
          IconButton(
            icon: const Icon(Icons.logout, color: TacticalColors.red),
            tooltip: 'Çıkış Yap',
            onPressed: () async {
              final prefs = await SharedPreferences.getInstance();
              await prefs.remove('jwt_token');
              await prefs.remove('user_role');
              await prefs.remove('user_name');
              await prefs.remove('user_province');
              if (mounted) {
                _wsService?.dispose();
                Navigator.of(context).pushReplacementNamed('/login');
              }
            },
          ),
          _buildConnectionBadge(),
        ],
      ),
    );
  }

  Widget _buildConnectionBadge() {
    final isConnected = _connectionStatus == ConnectionStatus.connected;
    final isConnecting = _connectionStatus == ConnectionStatus.connecting;
    final color = isConnected ? TacticalColors.green : isConnecting ? TacticalColors.amber : TacticalColors.red;
    final label = isConnected ? 'BAĞLI' : isConnecting ? 'EŞLEŞİYOR' : 'ÇEVRİMDIŞI';

    return AnimatedBuilder(
      animation: _pulseController,
      builder: (context, child) {
        final opacity = isConnected ? 1.0 : (0.5 + 0.5 * _pulseController.value);
        return Opacity(opacity: opacity, child: child);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: color.withOpacity(0.12),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: color.withOpacity(0.4)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 8, height: 8,
              decoration: BoxDecoration(
                color: color, shape: BoxShape.circle,
                boxShadow: [BoxShadow(color: color.withOpacity(0.6), blurRadius: 6)],
              ),
            ),
            const SizedBox(width: 8),
            Text(label, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 1.0)),
          ],
        ),
      ),
    );
  }

  // ── Status Bar ──────────────────────────────────────────────
  Widget _buildStatusBar() {
    final isConnected = _connectionStatus == ConnectionStatus.connected;
    final isPolling = _pollingTimer != null;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: isConnected ? TacticalColors.green.withOpacity(0.05) : TacticalColors.red.withOpacity(0.05),
        border: Border(
          bottom: BorderSide(
            color: isConnected ? TacticalColors.green.withOpacity(0.15) : TacticalColors.red.withOpacity(0.15),
          ),
        ),
      ),
      child: Row(
        children: [
          Icon(
            isConnected ? Icons.link : Icons.link_off,
            size: 16,
            color: isConnected ? TacticalColors.green : TacticalColors.red,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              isConnected
                  ? 'WS BAĞLI → ${AppConfig.serverUrl} [$_userRole]'
                  : 'WS KOPTU${isPolling ? " │ YEDEK SORGULAMA AKTİF" : ""}',
              style: TextStyle(
                fontSize: 11, letterSpacing: 0.5,
                color: isConnected ? TacticalColors.green.withOpacity(0.8) : TacticalColors.red.withOpacity(0.8),
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (_wsService?.clientId != null)
            Text(
              'UID:${_wsService!.clientId!.split('-').first}',
              style: TextStyle(fontSize: 10, color: TacticalColors.textMuted),
            ),
          if (!isConnected) ...[
            const SizedBox(width: 8),
            GestureDetector(
              onTap: () { _wsService?.dispose(); _initWebSocket(); },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: TacticalColors.amber.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(3),
                  border: Border.all(color: TacticalColors.amber.withOpacity(0.4)),
                ),
                child: const Text('YENİDEN DENE', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: TacticalColors.amber)),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ── Metrics Row ─────────────────────────────────────────────
  Widget _buildMetricsRow() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: TacticalColors.border, width: 1)),
      ),
      child: Row(
        children: [
          _buildMetricTile('OTURUM', _uptimeStr(), TacticalColors.cyan),
          _buildMetricTile('GELEN ALARM', '$_alarmsReceived', TacticalColors.orange),
          _buildMetricTile('ONAYLANAN', '$_alarmsAcked', TacticalColors.green),
          _buildMetricTile('KANAL', _pollingTimer != null ? 'SORG' : 'WS', _pollingTimer != null ? TacticalColors.amber : TacticalColors.cyan),
        ],
      ),
    );
  }

  Widget _buildMetricTile(String label, String value, Color color) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 4),
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
        decoration: BoxDecoration(
          color: color.withOpacity(0.06),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: color.withOpacity(0.15)),
        ),
        child: Column(
          children: [
            Text(value, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: color)),
            const SizedBox(height: 2),
            Text(label, style: TextStyle(fontSize: 8, fontWeight: FontWeight.w700, color: color.withOpacity(0.6), letterSpacing: 1.0)),
          ],
        ),
      ),
    );
  }

  // ── Alarm Trigger Button ────────────────────────────────────
  Widget _buildAlarmButton() {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: SizedBox(
        width: double.infinity,
        height: 56,
        child: ElevatedButton(
          onPressed: () async {
            _addLog('ALARM TETİKLENİYOR (CANLI)...');
            try {
              final response = await http.post(
                Uri.parse('${AppConfig.serverUrl}/api/trigger-alarm'),
                headers: {
                  'Content-Type': 'application/json',
                  'Authorization': 'Bearer $_jwtToken',
                },
                body: jsonEncode({
                  'title': 'KIRMIZI ALARM: ACİL İNTİKAL',
                  'body': '$_userName tarafından alarm tetiklendi. En yakın toplanma alanına geçin.',
                  'priority': 'critical'
                }),
              ).timeout(const Duration(seconds: 10));

              if (response.statusCode == 200) {
                final data = jsonDecode(response.body);
                _addLog('ALARM BAŞARILI: ${data['sent_to']} cihaza iletildi.');
              } else {
                _addLog('ALARM HATASI: Sunucu reddetti (${response.statusCode})');
              }
            } catch (e) {
              _addLog('ALARM HATASI: Bağlantı kurulamadı.');
            }
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: TacticalColors.red.withOpacity(0.15),
            foregroundColor: TacticalColors.red,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(4),
              side: BorderSide(color: TacticalColors.red.withOpacity(0.5), width: 1.5),
            ),
            elevation: 0,
          ),
          child: const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.satellite_alt, size: 22),
              SizedBox(width: 10),
              Text('BİRLİKLERE ALARM GÖNDER (CANLI)', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900, letterSpacing: 1.5)),
            ],
          ),
        ),
      ),
    );
  }

  // ── Log Panel ───────────────────────────────────────────────
  Widget _buildLogPanel() {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 0),
      decoration: BoxDecoration(
        color: const Color(0xFF060A10),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: TacticalColors.border, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: const BoxDecoration(
              color: TacticalColors.panel,
              borderRadius: BorderRadius.only(topLeft: Radius.circular(5), topRight: Radius.circular(5)),
              border: Border(bottom: BorderSide(color: TacticalColors.border)),
            ),
            child: Row(
              children: [
                const Icon(Icons.terminal, color: TacticalColors.cyan, size: 14),
                const SizedBox(width: 8),
                const Text('SİSTEM GÜNLÜĞÜ', style: TextStyle(color: TacticalColors.cyan, fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 1.5)),
                const Spacer(),
                Text('${_logs.length} kayıt', style: TextStyle(color: TacticalColors.textMuted, fontSize: 10)),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(10),
              itemCount: _logs.length,
              reverse: true,
              itemBuilder: (context, index) {
                final log = _logs[_logs.length - 1 - index];
                final isError = log.contains('ERROR') || log.contains('❌') || log.contains('💀');
                final isAlarm = log.contains('🚨') || log.contains('ALARM');
                final isSuccess = log.contains('✅') || log.contains('LIVE') || log.contains('Connected');
                final isPoll = log.contains('📡') || log.contains('Recovery');

                Color textColor = TacticalColors.textSecondary;
                if (isError) textColor = TacticalColors.red;
                if (isAlarm) textColor = TacticalColors.orange;
                if (isSuccess) textColor = TacticalColors.green;
                if (isPoll) textColor = TacticalColors.amber;

                return Padding(
                  padding: const EdgeInsets.only(bottom: 3),
                  child: Text(
                    log,
                    style: TextStyle(color: textColor, fontSize: 11, fontWeight: isAlarm ? FontWeight.bold : FontWeight.normal),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // ── Footer ──────────────────────────────────────────────────
  Widget _buildFooter() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: TacticalColors.border, width: 1)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text('${AppConfig.appName} v${AppConfig.appVersion}', style: TextStyle(fontSize: 9, color: TacticalColors.textMuted, letterSpacing: 1.0)),
          Text('GÜVENLİK-KRİTİK │ BÖL. 2-4', style: TextStyle(fontSize: 9, color: TacticalColors.textMuted, letterSpacing: 1.0)),
        ],
      ),
    );
  }
}
