import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:whatsapp_clone/models/call_model.dart';

class CallHistoryScreen extends StatefulWidget {
  final String currentUserId;
  final List<CallModel> callHistory;
  final bool isLoading;
  final VoidCallback onRefresh;
  final Function(String) onCallTap; // Call user by UID

  const CallHistoryScreen({
    super.key,
    required this.currentUserId,
    required this.callHistory,
    required this.isLoading,
    required this.onRefresh,
    required this.onCallTap,
  });

  @override
  State<CallHistoryScreen> createState() => _CallHistoryScreenState();
}

class _CallHistoryScreenState extends State<CallHistoryScreen> {
  @override
  void initState() {
    super.initState();
    widget.onRefresh();
  }

  String _formatCallDuration(int seconds) {
    if (seconds < 60) {
      return '${seconds}s';
    } else if (seconds < 3600) {
      final minutes = seconds ~/ 60;
      return '${minutes}m';
    } else {
      final hours = seconds ~/ 3600;
      final mins = (seconds % 3600) ~/ 60;
      return '${hours}h ${mins}m';
    }
  }

  String _formatTime(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.inSeconds < 60) {
      return 'just now';
    } else if (difference.inMinutes < 60) {
      return '${difference.inMinutes}m ago';
    } else if (difference.inHours < 24) {
      return '${difference.inHours}h ago';
    } else if (difference.inDays < 7) {
      return '${difference.inDays}d ago';
    } else {
      return '${dateTime.month}/${dateTime.day}/${dateTime.year}';
    }
  }

  String _getCallStatusText(CallModel call) {
    if (call.endReason == 'no_answer') {
      return 'Missed';
    } else if (call.endReason == 'rejected') {
      return 'Rejected';
    } else if (call.initiatorId == widget.currentUserId) {
      return 'Outgoing';
    } else {
      return 'Incoming';
    }
  }

  Color _getCallStatusColor(CallModel call) {
    if (call.endReason == 'no_answer' || call.endReason == 'rejected') {
      return Colors.red;
    } else if (call.initiatorId == widget.currentUserId) {
      return Colors.grey;
    } else {
      return Colors.green;
    }
  }

  IconData _getCallIcon(CallModel call) {
    if (call.endReason == 'no_answer') {
      return Icons.call_missed;
    } else if (call.callType == 'video') {
      return call.initiatorId == widget.currentUserId
          ? Icons.video_call
          : Icons.video_call;
    } else {
      return call.initiatorId == widget.currentUserId
          ? Icons.call_made
          : Icons.call_received;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Call History'), centerTitle: true),
      body: widget.isLoading
          ? const Center(child: CircularProgressIndicator())
          : widget.callHistory.isEmpty
          ? const Center(child: Text('No calls yet'))
          : ListView.builder(
              itemCount: widget.callHistory.length,
              itemBuilder: (context, index) {
                final call = widget.callHistory[index];
                final otherUserId = call.initiatorId == widget.currentUserId
                    ? call.receiverId
                    : call.initiatorId;
                final otherUserName = call.initiatorId == widget.currentUserId
                    ? call.receiverName
                    : call.initiatorName;
                final otherUserPic = call.initiatorId == widget.currentUserId
                    ? call.receiverProfilePic
                    : call.initiatorProfilePic;

                return ListTile(
                  leading: CircleAvatar(
                    backgroundImage: CachedNetworkImageProvider(otherUserPic),
                    child: otherUserPic.isEmpty
                        ? const Icon(Icons.person)
                        : null,
                  ),
                  title: Text(otherUserName),
                  subtitle: Row(
                    children: [
                      Icon(
                        _getCallIcon(call),
                        size: 16,
                        color: _getCallStatusColor(call),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _getCallStatusText(call),
                        style: TextStyle(
                          color: _getCallStatusColor(call),
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Text(
                        _formatTime(call.initiatedAt),
                        style: const TextStyle(fontSize: 12),
                      ),
                    ],
                  ),
                  trailing: call.status == 'ended'
                      ? Text(
                          _formatCallDuration(call.durationSeconds),
                          style: theme.textTheme.labelSmall,
                        )
                      : null,
                  onTap: () {
                    widget.onCallTap(otherUserId);
                  },
                );
              },
            ),
    );
  }
}
