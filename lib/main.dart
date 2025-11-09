import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

// 1. Import the new package
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

// Background message handler
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  print("✅ Handling a background message: ${message.messageId}");
}

// 2. Create a global instance of the plugin
final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
FlutterLocalNotificationsPlugin();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // 3. Initialize the plugin
  // The '@mipmap/ic_launcher' refers to the default app icon in the 'android/app/src/main/res' folders.
  const AndroidInitializationSettings initializationSettingsAndroid =
  AndroidInitializationSettings('@mipmap/ic_launcher');
  const InitializationSettings initializationSettings =
  InitializationSettings(android: initializationSettingsAndroid);
  await flutterLocalNotificationsPlugin.initialize(initializationSettings);

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

  // 4. Create the function that will build and show the notification
  void showLocalNotification(RemoteMessage message) async {
    final notification = message.notification;
    if (notification == null) return;

    // This part is where we define the 'look' of the notification.
    const AndroidNotificationDetails androidPlatformChannelSpecifics =
    AndroidNotificationDetails(
      'sar_channel_id', // A unique channel ID
      'SAR Alerts', // A user-visible channel name for the settings
      channelDescription: 'Channel for critical SAR alerts',
      importance: Importance.max, // Set the importance to the highest level
      priority: Priority.high, // Set the priority to high
      showWhen: true,
    );

    const NotificationDetails platformChannelSpecifics =
    NotificationDetails(android: androidPlatformChannelSpecifics);

    // This command actually shows the notification
    await flutterLocalNotificationsPlugin.show(
      notification.hashCode, // A unique ID for this specific notification
      notification.title,
      notification.body,
      platformChannelSpecifics,
    );
  }

  void setupFcm() async {
    final fcm = FirebaseMessaging.instance;
    await fcm.requestPermission();
    final token = await fcm.getToken();
    print("✅✅✅ FCM Token: $token ✅✅✅");

    // 5. THIS IS THE KEY CHANGE: Call our new function from the foreground listener
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      print('Got a message whilst in the foreground!');
      showLocalNotification(message); // <-- This is the new, important part
    });
  }

  // The UI build method can be simpler now
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: Text(widget.title),
      ),
      body: const Center(
        child: Padding(
          padding: EdgeInsets.all(16.0),
          child: Text(
            'ANDA-AKE is running.\nReady to receive notifications!',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 18),
          ),
        ),
      ),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});
  final String title;
  @override
  State<MyHomePage> createState() => _MyHomePageState();
}
