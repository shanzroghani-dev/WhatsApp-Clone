import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:whatsapp_clone/core/encryption_service.dart';
import 'package:whatsapp_clone/core/firebase_service.dart';
import 'package:whatsapp_clone/core/call_ringtone_service.dart';
import 'package:whatsapp_clone/firebase_options.dart';
import 'package:whatsapp_clone/chat/call_service.dart';
import 'package:whatsapp_clone/chat/call_service_utils.dart';

const AndroidNotificationChannel _defaultChannel = AndroidNotificationChannel(
  'chat_messages',
  'Chat Messages',
  description: 'Notifications for incoming chat messages',
  importance: Importance.high,
);

const AndroidNotificationChannel _callsChannel = AndroidNotificationChannel(
  'calls',
  'Voice and Video Calls',
  description: 'Notifications for incoming voice and video calls',
  importance: Importance.max,
  playSound: true,
  enableVibration: true,
  enableLights: true,
  showBadge: true,
  sound: RawResourceAndroidNotificationSound('notification'),
  ledColor: Color(0xFF25D366), // WhatsApp green
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

Map<String, dynamic>? _decodeNotificationPayload(String? payload) {
  if (payload == null || payload.isEmpty) return null;

  try {
    final decoded = jsonDecode(payload);
    if (decoded is Map<String, dynamic>) {
      return decoded;
    }
  } catch (_) {
    // Fallback for legacy map-like payload string: {key: value, ...}
  }

  final callIdMatch = RegExp(
    r'callId[:\s]+([a-zA-Z0-9-]+)',
  ).firstMatch(payload);
  if (callIdMatch == null) return null;

  return {'callId': callIdMatch.group(1)};
}

String? _extractCallIdFromPayload(String? payload) {
  final decoded = _decodeNotificationPayload(payload);
  final callId = decoded?['callId']?.toString();
  if (callId == null || callId.isEmpty) return null;
  return callId;
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
  await androidPlugin?.createNotificationChannel(_callsChannel);

  final title =
      message.notification?.title ?? message.data['title'] ?? 'New message';
  final body = prefs.previewEnabled
      ? _decryptMessageBody(message)
      : 'New message';

  await plugin.show(
    (message.messageId?.hashCode ?? DateTime.now().millisecondsSinceEpoch) %
        2147483647,
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
    payload: message.data.isEmpty ? null : jsonEncode(message.data),
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

  // Check if this is an incoming call notification
  final messageType = message.data['type']?.toString();
  if (messageType == 'incoming_call') {
    await NotificationService._handleIncomingCallNotification(message);
    return;
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

  // Track active call notifications to prevent duplicates
  static final Set<String> _activeCallNotifications = {};

  // Track call notification timers for auto-dismiss
  static final Map<String, Timer> _callNotificationTimers = {};

  // Prevent duplicate accept handling when notification callbacks fire twice.
  static final Set<String> _processingAcceptedCallIds = {};

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

    FirebaseMessaging.onMessage.listen((message) {
      print(
        '[FCM] 📬 FOREGROUND: messageId=${message.messageId}, title=${message.notification?.title}, from=${message.data['senderUID']}',
      );
      print('[FCM] 📬 FOREGROUND DATA: ${message.data}');

      // Check if this is an incoming call
      final messageType = message.data['type']?.toString();
      if (messageType == 'incoming_call') {
        // Don't show notification in foreground - HomeScreen listener will handle it
        print(
          '[FCM] ℹ️ Incoming call detected in foreground - skipping notification',
        );
        return;
      }

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

      // Check if this is an incoming call
      final messageType = message.data['type']?.toString();
      if (messageType == 'incoming_call') {
        // Stop ringtone when app is opened
        CallRingtoneService().stopRingtone();
      }

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

    await _localNotifications.initialize(
      initSettings,
      onDidReceiveNotificationResponse: _onNotificationTap,
      onDidReceiveBackgroundNotificationResponse: _onNotificationTap,
    );

    final androidPlugin = _localNotifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    await androidPlugin?.createNotificationChannel(_defaultChannel);
    await androidPlugin?.createNotificationChannel(_callsChannel);
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

    // Don't show local notification when app is in foreground
    // Only show SnackBar for better user experience
  }

  static Future<void> _handleIncomingCallNotification(
    RemoteMessage message,
  ) async {
    print('[FCM] 📞 Handling incoming call notification');

    final callId = message.data['callId']?.toString();
    final initiatorName =
        message.data['initiatorName']?.toString() ?? 'Unknown';
    final callType = message.data['callType']?.toString() ?? CallType.voice;
    final callTypeLabel = callType == CallType.video ? 'Video' : 'Voice';

    if (callId == null) {
      print('[FCM] ⚠️ No callId in incoming call notification');
      return;
    }

    // Prevent duplicate notifications for the same call
    if (_activeCallNotifications.contains(callId)) {
      print('[FCM] ⚠️ Call notification already shown for $callId');
      return;
    }
    _activeCallNotifications.add(callId);

    // Initialize plugin for background context
    final plugin = FlutterLocalNotificationsPlugin();

    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosInit = DarwinInitializationSettings();
    const initSettings = InitializationSettings(
      android: androidInit,
      iOS: iosInit,
    );

    await plugin.initialize(
      initSettings,
      onDidReceiveNotificationResponse: _onNotificationTap,
    );

    // Create notification channels
    final androidPlugin = plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    await androidPlugin?.createNotificationChannel(_callsChannel);

    print('[FCM] ✅ Plugin initialized for background call notification');

    // Start ringtone
    await CallRingtoneService().startRingtone(callId);

    // Create Android notification details for call alert
    final AndroidNotificationDetails
    androidDetails = AndroidNotificationDetails(
      'calls',
      'Voice and Video Calls',
      channelDescription: 'Notifications for incoming voice and video calls',
      importance: Importance.max,
      priority: Priority.max,
      playSound: false, // We handle sound via CallRingtoneService
      enableVibration: true,
      // Aggressive vibration pattern: silent, vibrate, silent, vibrate, silent, vibrate
      vibrationPattern: Int64List.fromList([0, 500, 200, 500, 200, 500]),
      fullScreenIntent: true,
      category: AndroidNotificationCategory.call,
      ongoing: true, // Makes notification persistent
      autoCancel: false, // Never auto-dismiss
      usesChronometer: true,
      showWhen: true,
      when: DateTime.now().millisecondsSinceEpoch,
      visibility: NotificationVisibility.public,
      ticker: 'Incoming $callTypeLabel Call',
      tag: 'call_$callId', // Unique tag prevents duplicate notifications
      // Make it look more like a native call notification
      colorized: true,
      color: const Color(0xFF25D366), // WhatsApp green
      ledOnMs: 1000,
      ledOffMs: 3000,

      // Style configuration for call appearance
      styleInformation: BigTextStyleInformation(
        '$initiatorName is calling...',
        htmlFormatBigText: true,
        contentTitle: initiatorName,
        summaryText: 'Incoming $callTypeLabel Call',
      ),

      // Action buttons for call
      actions: <AndroidNotificationAction>[
        AndroidNotificationAction(
          'accept_call',
          'Accept',
          showsUserInterface: true,
          cancelNotification: false,
        ),
        AndroidNotificationAction(
          'reject_call',
          'Reject',
          showsUserInterface: false,
          cancelNotification: false,
        ),
      ],
    );

    // iOS notification with call-specific settings
    const DarwinNotificationDetails iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
      sound: 'default',
      interruptionLevel: InterruptionLevel.timeSensitive,
      categoryIdentifier: 'CALL_INVITE',
    );

    await plugin.show(
      callId.hashCode.abs() % 2147483647,
      'Incoming $callTypeLabel Call',
      initiatorName,
      NotificationDetails(android: androidDetails, iOS: iosDetails),
      payload: jsonEncode(message.data),
    );

    print('[FCM] ✅ Incoming call notification shown with call alert style');

    // Set a timeout to auto-dismiss the notification after 45 seconds
    _callNotificationTimers[callId]?.cancel();
    _callNotificationTimers[callId] = Timer(const Duration(seconds: 45), () {
      print('[FCM] ⏱️ Call notification timeout for $callId');
      cancelCallNotification(callId);
    });
  }

  @pragma('vm:entry-point')
  static void _onNotificationTap(NotificationResponse response) {
    print(
      '[FCM] 📲 Notification tapped: ${response.actionId}, payload: ${response.payload}',
    );

    if (response.actionId == 'accept_call') {
      _handleAcceptCall(response.payload);
    } else if (response.actionId == 'reject_call') {
      _handleRejectCall(response.payload);
    } else {
      // Regular notification tap (no action button)
      if (_extractCallIdFromPayload(response.payload) != null) {
        _handleAcceptCall(response.payload);
      } else {
        _navigatorKey?.currentState?.pushNamed('/home');
      }
    }
  }

  static void _handleAcceptCall(String? payload) async {
    if (payload == null) return;

    print('[FCM] 🟢 Processing call acceptance from notification');

    try {
      final decoded = _decodeNotificationPayload(payload);
      if (decoded == null) {
        print('[FCM] ⚠️ Could not decode payload');
        return;
      }

      final callId = decoded['callId']?.toString();
      if (callId == null) {
        print('[FCM] ⚠️ No callId found in payload');
        return;
      }

      final prefs = await SharedPreferences.getInstance();
      final lastAcceptedCallId = prefs.getString('last_accepted_call_id');
      final lastAcceptedAt = prefs.getInt('last_accepted_call_at') ?? 0;
      final nowMs = DateTime.now().millisecondsSinceEpoch;

      if (_processingAcceptedCallIds.contains(callId)) {
        print('[FCM] ⚠️ Duplicate accept ignored (in-flight): $callId');
        return;
      }

      if (lastAcceptedCallId == callId && nowMs - lastAcceptedAt < 10000) {
        print('[FCM] ⚠️ Duplicate accept ignored (recent): $callId');
        return;
      }

      _processingAcceptedCallIds.add(callId);
      await prefs.setString('last_accepted_call_id', callId);
      await prefs.setInt('last_accepted_call_at', nowMs);

      // Cancel timeout timer and cleanup
      _callNotificationTimers[callId]?.cancel();
      _callNotificationTimers.remove(callId);
      _activeCallNotifications.remove(callId);

      // Stop ringtone
      await CallRingtoneService().stopRingtone();

      // Store the pending call acceptance in SharedPreferences
      // HomeScreen will check this after authentication and auto-join
      print('[FCM] 💾 Storing pending call acceptance: $callId');
      await prefs.setString('pending_call_id', callId);
      await prefs.setString('pending_call_data', payload);
      await prefs.setBool('pending_call_accepted', true);

      // Navigate to home - authentication will happen naturally
      // After auth, HomeScreen will detect the pending call and join it
      print('[FCM] 🏠 Navigating to home with pending call');
      _navigatorKey?.currentState?.pushNamedAndRemoveUntil(
        '/home',
        (route) => false,
      );

      _processingAcceptedCallIds.remove(callId);
    } catch (e) {
      print('[FCM] ❌ Error accepting call from notification: $e');

      final callId = _extractCallIdFromPayload(payload);
      if (callId != null) {
        _processingAcceptedCallIds.remove(callId);
      }

      // On error, just navigate to home
      _navigatorKey?.currentState?.pushNamedAndRemoveUntil(
        '/home',
        (route) => false,
      );
    }
  }

  static void _handleRejectCall(String? payload) async {
    if (payload == null) return;

    print('[FCM] 🔴 Processing call rejection from notification');

    try {
      // Stop ringtone
      await CallRingtoneService().stopRingtone();

      final callId = _extractCallIdFromPayload(payload);
      if (callId == null) {
        print('[FCM] ⚠️ No callId found in payload');
        return;
      }

      // Cancel timer and cleanup
      _callNotificationTimers[callId]?.cancel();
      _callNotificationTimers.remove(callId);
      _activeCallNotifications.remove(callId);

      // Get the call to retrieve initiatorId
      final call = await CallService.getCall(callId);
      if (call != null) {
        // Reject the call in Firebase
        await CallService.rejectCall(
          callId: callId,
          initiatorId: call.initiatorId,
        );
        print('[FCM] ✅ Call rejected in Firebase: $callId');
      }
    } catch (e) {
      print('[FCM] ❌ Error rejecting call: $e');
    }
  }

  /// Cancel incoming call notification
  static Future<void> cancelCallNotification(String callId) async {
    // Cancel the timeout timer if it exists
    _callNotificationTimers[callId]?.cancel();
    _callNotificationTimers.remove(callId);

    await _localNotifications.cancel(callId.hashCode.abs() % 2147483647);
    await CallRingtoneService().stopRingtone();
    _activeCallNotifications.remove(callId);
    print('[FCM] 🚫 Cancelled call notification for $callId');
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
      DateTime.now().millisecondsSinceEpoch % 2147483647,
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
