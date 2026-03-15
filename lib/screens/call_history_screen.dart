import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:whatsapp_clone/auth/auth_service.dart';
import 'package:whatsapp_clone/chat/call_service.dart';
import 'package:whatsapp_clone/chat/call_service_utils.dart';
import 'package:whatsapp_clone/models/call_model.dart';
import 'package:whatsapp_clone/models/user_model.dart';
import 'package:whatsapp_clone/core/design_tokens.dart';
import 'package:whatsapp_clone/core/firebase_service.dart';
import 'package:whatsapp_clone/core/agora_service.dart';
import 'package:whatsapp_clone/screens/call/enhanced_in_call_screen.dart';
import 'package:whatsapp_clone/utils/date_time_utils.dart';
import 'package:timeago/timeago.dart' as timeago;

class CallHistoryScreen extends StatefulWidget {
  const CallHistoryScreen({super.key});

  @override
  State<CallHistoryScreen> createState() => _CallHistoryScreenState();
}

class _CallHistoryScreenState extends State<CallHistoryScreen> {
  List<CallModel> _callHistory = [];
  bool _isLoading = true;
  String? _currentUserId;
  final GlobalKey<AnimatedListState> _listKey = GlobalKey<AnimatedListState>();

  @override
  void initState() {
    super.initState();
    _loadCallHistory();
  }

  Future<void> _loadCallHistory() async {
    try {
      final user = await AuthService.getCurrentUser();
      if (user == null || !mounted) return;

      setState(() {
        _currentUserId = user.uid;
        _isLoading = true;
      });

      final history = await CallService.getCallHistory(
        userId: user.uid,
        limit: 50,
      );

      if (mounted) {
        setState(() {
          _callHistory = history;
          _isLoading = false;
        });
      }
    } catch (e) {
      print('[CallHistory] Error loading: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  String _getCallDirection(CallModel call) {
    if (_currentUserId == null) return 'unknown';
    return call.getDirection(_currentUserId!);
  }

  IconData _getCallIcon(CallModel call) {
    final direction = _getCallDirection(call);
    final isVideo = call.isVideoCall;

    if (isVideo) {
      if (call.status == CallStatus.missed && direction == 'incoming') {
        return Icons.videocam_off;
      }
      return Icons.videocam;
    } else {
      if (call.status == CallStatus.missed && direction == 'incoming') {
        return Icons.call_missed;
      } else if (direction == 'incoming') {
        return Icons.call_received;
      } else {
        return Icons.call_made;
      }
    }
  }

  Color _getCallIconColor(CallModel call) {
    final direction = _getCallDirection(call);
    if (call.status == CallStatus.missed && direction == 'incoming') {
      return Colors.red;
    }
    return Colors.green;
  }

  String _getCallSummary(CallModel call) {
    final direction = _getCallDirection(call);
    final parts = <String>[];

    // Add direction prefix
    if (call.status == CallStatus.missed && direction == 'incoming') {
      parts.add('Missed');
    } else if (direction == 'incoming') {
      parts.add('Incoming');
    } else {
      parts.add('Outgoing');
    }

    // Add call type
    parts.add(call.isVideoCall ? 'video call' : 'voice call');

    // Add duration if answered
    if (call.wasAnswered == true && call.durationSeconds > 0) {
      final duration = DateTimeUtils.formatDurationHuman(call.durationSeconds);
      parts.add('($duration)');
    }

    return parts.join(' ');
  }

  Future<void> _deleteCall(CallModel call) async {
    HapticFeedback.mediumImpact();
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Call'),
        content: const Text(
          'Are you sure you want to delete this call from history?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await _removeCallFromHistory(call);
    }
  }

  Future<void> _removeCallFromHistory(CallModel call) async {
    final removedIndex = _callHistory.indexOf(call);
    if (removedIndex == -1) {
      return;
    }

    setState(() {
      _callHistory.removeAt(removedIndex);
    });

    try {
      await CallService.deleteCallHistoryEntry(callId: call.callId);
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Call deleted from history')),
      );
    } catch (e) {
      if (!mounted) {
        return;
      }

      final restoreIndex = removedIndex <= _callHistory.length
          ? removedIndex
          : _callHistory.length;

      setState(() {
        _callHistory.insert(restoreIndex, call);
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to delete call from history')),
      );
    }
  }

  Widget _buildCallTile(CallModel call) {
    final direction = _getCallDirection(call);
    final isMissed =
        call.status == CallStatus.missed && direction == 'incoming';

    // Determine the contact (other party in the call)
    final isOutgoing = direction == 'outgoing';
    final contactName = isOutgoing ? call.receiverName : call.initiatorName;
    final contactProfilePic = isOutgoing
        ? call.receiverProfilePic
        : call.initiatorProfilePic;

    return Dismissible(
      key: Key(call.callId),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        color: Colors.red,
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      confirmDismiss: (direction) async {
        HapticFeedback.mediumImpact();
        return await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Delete Call'),
            content: const Text('Remove this call from history?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () {
                  HapticFeedback.lightImpact();
                  Navigator.pop(ctx, true);
                },
                child: const Text(
                  'Delete',
                  style: TextStyle(color: Colors.red),
                ),
              ),
            ],
          ),
        );
      },
      onDismissed: (direction) {
        unawaited(_removeCallFromHistory(call));
      },
      child: ListTile(
        leading: CircleAvatar(
          radius: 24,
          backgroundImage: contactProfilePic.isNotEmpty
              ? CachedNetworkImageProvider(contactProfilePic)
              : null,
          child: contactProfilePic.isEmpty
              ? Text(contactName.substring(0, 1).toUpperCase())
              : null,
        ),
        title: Text(
          contactName,
          style: TextStyle(
            fontWeight: isMissed ? FontWeight.bold : FontWeight.normal,
            color: isMissed ? Colors.red : null,
          ),
        ),
        subtitle: Row(
          children: [
            Icon(_getCallIcon(call), size: 16, color: _getCallIconColor(call)),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                _getCallSummary(call),
                style: TextStyle(
                  fontSize: 13,
                  color: isMissed ? Colors.red.shade300 : Colors.grey,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        trailing: SizedBox(
          width: 80,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    timeago.format(call.initiatedAt, locale: 'en_short'),
                    style: TextStyle(
                      fontSize: 12,
                      color: isMissed ? Colors.red : Colors.grey,
                    ),
                  ),
                  const SizedBox(height: 2),
                ],
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: Icon(
                  call.isVideoCall ? Icons.videocam : Icons.call,
                  size: 20,
                ),
                color: Colors.green,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                onPressed: () {
                  HapticFeedback.lightImpact();
                  _initiateCallFromHistory(call, call.callType);
                },
                tooltip: 'Call $contactName',
              ),
            ],
          ),
        ),
        onTap: () {
          HapticFeedback.selectionClick();
          _showCallDetails(call);
        },
        onLongPress: () {
          HapticFeedback.heavyImpact();
          _showCallContextMenu(call);
        },
      ),
    );
  }

  void _showCallContextMenu(CallModel call) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.call, color: Colors.green),
              title: const Text('Voice Call'),
              onTap: () {
                HapticFeedback.lightImpact();
                Navigator.pop(context);
                _initiateCallFromHistory(call, CallType.voice);
              },
            ),
            ListTile(
              leading: const Icon(Icons.videocam, color: Colors.blue),
              title: const Text('Video Call'),
              onTap: () {
                HapticFeedback.lightImpact();
                Navigator.pop(context);
                _initiateCallFromHistory(call, CallType.video);
              },
            ),
            ListTile(
              leading: const Icon(Icons.info_outline, color: Colors.grey),
              title: const Text('Call Details'),
              onTap: () {
                HapticFeedback.lightImpact();
                Navigator.pop(context);
                _showCallDetails(call);
              },
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.delete, color: Colors.red),
              title: const Text(
                'Delete Call',
                style: TextStyle(color: Colors.red),
              ),
              onTap: () {
                Navigator.pop(context);
                _deleteCall(call);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  void _showCallDetails(CallModel call) {
    showModalBottomSheet(
      context: context,
      builder: (context) => Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Call Details', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: AppSpacing.md),
            _buildDetailRow(
              'Type',
              call.isVideoCall ? 'Video Call' : 'Voice Call',
            ),
            _buildDetailRow('Status', call.status.toUpperCase()),
            _buildDetailRow('Initiated', call.initiatedAt.toString()),
            if (call.answeredAt != null)
              _buildDetailRow('Answered', call.answeredAt.toString()),
            if (call.endedAt != null)
              _buildDetailRow('Ended', call.endedAt.toString()),
            if (call.durationSeconds > 0)
              _buildDetailRow(
                'Duration',
                DateTimeUtils.formatDurationHuman(call.durationSeconds),
              ),
            if (call.endReason != null)
              _buildDetailRow(
                'End Reason',
                call.endReason!.replaceAll('_', ' ').toUpperCase(),
              ),
            if (call.avgNetworkQuality != null)
              _buildDetailRow(
                'Avg Network Quality',
                _getNetworkQualityText(call.avgNetworkQuality!),
              ),
            if (call.avgBitrate != null)
              _buildDetailRow(
                'Avg Bitrate',
                '${call.avgBitrate!.toStringAsFixed(1)} kbps',
              ),
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                if (call.isVideoCall)
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () {
                        Navigator.pop(context);
                        _initiateCallFromHistory(call, CallType.video);
                      },
                      icon: const Icon(Icons.videocam),
                      label: const Text('Video Call'),
                    ),
                  ),
                if (call.isVideoCall) const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Navigator.pop(context);
                      _initiateCallFromHistory(call, CallType.voice);
                    },
                    icon: const Icon(Icons.call),
                    label: const Text('Voice Call'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              '$label:',
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.grey,
              ),
            ),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }

  String _getNetworkQualityText(int quality) {
    switch (quality) {
      case 1:
        return 'Excellent';
      case 2:
        return 'Good';
      case 3:
        return 'Poor';
      case 4:
        return 'Bad';
      case 5:
        return 'Very Bad';
      case 6:
        return 'Disconnected';
      default:
        return 'Unknown';
    }
  }

  void _showDialPad() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => const DialPadWidget(),
    );
  }

  Future<void> _initiateCallFromHistory(
    CallModel previousCall,
    String callType,
  ) async {
    if (_currentUserId == null) return;

    // Determine who to call (the other person in the call)
    final receiverId = previousCall.getOtherUserId(_currentUserId!);
    final receiverName = previousCall.getOtherUserName(_currentUserId!);
    final receiverProfilePic = previousCall.getOtherUserProfilePic(
      _currentUserId!,
    );

    final currentUser = await AuthService.getCurrentUser();
    if (currentUser == null || !mounted) return;

    // Show loading
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(
        child: Card(
          child: Padding(
            padding: EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('Starting call...'),
              ],
            ),
          ),
        ),
      ),
    );

    try {
      print('[CallHistory] Initiating ${callType} call from history...');

      // Initiate call
      final call = await CallService.initiateCall(
        initiatorId: currentUser.uid,
        initiatorName: currentUser.displayName,
        initiatorProfilePic: currentUser.profilePic,
        receiverId: receiverId,
        receiverName: receiverName,
        receiverProfilePic: receiverProfilePic,
        callType: callType,
      );
      print('[CallHistory] Call created: ${call.callId}');

      if (!mounted) return;

      // Get Agora token
      final localUid = CallService.agoraUidFromUserId(currentUser.uid);
      final remoteUid = CallService.agoraUidFromUserId(receiverId);
      print('[CallHistory] Local UID: $localUid, Remote UID: $remoteUid');

      final token = await CallService.getAgoraToken(
        channelName: call.callId,
        uid: localUid,
      );
      print('[CallHistory] Got Agora token');

      // Initialize Agora service
      final agoraService = AgoraService();
      await agoraService.initialize();
      print('[CallHistory] Agora initialized');

      await agoraService.joinChannel(
        channelName: call.callId,
        uid: localUid,
        token: token,
        isVideoCall: callType == CallType.video,
      );
      print('[CallHistory] Joined Agora channel');

      if (!mounted) return;

      // Close loading dialog
      Navigator.of(context).pop();

      // Navigate to in-call screen
      print('[CallHistory] Navigating to call screen...');
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
                print('[CallHistory] Error ending call: $e');
              }

              if (context.mounted && Navigator.of(context).canPop()) {
                Navigator.of(context).pop();
              }
            },
          ),
        ),
      );
      print('[CallHistory] Returned from call screen');
    } catch (e) {
      print('[CallHistory] Error initiating call from history: $e');
      print('[CallHistory] Error type: ${e.runtimeType}');

      if (mounted && Navigator.of(context).canPop()) {
        Navigator.of(context).pop(); // Close loading dialog
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to start call: ${e.toString()}'),
            duration: const Duration(seconds: 4),
          ),
        );
      }
    }
  }

  Widget _buildSkeletonLoader() {
    return ListView.builder(
      itemCount: 10,
      itemBuilder: (context, index) {
        return Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm,
          ),
          child: Row(
            children: [
              // Avatar skeleton
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              // Text skeleton
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: double.infinity,
                      height: 14,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      width: 120,
                      height: 12,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade200,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              // Icon skeleton
              Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Calls'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadCallHistory,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: _isLoading
          ? _buildSkeletonLoader()
          : _callHistory.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.call, size: 64, color: Colors.grey.shade400),
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    'No calls yet',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: Colors.grey.shade600,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    'Your call history will appear here',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Colors.grey.shade500,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  ElevatedButton.icon(
                    onPressed: _showDialPad,
                    icon: const Icon(Icons.dialpad),
                    label: const Text('Make a Call'),
                  ),
                ],
              ),
            )
          : RefreshIndicator(
              onRefresh: _loadCallHistory,
              child: AnimatedList(
                key: _listKey,
                initialItemCount: _callHistory.length,
                itemBuilder: (context, index, animation) {
                  if (index >= _callHistory.length) {
                    return const SizedBox.shrink();
                  }
                  final call = _callHistory[index];
                  return SizeTransition(
                    sizeFactor: animation,
                    child: FadeTransition(
                      opacity: animation,
                      child: _buildCallTile(call),
                    ),
                  );
                },
              ),
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          HapticFeedback.mediumImpact();
          _showDialPad();
        },
        tooltip: 'Dial',
        child: const Icon(Icons.dialpad),
      ),
    );
  }
}

/// Dial pad widget for making direct calls
class DialPadWidget extends StatefulWidget {
  const DialPadWidget({super.key});

  @override
  State<DialPadWidget> createState() => _DialPadWidgetState();
}

class _DialPadWidgetState extends State<DialPadWidget> {
  final _searchController = TextEditingController();
  UserModel? _foundUser;
  UserModel? _currentUser;
  bool _searching = false;
  bool _searched = false;

  @override
  void initState() {
    super.initState();
    _loadCurrentUser();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadCurrentUser() async {
    _currentUser = await AuthService.getCurrentUser();
  }

  Future<void> _searchUser() async {
    HapticFeedback.lightImpact();
    final query = _searchController.text.trim();
    if (query.isEmpty) return;

    setState(() {
      _searching = true;
      _searched = true;
      _foundUser = null;
    });

    try {
      final found = await FirebaseService.searchUserByEmailOrNumber(query);

      if (!mounted) return;

      setState(() {
        _foundUser = found;
        _searching = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _searching = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Search failed: $e')));
    }
  }

  Future<void> _initiateCall(String callType) async {
    if (_foundUser == null || _currentUser == null) return;

    if (_foundUser!.uid == _currentUser!.uid) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('You cannot call yourself')));
      return;
    }

    // Show loading
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(
        child: Card(
          child: Padding(
            padding: EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('Starting call...'),
              ],
            ),
          ),
        ),
      ),
    );

    try {
      print('[CallHistory] Initiating ${callType} call...');

      // Initiate call
      final call = await CallService.initiateCall(
        initiatorId: _currentUser!.uid,
        initiatorName: _currentUser!.displayName,
        initiatorProfilePic: _currentUser!.profilePic,
        receiverId: _foundUser!.uid,
        receiverName: _foundUser!.displayName,
        receiverProfilePic: _foundUser!.profilePic,
        callType: callType,
      );
      print('[CallHistory] Call created: ${call.callId}');

      if (!mounted) return;

      // Get Agora token
      final localUid = CallService.agoraUidFromUserId(_currentUser!.uid);
      final remoteUid = CallService.agoraUidFromUserId(_foundUser!.uid);
      print('[CallHistory] Local UID: $localUid, Remote UID: $remoteUid');

      final token = await CallService.getAgoraToken(
        channelName: call.callId,
        uid: localUid,
      );
      print('[CallHistory] Got Agora token');

      // Initialize Agora service
      final agoraService = AgoraService();
      await agoraService.initialize();
      print('[CallHistory] Agora initialized');

      await agoraService.joinChannel(
        channelName: call.callId,
        uid: localUid,
        token: token,
        isVideoCall: callType == CallType.video,
      );
      print('[CallHistory] Joined Agora channel');

      if (!mounted) return;

      // Close loading dialog
      Navigator.of(context).pop();

      // Close dial pad
      Navigator.of(context).pop();

      // Navigate to in-call screen
      print('[CallHistory] Navigating to call screen...');
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
                print('[DialPad] Error ending call: $e');
              }

              if (context.mounted && Navigator.of(context).canPop()) {
                Navigator.of(context).pop();
              }
            },
          ),
        ),
      );
      print('[CallHistory] Returned from call screen');
    } catch (e) {
      print('[CallHistory] Error initiating call: $e');
      print('[CallHistory] Error type: ${e.runtimeType}');

      if (mounted && Navigator.of(context).canPop()) {
        Navigator.of(context).pop(); // Close loading dialog
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to start call: ${e.toString()}'),
            duration: const Duration(seconds: 4),
          ),
        );
      }
    }
  }

  void _addDigit(String digit) {
    HapticFeedback.selectionClick();
    setState(() {
      _searchController.text += digit;
    });
  }

  void _deleteDigit() {
    final text = _searchController.text;
    if (text.isNotEmpty) {
      HapticFeedback.lightImpact();
      setState(() {
        _searchController.text = text.substring(0, text.length - 1);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
        top: AppSpacing.md,
        left: AppSpacing.md,
        right: AppSpacing.md,
      ),
      decoration: BoxDecoration(
        color: theme.scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle bar
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.only(bottom: AppSpacing.md),
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // Title
          Text(
            'Dial',
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: AppSpacing.md),

          // Search input
          TextField(
            controller: _searchController,
            readOnly: true,
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineMedium,
            decoration: InputDecoration(
              hintText: 'Enter number (0380...) or email',
              hintStyle: theme.textTheme.bodyLarge?.copyWith(
                color: Colors.grey,
              ),
              border: InputBorder.none,
              suffixIcon: _searchController.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.backspace_outlined),
                      onPressed: _deleteDigit,
                    )
                  : null,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),

          // Search button
          if (_searchController.text.isNotEmpty)
            ElevatedButton.icon(
              onPressed: _searching ? null : _searchUser,
              icon: _searching
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.search),
              label: Text(_searching ? 'Searching...' : 'Search User'),
            ),

          const SizedBox(height: AppSpacing.md),

          // Found user display
          if (_foundUser != null)
            Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: isDark ? Colors.grey.shade800 : Colors.grey.shade100,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  CircleAvatar(
                    radius: 32,
                    backgroundImage: _foundUser!.profilePic.isNotEmpty
                        ? CachedNetworkImageProvider(_foundUser!.profilePic)
                        : null,
                    child: _foundUser!.profilePic.isEmpty
                        ? Text(
                            _foundUser!.displayName
                                .substring(0, 1)
                                .toUpperCase(),
                            style: const TextStyle(fontSize: 24),
                          )
                        : null,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    _foundUser!.displayName,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    _foundUser!.email,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: Colors.grey,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () {
                            HapticFeedback.mediumImpact();
                            _initiateCall('voice');
                          },
                          icon: const Icon(Icons.call),
                          label: const Text('Voice Call'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green,
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () {
                            HapticFeedback.mediumImpact();
                            _initiateCall('video');
                          },
                          icon: const Icon(Icons.videocam),
                          label: const Text('Video Call'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blue,
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            )
          else if (_searched && !_searching)
            Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Column(
                children: [
                  Icon(Icons.person_off, size: 48, color: Colors.grey.shade400),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    'User not found',
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: Colors.grey,
                    ),
                  ),
                ],
              ),
            ),

          const SizedBox(height: AppSpacing.md),

          // Dial pad grid
          GridView.count(
            shrinkWrap: true,
            crossAxisCount: 3,
            childAspectRatio: 1.5,
            mainAxisSpacing: AppSpacing.sm,
            crossAxisSpacing: AppSpacing.sm,
            physics: const NeverScrollableScrollPhysics(),
            children: [
              _buildDialButton('1', ''),
              _buildDialButton('2', 'ABC'),
              _buildDialButton('3', 'DEF'),
              _buildDialButton('4', 'GHI'),
              _buildDialButton('5', 'JKL'),
              _buildDialButton('6', 'MNO'),
              _buildDialButton('7', 'PQRS'),
              _buildDialButton('8', 'TUV'),
              _buildDialButton('9', 'WXYZ'),
              _buildDialButton('*', ''),
              _buildDialButton('0', '+'),
              _buildDialButton('#', ''),
            ],
          ),

          const SizedBox(height: AppSpacing.sm),

          // Special buttons
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              TextButton.icon(
                onPressed: () {
                  _addDigit('@');
                },
                icon: const Icon(Icons.alternate_email),
                label: const Text('@'),
              ),
              TextButton.icon(
                onPressed: () {
                  _addDigit('.');
                },
                icon: const Icon(Icons.circle, size: 8),
                label: const Text('.'),
              ),
              TextButton.icon(
                onPressed: () {
                  setState(() {
                    _searchController.clear();
                    _foundUser = null;
                    _searched = false;
                  });
                },
                icon: const Icon(Icons.clear),
                label: const Text('Clear'),
              ),
            ],
          ),

          const SizedBox(height: AppSpacing.md),
        ],
      ),
    );
  }

  Widget _buildDialButton(String digit, String letters) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return InkWell(
      onTap: () => _addDigit(digit),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        decoration: BoxDecoration(
          color: isDark ? Colors.grey.shade800 : Colors.grey.shade200,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              digit,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            if (letters.isNotEmpty)
              Text(
                letters,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: Colors.grey,
                  fontSize: 10,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
