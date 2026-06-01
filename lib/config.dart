/// ANDA AKE — Centralized Configuration
///
/// Safety-Critical Design: All configuration constants are defined in a single
/// location to prevent inconsistencies across modules (Error Confinement, Ch.2).
/// Previously, server URL and API key were duplicated across main.dart and
/// foreground_task_handler.dart, creating a maintenance hazard.

class AppConfig {
  AppConfig._(); // Prevent instantiation

  // ── Server ──────────────────────────────────────────────────────────────
  /// Base URL includes port since Nginx Proxy Manager doesn't proxy WS.
  static const String serverUrl = 'http://anda.biricik.de:3000';
  static const String apiKey = 'mahmutgülşahhamsizatturizortzort';

  // ── WebSocket ───────────────────────────────────────────────────────────
  static String get wsUrl => serverUrl.replaceFirst('http', 'ws');
  static String get wsEndpoint => '$wsUrl/ws';

  // ── REST API ────────────────────────────────────────────────────────────
  static String get triggerAlarmUrl => '$serverUrl/api/trigger-alarm';
  static String get pendingAlarmsUrl => '$serverUrl/api/pending-alarms';
  static String get healthUrl => '$serverUrl/api/health';
  static String get clientsUrl => '$serverUrl/api/clients';
  static String get ackUrl => '$serverUrl/api/ack';

  // ── Polling Fallback (Recovery Block: Alternate 1, Ch.4) ────────────────
  static const int pollingIntervalSeconds = 10;
  static const int pollingTimeoutSeconds = 5;

  // ── Heartbeat Watchdog (Ch.3) ───────────────────────────────────────────
  static const int heartbeatIntervalSeconds = 15;
  static const int maxMissedHeartbeats = 3;

  // ── Reconnect (Forward Error Recovery, Ch.3) ────────────────────────────
  static const int maxReconnectAttempts = 50;
  static const int maxReconnectDelaySeconds = 30;

  // ── App ─────────────────────────────────────────────────────────────────
  static const String appVersion = '2.0.0';
  static const String appName = 'ANDA AKE';
  static const String appCodename = 'C2 // KARARGAH';
}
