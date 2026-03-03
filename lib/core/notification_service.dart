import 'package:firebase_messaging/firebase_messaging.dart';

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {}

class NotificationService {
  static final FirebaseMessaging _messaging = FirebaseMessaging.instance;

  static Future<void> initialize() async {
    await _messaging.requestPermission();
    await FirebaseMessaging.instance.setAutoInitEnabled(true);
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
  }

  static Future<String?> getToken() {
    return _messaging.getToken();
  }

  static Stream<RemoteMessage> foregroundMessages() {
    return FirebaseMessaging.onMessage;
  }

  static Stream<RemoteMessage> openedFromNotification() {
    return FirebaseMessaging.onMessageOpenedApp;
  }
}
