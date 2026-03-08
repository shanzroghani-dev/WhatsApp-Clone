import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:whatsapp_clone/models/call_model.dart';
import 'package:whatsapp_clone/core/design_tokens.dart';
import 'package:whatsapp_clone/core/notification_service.dart';

class IncomingCallScreen extends StatefulWidget {
  final CallModel incomingCall;
  final VoidCallback onAccept;
  final VoidCallback onReject;

  const IncomingCallScreen({
    super.key,
    required this.incomingCall,
    required this.onAccept,
    required this.onReject,
  });

  @override
  State<IncomingCallScreen> createState() => _IncomingCallScreenState();
}

class _IncomingCallScreenState extends State<IncomingCallScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _scaleAnimation;
  late Timer _countdownTimer;
  int _secondsRemaining = 60; // Default timeout is 60 seconds

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat(reverse: true);

    _scaleAnimation = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );

    // Start countdown timer
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() {
        _secondsRemaining--;
      });

      // Auto-reject if time runs out
      if (_secondsRemaining <= 0) {
        _countdownTimer.cancel();
        widget.onReject();
      }
    });
  }

  @override
  void dispose() {
    _animationController.dispose();
    _countdownTimer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? Colors.black : Colors.white,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            // Call type badge
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.sm,
              ),
              decoration: BoxDecoration(
                color: AppColors.primary.withAlpha(150),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                widget.incomingCall.callType == 'video'
                    ? 'Video Call'
                    : 'Voice Call',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),

            // Profile image with animation
            ScaleTransition(
              scale: _scaleAnimation,
              child: Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.primary, width: 3),
                ),
                child: ClipOval(
                  child: CachedNetworkImage(
                    imageUrl: widget.incomingCall.initiatorProfilePic,
                    width: 120,
                    height: 120,
                    fit: BoxFit.cover,
                    placeholder: (context, url) => Container(
                      width: 120,
                      height: 120,
                      color: Colors.grey.shade300,
                      child: const Icon(Icons.person),
                    ),
                    errorWidget: (context, url, error) => Container(
                      width: 120,
                      height: 120,
                      color: Colors.grey.shade300,
                      child: const Icon(Icons.person),
                    ),
                  ),
                ),
              ),
            ),

            // Caller name
            Column(
              children: [
                Text(
                  widget.incomingCall.initiatorName,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  'Incoming ${widget.incomingCall.callType} call...',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: Colors.grey,
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                // Countdown timer
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                    vertical: AppSpacing.sm,
                  ),
                  decoration: BoxDecoration(
                    color: _secondsRemaining <= 10
                        ? Colors.red.withAlpha(100)
                        : Colors.orange.withAlpha(100),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    'Timeout in $_secondsRemaining seconds',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color:
                          _secondsRemaining <= 10 ? Colors.red : Colors.orange,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),

            // Action buttons
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                // Reject button
                FloatingActionButton(
                  heroTag: 'reject_call_btn',
                  onPressed: () async {
                    await NotificationService.cancelCallNotification(
                      widget.incomingCall.callId,
                    );
                    widget.onReject();
                  },
                  backgroundColor: Colors.red,
                  child: const Icon(Icons.call_end),
                ),

                // Accept button
                FloatingActionButton(
                  heroTag: 'accept_call_btn',
                  onPressed: () async {
                    await NotificationService.cancelCallNotification(
                      widget.incomingCall.callId,
                    );
                    widget.onAccept();
                  },
                  backgroundColor: Colors.green,
                  child: Icon(
                    widget.incomingCall.callType == 'video'
                        ? Icons.videocam
                        : Icons.call,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
