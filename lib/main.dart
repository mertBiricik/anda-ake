import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

// Import your new alarm screen
import 'alarm_screen.dart';

// 1. Create a GlobalKey to access the Navigator from anywhere (even outside the UI tree)
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
FlutterLocalNotificationsPlugin();

const AndroidNotificationChannel channel = AndroidNotificationChannel(
  'sar_channel_critical',
  'CRITICAL SAR ALERTS',
  description: 'This channel is used for critical search and rescue alerts.',
  importance: Importance.max,
  playSound: true,
  sound: RawResourceAndroidNotificationSound('alarm'), // Plays the sound once for the notification
);

// Background handler
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  print("✅ Handling a background message: ${message.messageId}");

  // We must create a new instance of the plugin for the background isolate
  final FlutterLocalNotificationsPlugin backgroundPlugin = FlutterLocalNotificationsPlugin();

  // Call the helper to show the notification
  showLocalNotification(message, backgroundPlugin);
}

// Top-level function to show the notification
void showLocalNotification(RemoteMessage message, FlutterLocalNotificationsPlugin pluginInstance) async {
  String title = message.data['title'] ?? message.notification?.title ?? 'CRITICAL ALERT';
  String body = message.data['body'] ?? message.notification?.body ?? 'Emergency assistance required.';

  await pluginInstance.show(
    message.hashCode,
    title,
    body,
    NotificationDetails(
      android: AndroidNotificationDetails(
        channel.id,
        channel.name,
        channelDescription: channel.description,
        icon: '@mipmap/ic_launcher',
        priority: Priority.high,
        importance: Importance.max,

        // 🚨 THIS IS THE MAGIC 🚨
        // This tells Android to try and launch the app immediately (Full Screen Intent)
        // If the screen is locked, this is what triggers the "Wake Up" behavior
        fullScreenIntent: true,

        // Keep the notification visible until acknowledged
        ongoing: true,
        autoCancel: false,
      ),
    ),
    // We pass the body as the payload so the AlarmScreen can display it
    payload: body,
  );
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  const AndroidInitializationSettings initializationSettingsAndroid =
  AndroidInitializationSettings('@mipmap/ic_launcher');

  const InitializationSettings initializationSettings =
  InitializationSettings(android: initializationSettingsAndroid);

  await flutterLocalNotificationsPlugin.initialize(
    initializationSettings,
    // 2. Handle what happens when the user taps the notification
    onDidReceiveNotificationResponse: (NotificationResponse response) {
      if (response.payload != null) {
        // Navigate to the Alarm Screen using the global key
        navigatorKey.currentState?.pushNamed('/alarm', arguments: response.payload);
      }
    },
  );

  await flutterLocalNotificationsPlugin
  .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
  ?.createNotificationChannel(channel);

  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      // 3. Assign the navigator key
      navigatorKey: navigatorKey,
      title: 'ANDA AKE',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepOrange),
        useMaterial3: true,
      ),
      // 4. Define the Routes
      initialRoute: '/',
      routes: {
        '/': (context) => const MyHomePage(title: 'ANDA AKE Home'),
        '/alarm': (context) {
          // Extract the message passed from the notification
          final message = ModalRoute.of(context)!.settings.arguments as String? ?? "CRITICAL MISSION";
          return AlarmScreen(missionMessage: message);
        },
      },
    );
  }
}

class _MyHomePageState extends State<MyHomePage> {
  @override
  void initState() {
    super.initState();
    setupFcm();
  }

  void setupFcm() async {
    final fcm = FirebaseMessaging.instance;
    await fcm.requestPermission();
    final token = await fcm.getToken();
    print("✅✅✅ FCM Token: $token ✅✅✅");

    // Handle Foreground Messages
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      print('Got a message whilst in the foreground!');

      // For foreground, we don't need a notification; we just go straight to the screen!
      String body = message.data['body'] ?? "Emergency Alert";
      navigatorKey.currentState?.pushNamed('/alarm', arguments: body);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: const Center(child: Text("Ready for alerts.")),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});
  final String title;
  @override
  State<MyHomePage> createState() => _MyHomePageState();
}
