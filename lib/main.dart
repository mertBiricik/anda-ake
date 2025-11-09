import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

// THIS IS THE KEY CHANGE!
// We now make the background handler call the same 'showLocalNotification' function.
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  print("✅ Handling a background message: ${message.messageId}");

  // Create an instance of the plugin (required for background isolates)
  final FlutterLocalNotificationsPlugin _flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();

  // Call the function to show the notification
  showLocalNotification(message, _flutterLocalNotificationsPlugin);
}

// Global instance for the main app isolate
final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();

const AndroidNotificationChannel channel = AndroidNotificationChannel(
  'sar_channel_critical',
  'CRITICAL SAR ALERTS',
  description: 'This channel is used for critical search and rescue alerts.',
  importance: Importance.max,
  playSound: true,
  sound: RawResourceAndroidNotificationSound('alarm'),
);

// We turn showLocalNotification into a top-level function so it can be called from the background.
// It now accepts the plugin instance as an argument.
void showLocalNotification(RemoteMessage message, FlutterLocalNotificationsPlugin pluginInstance) async {
  // If we are using a data-only message, the 'notification' property will be null.
  // We need to get the title and body from the 'data' payload instead.
  String title = message.data['title'] ?? message.notification?.title ?? 'No Title';
  String body = message.data['body'] ?? message.notification?.body ?? 'No Body';

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
      ),
    ),
  );
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  const AndroidInitializationSettings initializationSettingsAndroid = AndroidInitializationSettings('@mipmap/ic_launcher');
  const InitializationSettings initializationSettings = InitializationSettings(android: initializationSettingsAndroid);
  await flutterLocalNotificationsPlugin.initialize(initializationSettings);

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
      title: 'ANDA AKE',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepOrange),
        useMaterial3: true,
      ),
      home: const MyHomePage(title: 'ANDA AKE'),
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

    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      print('Got a message whilst in the foreground!');
      // The foreground handler now calls the top-level function, passing its own plugin instance.
      showLocalNotification(message, flutterLocalNotificationsPlugin);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: Text(widget.title),
      ),
      body: const Center( /* ... UI code ... */ ),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});
  final String title;
  @override
  State<MyHomePage> createState() => _MyHomePageState();
}
