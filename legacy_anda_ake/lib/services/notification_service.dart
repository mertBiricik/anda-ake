/// Notification Service — Local notification handling (Firebase-free)
///
/// Shows local notifications when alarms arrive while the app is
/// in background. Uses fullScreenIntent for lock screen wake-up.
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class NotificationService {
  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  static const AndroidNotificationChannel channel = AndroidNotificationChannel(
    'sar_channel_critical',
    'CRITICAL SAR ALERTS',
    description: 'This channel is used for critical search and rescue alerts.',
    importance: Importance.max,
    playSound: true,
    sound: RawResourceAndroidNotificationSound('alarm'),
    audioAttributesUsage: AudioAttributesUsage.alarm,
  );

  /// Initialize the notification plugin
  static Future<void> initialize({
    required void Function(String? payload) onNotificationTapped,
  }) async {
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const settings = InitializationSettings(android: androidSettings);

    await _plugin.initialize(
      settings,
      onDidReceiveNotificationResponse: (NotificationResponse response) {
        onNotificationTapped(response.payload);
      },
    );

    // Create the notification channel
    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);
  }

  /// Show a critical alarm notification with full screen intent
  static Future<void> showAlarmNotification({
    required int id,
    required String title,
    required String body,
    String? payload,
  }) async {
    await _plugin.show(
      id,
      title,
      body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          channel.id,
          channel.name,
          channelDescription: channel.description,
          icon: '@mipmap/ic_launcher',
          priority: Priority.max,
          importance: Importance.max,
          fullScreenIntent: true,
          category: AndroidNotificationCategory.alarm,
          visibility: NotificationVisibility.public,
          audioAttributesUsage: AudioAttributesUsage.alarm,
          ongoing: true,
          autoCancel: false,
        ),
      ),
      payload: payload,
    );
  }

  /// Cancel all notifications
  static Future<void> cancelAll() async {
    await _plugin.cancelAll();
  }

  /// Check if the app was launched via a notification
  static Future<String?> getInitialPayload() async {
    final details = await _plugin.getNotificationAppLaunchDetails();
    if (details?.didNotificationLaunchApp ?? false) {
      return details?.notificationResponse?.payload;
    }
    return null;
  }
}
