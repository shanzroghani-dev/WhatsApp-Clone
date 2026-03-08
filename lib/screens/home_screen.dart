import 'package:flutter/material.dart';
import 'package:whatsapp_clone/core/security_service.dart';
import 'chat_list.dart';
import 'profile_screen.dart';
import 'security_unlock_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  int _currentIndex = 0;
  bool _isUnlockDialogOpen = false;

  late final List<Widget> _screens = [
    const ChatListScreen(),
    const ProfileScreen(),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _ensureUnlocked();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _ensureUnlocked();
    }
  }

  Future<void> _ensureUnlocked() async {
    if (_isUnlockDialogOpen || !mounted) return;
    final lockEnabled = await SecurityService.isScreenLockEnabled();
    final hasPin = await SecurityService.hasPin();
    if (!lockEnabled || !hasPin) return;

    _isUnlockDialogOpen = true;
    final unlocked = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const SecurityUnlockScreen()),
    );
    _isUnlockDialogOpen = false;

    if (!mounted) return;
    if (unlocked != true) {
      Navigator.of(context).pushReplacementNamed('/login');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _screens[_currentIndex],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) {
          setState(() {
            _currentIndex = index;
          });
        },
        items: [
          BottomNavigationBarItem(
            icon: const Icon(Icons.chat),
            label: 'Chats',
            backgroundColor: Theme.of(context).scaffoldBackgroundColor,
          ),
          BottomNavigationBarItem(
            icon: const Icon(Icons.person),
            label: 'Profile',
            backgroundColor: Theme.of(context).scaffoldBackgroundColor,
          ),
        ],
      ),
    );
  }
}
