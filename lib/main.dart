
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:whatsapp_clone/screens/chat_list.dart';
import 'package:whatsapp_clone/screens/login.dart';
import 'package:whatsapp_clone/screens/register.dart';
import 'package:whatsapp_clone/auth/auth_service.dart';
import 'package:whatsapp_clone/chat/chat_service.dart';
import 'package:whatsapp_clone/core/local_db_service.dart';
import 'package:whatsapp_clone/core/notification_service.dart';
import 'package:whatsapp_clone/core/app_theme.dart';
import 'firebase_options.dart';

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
    await NotificationService.initialize();
  } catch (e) {
    print('Service initialization error: $e');
  }
  
  runApp(const MyApp());
}
class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'WhatsApp Username Clone',
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.system,
      home: const Root(),
      routes: {
        '/login': (_) => const LoginScreen(),
        '/register': (_) => const RegisterScreen(),
        '/chats': (_) => const ChatListScreen(),
      },
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
        if (mounted) {
          Navigator.of(context).pushReplacementNamed('/chats');
        }
      } else {
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
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: _loading ? const CircularProgressIndicator() : const SizedBox.shrink(),
      ),
    );
  }
}
