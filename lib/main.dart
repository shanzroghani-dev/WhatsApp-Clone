import 'dart:async';

import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:provider/provider.dart';
import 'package:whatsapp_clone/screens/home_screen.dart';
import 'package:whatsapp_clone/screens/login.dart';
import 'package:whatsapp_clone/screens/register.dart';
import 'package:whatsapp_clone/auth/auth_service.dart';
import 'package:whatsapp_clone/chat/chat_service.dart';
import 'package:whatsapp_clone/core/firebase_service.dart';
import 'package:whatsapp_clone/core/local_db_service.dart';
import 'package:whatsapp_clone/core/notification_service.dart';
import 'package:whatsapp_clone/core/app_theme.dart';
import 'package:whatsapp_clone/providers/providers.dart';
import 'firebase_options.dart';

final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();
final GlobalKey<ScaffoldMessengerState> appScaffoldMessengerKey =
    GlobalKey<ScaffoldMessengerState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize all services
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } catch (_) {
    // Firebase not configured; app runs with local storage only
  }

  try {
    await LocalDBService.init();
    await ChatService.initialize();
    await ChatService.syncPendingOutgoing();
    await NotificationService.initialize(
      navigatorKey: appNavigatorKey,
      scaffoldMessengerKey: appScaffoldMessengerKey,
    );
  } catch (e) {
    print('Service initialization error: $e');
  }

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: getAppProviders(),
      child: MaterialApp(
        navigatorKey: appNavigatorKey,
        scaffoldMessengerKey: appScaffoldMessengerKey,
        title: 'WhatsApp Username Clone',
        theme: AppTheme.lightTheme,
        darkTheme: AppTheme.darkTheme,
        themeMode: ThemeMode.system,
        home: const Root(),
        routes: {
          '/login': (_) => const LoginScreen(),
          '/register': (_) => const RegisterScreen(),
          '/home': (_) => const HomeScreen(),
        },
      ),
    );
  }
}

class Root extends StatefulWidget {
  const Root({super.key});

  @override
  State<Root> createState() => _RootState();
}

class _RootState extends State<Root> {
  bool _loading = true;
  StreamSubscription<Map<String, dynamic>>? _statusSubscription;

  @override
  void initState() {
    super.initState();
    _checkAuth();
  }

  Future<void> _checkAuth() async {
    try {
      final user = await AuthService.getCurrentUser();
      setState(() => _loading = false);

      if (user != null) {
        NotificationService.setCurrentUserUid(user.uid);
        _subscribeToGlobalStatusUpdates(user.uid);
        // Sync any missed incoming messages
        await ChatService.syncIncomingMessages(user.uid);
        if (mounted) {
          Navigator.of(context).pushReplacementNamed('/home');
        }
      } else {
        _statusSubscription?.cancel();
        _statusSubscription = null;
        NotificationService.setCurrentUserUid(null);
        if (mounted) {
          Navigator.of(context).pushReplacementNamed('/login');
        }
      }
    } catch (e) {
      print('Auth check error: $e');
      setState(() => _loading = false);
      if (mounted) {
        Navigator.of(context).pushReplacementNamed('/login');
      }
    }
  }

  void _subscribeToGlobalStatusUpdates(String currentUserUid) {
    _statusSubscription?.cancel();
    _statusSubscription = FirebaseService.listenForStatusUpdates(
      currentUserUid,
    ).listen((statusUpdate) {
      final messageId = statusUpdate['messageId'] as String?;
      final localMessageId = statusUpdate['localMessageId'] as String?;
      final delivered = statusUpdate['delivered'] as bool? ?? false;
      final read = statusUpdate['read'] as bool? ?? false;

      final targetId = messageId ?? localMessageId;
      if (targetId == null || targetId.isEmpty) return;

      unawaited(ChatService.updateMessageStatus(targetId, delivered, read));
    });
  }

  @override
  void dispose() {
    _statusSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: _loading
            ? const CircularProgressIndicator()
            : const SizedBox.shrink(),
      ),
    );
  }
}
