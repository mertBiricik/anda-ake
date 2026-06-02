/// Foreground Task Handler — Safety-Critical Background Service
///
/// Ensures the application remains active when the screen is off or app is in background.
/// Crucial for keeping the WebSocket connection alive and bypassing Android Doze mode.

import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config.dart';
import '../services/websocket_service.dart';
import '../services/notification_service.dart';
import '../models/alarm_message.dart';
import '../safety/acceptance_test.dart';

@pragma('vm:entry-point')
void startCallback() {
  FlutterForegroundTask.setTaskHandler(AndaBackgroundHandler());
}

class AndaBackgroundHandler extends TaskHandler {
  WebSocketService? _wsService;

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    debugPrint('[Background] Task Started');

    // Initialize Notification Service in isolate
    await NotificationService.initialize(
      onNotificationTapped: (payload) {
        if (payload != null) {
          FlutterForegroundTask.sendDataToMain({'type': 'NAVIGATION', 'payload': payload});
        }
      },
    );

    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('jwt_token') ?? '';

    // Re-establish WebSocket connection in the background isolate
    _wsService = WebSocketService(
      serverUrl: AppConfig.serverUrl,
      token: token,
      onAlarmReceived: (AlarmMessage alarm) {
        debugPrint('[Background] ALARM RECEIVED: ${alarm.title}');
        
        // Safety-Critical: Acceptance test before alerting
        final atResult = AlarmAcceptanceTest.validate(alarm);
        if (atResult.passed) {
          FlutterForegroundTask.sendDataToMain({'type': 'ALARM', 'data': alarm.toJson()});
          NotificationService.showAlarmNotification(
            id: alarm.hashCode,
            title: alarm.title,
            body: alarm.body,
            payload: alarm.body,
          );
        } else {
          debugPrint('[Background] Alarm failed AT: ${atResult.reason}');
        }
      },
      onConnectionStatusChanged: (status) {
        debugPrint('[Background] WS Status: $status');
        
        if (status == ConnectionStatus.disconnected) {
          FlutterForegroundTask.updateService(
            notificationTitle: 'ANDA AKE — OFFLINE',
            notificationText: 'Bağlantı koptu. Yeniden bağlanılıyor...',
          );
        } else if (status == ConnectionStatus.connected) {
          FlutterForegroundTask.updateService(
            notificationTitle: 'ANDA AKE — LIVE',
            notificationText: 'Karargah bağlantısı aktif. İzleniyor.',
          );
        }
      },
      onLog: (log) {
        FlutterForegroundTask.sendDataToMain({'type': 'LOG', 'message': log});
      },
    );

    _wsService?.connect();
  }

  @override
  void onRepeatEvent(DateTime timestamp) {
    // Keep-alive or periodic check logic can go here
  }

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {
    debugPrint('[Background] Task Destroyed');
    _wsService?.dispose();
    await NotificationService.cancelAll();
  }
}

class BackgroundManager {
  static void initForegroundTask() {
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'anda_ake_foreground',
        channelName: 'ANDA AKE C2 Service',
        channelDescription: 'Keeps connection alive for critical alerts.',
        channelImportance: NotificationChannelImportance.HIGH,
        priority: NotificationPriority.HIGH,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: true,
        playSound: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.repeat(5000),
        autoRunOnBoot: true,
        allowWakeLock: true,
        allowWifiLock: true,
      ),
    );
  }

  static Future<bool> startForegroundTask({
    required Function(Map<String, dynamic>) onMessage,
  }) async {
    // Check permissions
    if (!await FlutterForegroundTask.isIgnoringBatteryOptimizations) {
      await FlutterForegroundTask.requestIgnoreBatteryOptimization();
    }
    
    final NotificationPermission notificationPermissionStatus = await FlutterForegroundTask.checkNotificationPermission();
    if (notificationPermissionStatus != NotificationPermission.granted) {
      await FlutterForegroundTask.requestNotificationPermission();
    }

    if (await FlutterForegroundTask.isRunningService) {
      return true;
    }

    final ServiceRequestResult result = await FlutterForegroundTask.startService(
      notificationTitle: 'ANDA AKE — C2 System',
      notificationText: 'Servis başlatılıyor...',
      callback: startCallback,
    );

    if (result is ServiceRequestSuccess) {
      FlutterForegroundTask.receivePort?.listen((message) {
        if (message is Map<String, dynamic>) {
          onMessage(message);
        }
      });
      return true;
    }

    return false;
  }

  static Future<void> stopForegroundTask() async {
    await FlutterForegroundTask.stopService();
  }
}
