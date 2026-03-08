import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:whatsapp_clone/core/encryption_service.dart';
import 'package:whatsapp_clone/core/firebase_service.dart';
import 'package:whatsapp_clone/firebase_options.dart';

const AndroidNotificationChannel _defaultChannel = AndroidNotificationChannel(
  'chat_messages',
  'Chat Messages',
  description: 'Notifications for incoming chat messages',
  importance: Importance.high,
);

String _decryptMessageBody(RemoteMessage message) {
  try {
    final cipher = message.data['cipher']?.toString();
    final iv = message.data['iv']?.toString();
    final senderUid = message.data['senderUID']?.toString();
    final receiverUid = message.data['receiverUID']?.toString();

    print(
      '[FCM] 🔐 decrypt attempt: cipher=${cipher?.isNotEmpty ?? false}, iv=${iv?.isNotEmpty ?? false}, sender=$senderUid, receiver=$receiverUid',
    );

    // If we have encrypted data, decrypt it
    if (cipher != null &&
        cipher.isNotEmpty &&
        iv != null &&
        iv.isNotEmpty &&
        senderUid != null &&
        senderUid.isNotEmpty &&
        receiverUid != null &&
        receiverUid.isNotEmpty) {
      final decrypted = EncryptionService.decryptForUsers(
        cipher,
        iv,
        senderUid,
        receiverUid,
      );
      if (decrypted != null && decrypted.isNotEmpty) {
        print('[FCM] ✅ decrypted: $decrypted');
        return decrypted;
      } else {
        print('[FCM] ❌ decryption returned null');
      }
    } else {
      print('[FCM] ⚠️ missing encryption data in payload');
    }
  } catch (e) {
    print('[FCM] ❌ Decryption error: $e');
  }

  // Fallback to plaintext body if decryption fails or no encrypted data
  final fallback =
      message.notification?.body ?? message.data['body'] ?? 'New message';
  print('[FCM] 📝 using fallback: $fallback');
  return fallback;
}

class _NotificationPrefs {
  _NotificationPrefs({
    required this.messagesEnabled,
    required this.soundEnabled,
    required this.vibrationEnabled,
    required this.previewEnabled,
  });

  final bool messagesEnabled;
  final bool soundEnabled;
  final bool vibrationEnabled;
  final bool previewEnabled;
}

Future<_NotificationPrefs> _loadNotificationPrefs() async {
  final prefs = await SharedPreferences.getInstance();
  return _NotificationPrefs(
    messagesEnabled: prefs.getBool('notifications_messages') ?? true,
    soundEnabled: prefs.getBool('notifications_sound') ?? true,
    vibrationEnabled: prefs.getBool('notifications_vibration') ?? true,
    previewEnabled: prefs.getBool('notifications_preview') ?? true,
  );
}

Future<void> _showBackgroundLocalNotification(RemoteMessage message) async {
  final prefs = await _loadNotificationPrefs();
  if (!prefs.messagesEnabled) {
    return;
  }

  if (message.notification != null) {
    return;
  }

  final plugin = FlutterLocalNotificationsPlugin();

  const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
  const iosInit = DarwinInitializationSettings();
  const initSettings = InitializationSettings(
    android: androidInit,
    iOS: iosInit,
  );

  await plugin.initialize(initSettings);

  final androidPlugin = plugin
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >();
  await androidPlugin?.createNotificationChannel(_defaultChannel);

  final title =
      message.notification?.title ?? message.data['title'] ?? 'New message';
  final body = prefs.previewEnabled
      ? _decryptMessageBody(message)
      : 'New message';

  await plugin.show(
    message.messageId?.hashCode ?? DateTime.now().millisecondsSinceEpoch,
    title,
    body,
    NotificationDetails(
      android: AndroidNotificationDetails(
        _defaultChannel.id,
        _defaultChannel.name,
        channelDescription: _defaultChannel.description,
        importance: Importance.high,
        priority: Priority.high,
        playSound: prefs.soundEnabled,
        enableVibration: prefs.vibrationEnabled,
      ),
      iOS: DarwinNotificationDetails(presentSound: prefs.soundEnabled),
    ),
    payload: message.data.isEmpty ? null : message.data.toString(),
  );
}

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  print(
    '[FCM] 📬 BACKGROUND: messageId=${message.messageId}, title=${message.notification?.title}',
  );
  print('[FCM] 📬 BACKGROUND DATA: ${message.data}');

  // Ensure Firebase is initialized in background context
  try {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
      print('[FCM] Firebase initialized in background handler');
    }
  } catch (e) {
    print('[FCM] Firebase init in background failed: $e');
  }

  await NotificationService.markDeliveredFromNotification(message);
  await _showBackgroundLocalNotification(message);
}

class NotificationService {
  static final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  static final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  static GlobalKey<ScaffoldMessengerState>? _scaffoldMessengerKey;
  static GlobalKey<NavigatorState>? _navigatorKey;

  static String? _currentUserUid;
  static String? _activeChatPeerUid;

  static bool _initialized = false;
  static StreamSubscription<String>? _tokenRefreshSubscription;

  static Future<void> initialize({
    GlobalKey<ScaffoldMessengerState>? scaffoldMessengerKey,
    GlobalKey<NavigatorState>? navigatorKey,
  }) async {
    _scaffoldMessengerKey = scaffoldMessengerKey;
    _navigatorKey = navigatorKey;

    if (_initialized) return;
    _initialized = true;

    await _messaging.requestPermission(alert: true, badge: true, sound: true);
    await _messaging.setAutoInitEnabled(true);

    await refreshNotificationPreferences();

    await _initializeLocalNotifications();

    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

    FirebaseMessaging.onMessage.listen((message) {
      print(
        '[FCM] 📬 FOREGROUND: messageId=${message.messageId}, title=${message.notification?.title}, from=${message.data['senderUID']}',
      );
      print('[FCM] 📬 FOREGROUND DATA: ${message.data}');
      unawaited(markDeliveredFromNotification(message));
      _handleForegroundMessage(message);
    });

    _tokenRefreshSubscription?.cancel();
    _tokenRefreshSubscription = _messaging.onTokenRefresh.listen((token) {
      print('[FCM] onTokenRefresh uid=$_currentUserUid token=$token');
      unawaited(_saveTokenForCurrentUser(token));
    });

    await _syncTokenIfPossible();

    FirebaseMessaging.onMessageOpenedApp.listen((message) {
      print(
        '[FCM] 📬 OPENED: messageId=${message.messageId}, title=${message.notification?.title}',
      );
      print('[FCM] 📬 OPENED DATA: ${message.data}');
      unawaited(markDeliveredFromNotification(message));
      _navigatorKey?.currentState?.pushNamed('/home');
    });

    final initialMessage = await _messaging.getInitialMessage();
    if (initialMessage != null) {
      print(
        '[FCM] 📬 LAUNCH: messageId=${initialMessage.messageId}, title=${initialMessage.notification?.title}',
      );
      print('[FCM] 📬 LAUNCH DATA: ${initialMessage.data}');
      unawaited(markDeliveredFromNotification(initialMessage));
      _navigatorKey?.currentState?.pushNamed('/home');
    }
  }

  static Future<void> _initializeLocalNotifications() async {
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosInit = DarwinInitializationSettings();
    const initSettings = InitializationSettings(
      android: androidInit,
      iOS: iosInit,
    );

    await _localNotifications.initialize(initSettings);

    final androidPlugin = _localNotifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    await androidPlugin?.createNotificationChannel(_defaultChannel);
  }

  static void setCurrentUserUid(String? uid) {
    _currentUserUid = uid;
    if (uid != null && uid.isNotEmpty) {
      unawaited(_syncTokenIfPossible());
    }
  }

  static Future<void> _syncTokenIfPossible() async {
    final uid = _currentUserUid;
    if (uid == null || uid.isEmpty) return;

    final token = await _messaging.getToken();
    if (token == null || token.isEmpty) return;

    print('[FCM] syncToken uid=$uid token=$token');

    await _saveTokenForCurrentUser(token);
  }

  static Future<void> _saveTokenForCurrentUser(String token) async {
    final uid = _currentUserUid;
    if (uid == null || uid.isEmpty) return;

    try {
      await FirebaseService.updateUserProfile(uid: uid, fcmToken: token);
      print('[FCM] saved token uid=$uid token=$token');
    } catch (_) {}
  }

  static void setActiveChat({
    required String currentUserUid,
    required String peerUid,
  }) {
    _currentUserUid = currentUserUid;
    _activeChatPeerUid = peerUid;
  }

  static void clearActiveChat({String? peerUid}) {
    if (peerUid == null || _activeChatPeerUid == peerUid) {
      _activeChatPeerUid = null;
    }
  }

  static void _handleForegroundMessage(RemoteMessage message) {
    unawaited(_handleForegroundMessageAsync(message));
  }

  static Future<void> _handleForegroundMessageAsync(
    RemoteMessage message,
  ) async {
    final prefs = await _loadNotificationPrefs();
    if (!prefs.messagesEnabled) return;

    if (_shouldSuppressForActiveChat(message)) {
      return;
    }

    final title =
        message.notification?.title ?? message.data['title'] ?? 'New message';
    final body = prefs.previewEnabled
        ? _decryptMessageBody(message)
        : 'New message';

    _scaffoldMessengerKey?.currentState?.showSnackBar(
      SnackBar(
        content: Text('$title\n$body'),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
      ),
    );

    await _localNotifications.show(
      message.messageId?.hashCode ?? DateTime.now().millisecondsSinceEpoch,
      title,
      body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          _defaultChannel.id,
          _defaultChannel.name,
          channelDescription: _defaultChannel.description,
          importance: Importance.high,
          priority: Priority.high,
          playSound: prefs.soundEnabled,
          enableVibration: prefs.vibrationEnabled,
        ),
        iOS: DarwinNotificationDetails(presentSound: prefs.soundEnabled),
      ),
      payload: message.data.isEmpty ? null : message.data.toString(),
    );
  }

  static Future<void> refreshNotificationPreferences() async {
    final prefs = await _loadNotificationPrefs();
    await _messaging.setForegroundNotificationPresentationOptions(
      alert: prefs.messagesEnabled,
      badge: prefs.messagesEnabled,
      sound: prefs.messagesEnabled && prefs.soundEnabled,
    );
  }

  static Future<void> sendTestNotification() async {
    final prefs = await _loadNotificationPrefs();
    if (!prefs.messagesEnabled) {
      _scaffoldMessengerKey?.currentState?.showSnackBar(
        const SnackBar(content: Text('Notifications are currently disabled')),
      );
      return;
    }

    await _localNotifications.show(
      DateTime.now().millisecondsSinceEpoch,
      'WhatsApp Clone',
      prefs.previewEnabled ? 'This is a test notification' : 'New message',
      NotificationDetails(
        android: AndroidNotificationDetails(
          _defaultChannel.id,
          _defaultChannel.name,
          channelDescription: _defaultChannel.description,
          importance: Importance.high,
          priority: Priority.high,
          playSound: prefs.soundEnabled,
          enableVibration: prefs.vibrationEnabled,
        ),
        iOS: DarwinNotificationDetails(presentSound: prefs.soundEnabled),
      ),
    );
  }

  static bool _shouldSuppressForActiveChat(RemoteMessage message) {
    if (_activeChatPeerUid == null) return false;

    final senderUid =
        message.data['senderUID'] ??
        message.data['fromId'] ??
        message.data['senderUid'];
    final receiverUid =
        message.data['receiverUID'] ??
        message.data['toId'] ??
        message.data['receiverUid'];

    if (senderUid == null) return false;
    if (_activeChatPeerUid != senderUid) return false;

    if (_currentUserUid == null) return true;
    if (receiverUid == null) return true;

    return _currentUserUid == receiverUid;
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

  static Future<void> markDeliveredFromNotification(
    RemoteMessage message,
  ) async {
    try {
      final messageId =
          message.data['messageId']?.toString() ??
          message.messageId?.toString();
      final senderUid =
          message.data['senderUID']?.toString() ??
          message.data['fromId']?.toString() ??
          message.data['senderUid']?.toString();
      final receiverUid =
          message.data['receiverUID']?.toString() ??
          message.data['toId']?.toString() ??
          message.data['receiverUid']?.toString() ??
          _currentUserUid;

      if (messageId == null || messageId.isEmpty) {
        print('[FCM] ❌ markDelivered: messageId is null/empty');
        return;
      }
      if (receiverUid == null || receiverUid.isEmpty) {
        print('[FCM] ❌ markDelivered: receiverUid is null/empty');
        return;
      }

      print(
        '[FCM] ✅ markDelivered: msgId=$messageId, receiver=$receiverUid, sender=$senderUid',
      );
      await FirebaseService.markAsDelivered(messageId);
    } catch (e) {
      print('[FCM] ❌ markDelivered error: $e');
    }
  }
}
