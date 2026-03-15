import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:whatsapp_clone/auth/auth_service.dart';
import 'package:whatsapp_clone/chat/call_service.dart';
import 'package:whatsapp_clone/chat/call_service_utils.dart';
import 'package:whatsapp_clone/core/agora_service.dart';
import 'package:whatsapp_clone/core/security_service.dart';
import 'package:whatsapp_clone/models/call_model.dart';
import 'package:whatsapp_clone/screens/call/incoming_call_screen.dart';
import 'package:whatsapp_clone/screens/call/enhanced_in_call_screen.dart';
import 'call_history_screen.dart';
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
  bool _isInCallScreen = false;
  StreamSubscription<CallModel>? _incomingCallSubscription;

  late final List<Widget> _screens = [
    const ChatListScreen(),
    const CallHistoryScreen(),
    const ProfileScreen(),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _ensureUnlocked();
      _checkForPendingCall();
      _initializeCallListener();
    });
  }

  @override
  void dispose() {
    _incomingCallSubscription?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _ensureUnlocked();
      _checkForActiveCall();
    }
  }

  Future<void> _checkForPendingCall() async {
    try {
      print('[HomeScreen] 🔍 Checking for pending call from notification');
      final prefs = await SharedPreferences.getInstance();

      final pendingCallId = prefs.getString('pending_call_id');
      final pendingCallAccepted =
          prefs.getBool('pending_call_accepted') ?? false;

      if (pendingCallId != null && pendingCallAccepted) {
        print('[HomeScreen] ✅ Found pending call acceptance: $pendingCallId');

        // Clear the pending call flags
        await prefs.remove('pending_call_id');
        await prefs.remove('pending_call_data');
        await prefs.remove('pending_call_accepted');

        // Get current user
        final currentUser = await AuthService.getCurrentUser();
        if (currentUser == null || !mounted) {
          print('[HomeScreen] ⚠️ No user authenticated yet');
          return;
        }

        // Accept the call in Firebase
        try {
          await CallService.acceptCall(
            callId: pendingCallId,
            receiverId: currentUser.uid,
          );
          print('[HomeScreen] ✅ Call accepted in Firebase: $pendingCallId');
        } catch (e) {
          print('[HomeScreen] ⚠️ Error accepting call: $e');
        }

        // Get the call and join it
        final call = await CallService.getCall(pendingCallId);
        if (call != null && mounted) {
          print('[HomeScreen] 📞 Joining pending call...');
          await _joinActiveCall(call);
        } else {
          print('[HomeScreen] ⚠️ Pending call not found or expired');
        }
      } else {
        print('[HomeScreen] ℹ️ No pending call found');
      }
    } catch (e) {
      print('[HomeScreen] ❌ Error checking pending call: $e');
    }
  }

  Future<void> _checkForActiveCall() async {
    try {
      // Don't check if already in a call screen
      if (_isInCallScreen) return;

      final user = await AuthService.getCurrentUser();
      if (user == null || !mounted) return;

      // Check if there's an active call for this user
      final activeCall = await CallService.getActiveCall(user.uid);
      if (activeCall == null || !mounted) return;

      // If there's an active call, rejoin it
      if (activeCall.status == CallStatus.active &&
          activeCall.answeredAt != null) {
        print('[HomeScreen] Detected active call on resume, rejoining...');
        await _joinActiveCall(activeCall);
      } else if (activeCall.status == CallStatus.ringing &&
          activeCall.receiverId == user.uid) {
        // Show incoming call screen if call is still ringing
        print(
          '[HomeScreen] Detected ringing call on resume, showing incoming screen...',
        );
        _showIncomingCallScreen(activeCall);
      }
    } catch (e) {
      print('[HomeScreen] Error checking for active call: $e');
    }
  }

  Future<void> _initializeCallListener() async {
    try {
      final user = await AuthService.getCurrentUser();
      if (user == null || !mounted) return;

      _incomingCallSubscription = CallService.listenForIncomingCalls(user.uid).listen((
        call,
      ) {
        if (!mounted) return;

        // Prevent duplicate navigation if already in a call screen
        if (_isInCallScreen) {
          print(
            '[HomeScreen] Already in call screen, ignoring new call notification',
          );
          return;
        }

        // If call is ringing, show incoming call screen
        if (call.status == CallStatus.ringing) {
          _showIncomingCallScreen(call);
        }
        // If call is already active (e.g., accepted from notification), join it directly
        else if (call.status == CallStatus.active && call.answeredAt != null) {
          _joinActiveCall(call);
        }
      });
    } catch (e) {
      print('[HomeScreen] Error initializing call listener: $e');
    }
  }

  Future<void> _joinActiveCall(CallModel call) async {
    try {
      // Prevent duplicate navigation
      if (_isInCallScreen) {
        print('[HomeScreen] Already in call screen, skipping navigation');
        return;
      }

      print('[HomeScreen] Joining active call: ${call.callId}');

      // Get current user
      final currentUser = await AuthService.getCurrentUser();
      if (currentUser == null || !mounted) return;

      // Convert user IDs to integers for Agora
      final localUid = CallService.agoraUidFromUserId(currentUser.uid);
      final remoteUid = CallService.agoraUidFromUserId(call.initiatorId);

      // Mark that we're entering call screen
      setState(() => _isInCallScreen = true);

      // Show loading indicator
      if (mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (_) => const AlertDialog(
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('Connecting to call...'),
              ],
            ),
          ),
        );
      }

      try {
        // Get Agora token with timeout error handling
        final token = await CallService.getAgoraToken(
          channelName: call.callId,
          uid: localUid,
        );

        // Initialize and setup Agora service
        final agoraService = AgoraService();
        await agoraService.initialize();
        await agoraService.joinChannel(
          channelName: call.callId,
          uid: localUid,
          token: token,
          isVideoCall: call.callType == CallType.video,
        );

        if (!mounted) return;

        // Close loading dialog
        Navigator.of(context).pop();

        // Navigate to in-call screen
        await Navigator.of(context).push(
          MaterialPageRoute(
            fullscreenDialog: true,
            builder: (_) => EnhancedInCallScreen(
              callModel: call,
              agoraService: agoraService,
              remoteUid: remoteUid,
              onEndCall: () async {
                try {
                  await CallService.endCall(
                    callId: call.callId,
                    endReason: CallEndReason.userEnded,
                  );
                  await agoraService.dispose();
                } catch (e) {
                  print('[HomeScreen] Error in onEndCall: $e');
                }

                // Safely pop after current frame
                if (context.mounted) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (context.mounted && Navigator.of(context).canPop()) {
                      Navigator.of(context).pop();
                    }
                  });
                }
              },
            ),
          ),
        );

        // Call screen was closed, clear the flag
        if (mounted) {
          setState(() => _isInCallScreen = false);
        }
      } catch (e) {
        // Close loading dialog if still open
        if (mounted && Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
        }

        // Clear the flag on error
        if (mounted) {
          setState(() => _isInCallScreen = false);
        }

        // Error handling
        print('[HomeScreen] Error joining call: $e');
        final errorMessage = e.toString().contains('timed out')
            ? 'Connection timeout. Please check your internet and try again.'
            : e.toString().contains('token')
            ? 'Failed to get call credentials. Please try again.'
            : 'Failed to join call. Please try again.';

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(errorMessage),
              duration: const Duration(seconds: 4),
            ),
          );
        }
      }
    } catch (e) {
      print('[HomeScreen] Unexpected error in _joinActiveCall: $e');

      // Clear the flag on error
      if (mounted) {
        setState(() => _isInCallScreen = false);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('An unexpected error occurred')),
        );
      }
    }
  }

  void _showIncomingCallScreen(CallModel call) {
    // Prevent duplicate navigation
    if (_isInCallScreen) {
      print(
        '[HomeScreen] Already in call screen, skipping incoming call navigation',
      );
      return;
    }

    // Mark that we're entering call screen
    setState(() => _isInCallScreen = true);

    Navigator.of(context)
        .push(
          MaterialPageRoute(
            fullscreenDialog: true,
            builder: (_) => IncomingCallScreen(
              incomingCall: call,
              onAccept: () async {
                try {
                  Navigator.of(context).pop();

                  // Accept the call in Firebase
                  await CallService.acceptCall(
                    callId: call.callId,
                    receiverId: call.receiverId,
                  );

                  // Get current user to determine local/remote UIDs
                  final currentUser = await AuthService.getCurrentUser();
                  if (currentUser == null || !mounted) return;

                  // Convert user IDs to integers for Agora (using hashCode)
                  final localUid = CallService.agoraUidFromUserId(
                    currentUser.uid,
                  );
                  final remoteUid = CallService.agoraUidFromUserId(
                    call.initiatorId,
                  );

                  // Get Agora token from Cloud Function
                  final token = await CallService.getAgoraToken(
                    channelName: call.callId,
                    uid: localUid,
                  );

                  // Initialize and setup Agora service
                  final agoraService = AgoraService();
                  await agoraService.initialize();
                  await agoraService.joinChannel(
                    channelName: call.callId,
                    uid: localUid,
                    token: token,
                    isVideoCall: call.callType == CallType.video,
                  );

                  if (!mounted) return;

                  // Navigate to in-call screen
                  await Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => EnhancedInCallScreen(
                        callModel: call,
                        agoraService: agoraService,
                        remoteUid: remoteUid,
                        onEndCall: () async {
                          try {
                            await CallService.endCall(
                              callId: call.callId,
                              endReason: CallEndReason.userEnded,
                            );
                            await agoraService.dispose();
                          } catch (e) {
                            print('[HomeScreen] Error in onEndCall: $e');
                          }

                          // Safely pop after current frame
                          if (context.mounted) {
                            WidgetsBinding.instance.addPostFrameCallback((_) {
                              if (context.mounted &&
                                  Navigator.of(context).canPop()) {
                                Navigator.of(context).pop();
                              }
                            });
                          }
                        },
                      ),
                    ),
                  );

                  // Call screen was closed, clear the flag
                  if (mounted) {
                    setState(() => _isInCallScreen = false);
                  }
                } catch (e) {
                  print('[HomeScreen] Error accepting call: $e');

                  // Clear the flag on error
                  if (mounted) {
                    setState(() => _isInCallScreen = false);
                  }

                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Failed to join call: $e')),
                    );
                  }
                }
              },
              onReject: () async {
                Navigator.of(context).pop();

                // Clear the flag on reject
                if (mounted) {
                  setState(() => _isInCallScreen = false);
                }

                await CallService.rejectCall(
                  callId: call.callId,
                  initiatorId: call.initiatorId,
                );
              },
            ),
          ),
        )
        .then((_) {
          // Clear flag when incoming call screen is dismissed
          if (mounted) {
            setState(() => _isInCallScreen = false);
          }
        });
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
            icon: const Icon(Icons.phone),
            label: 'Calls',
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
