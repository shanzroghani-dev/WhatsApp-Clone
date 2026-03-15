import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:whatsapp_clone/models/call_model.dart';
import 'package:whatsapp_clone/core/design_tokens.dart';
import 'package:whatsapp_clone/core/agora_service.dart';
import 'package:whatsapp_clone/chat/call_service.dart';
import 'package:whatsapp_clone/chat/call_service_utils.dart';
import 'package:whatsapp_clone/utils/date_time_utils.dart';

/// Enhanced in-call screen with advanced features beyond WhatsApp
class EnhancedInCallScreen extends StatefulWidget {
  final CallModel callModel;
  final AgoraService agoraService;
  final VoidCallback onEndCall;
  final int remoteUid;

  const EnhancedInCallScreen({
    super.key,
    required this.callModel,
    required this.agoraService,
    required this.onEndCall,
    required this.remoteUid,
  });

  @override
  State<EnhancedInCallScreen> createState() => _EnhancedInCallScreenState();
}

class _EnhancedInCallScreenState extends State<EnhancedInCallScreen> {
  bool _showControls = true;
  bool _showAdvancedMenu = false;
  bool _isTogglingAudio = false;
  bool _isTogglingVideo = false;
  bool _isTogglingSpeaker = false;
  VoiceEffectPreset _selectedVoiceEffect = VoiceEffectPreset.none;
  VideoQualityPreset _selectedVideoQuality = VideoQualityPreset.high;
  double _smoothness = 0.5;
  double _lightening = 0.7;
  double _redness = 0.1;
  double _sharpness = 0.3;
  Duration _callDuration = Duration.zero;
  late Stopwatch _stopwatch;
  StreamSubscription<CallModel?>? _callStatusSubscription;
  bool _isEndingCall = false;
  bool _timerStarted = false;
  bool _isChannelJoined = false;
  bool _isLocalPrimary = false;
  Offset? _floatingVideoOffset;
  Timer? _controlsAutoHideTimer;

  static const double _floatingVideoWidth = 170;
  static const double _floatingVideoHeight = 230;
  static const double _floatingVideoMargin = 16;

  @override
  void initState() {
    super.initState();
    _stopwatch = Stopwatch();
    _smoothness = widget.agoraService.beautySmoothness;
    _lightening = widget.agoraService.beautyLightening;
    _redness = widget.agoraService.beautyRedness;
    _sharpness = widget.agoraService.beautySharpness;

    // Listen to shared Agora service state updates.
    widget.agoraService.addListener(_onAgoraStateChanged);

    // Delay video view initialization slightly to ensure channel is ready
    Future.delayed(const Duration(milliseconds: 300), () {
      if (mounted) {
        setState(() {
          _isChannelJoined = true;
        });
      }
    });

    // Start timer if call already answered, otherwise wait for answer
    if (widget.callModel.answeredAt != null) {
      _startTimer();
    }

    Future.delayed(const Duration(seconds: 1), _updateDuration);
    _showControlsTemporarily();

    // Listen to call status changes
    _callStatusSubscription = CallService.listenToCall(widget.callModel.callId)
        .listen((call) {
          if (call == null ||
              call.status == CallStatus.ended ||
              call.status == CallStatus.rejected) {
            // Call ended by other party, close screen without calling endCall again
            if (mounted && !_isEndingCall) {
              _isEndingCall = true;
              _handleRemoteCallEnd();
            }
          } else if (!_timerStarted && call.answeredAt != null) {
            // Call was answered, start the timer
            _startTimer();
          }
        });
  }

  void _onAgoraStateChanged() {
    if (!mounted) return;
    setState(() {});
  }

  void _showControlsTemporarily() {
    if (!mounted) return;
    if (!_showControls) {
      setState(() {
        _showControls = true;
      });
    }
    _controlsAutoHideTimer?.cancel();
    if (_showAdvancedMenu) return;

    _controlsAutoHideTimer = Timer(const Duration(seconds: 4), () {
      if (!mounted || _showAdvancedMenu) return;
      setState(() {
        _showControls = false;
      });
    });
  }

  void _toggleControlsVisibility() {
    _controlsAutoHideTimer?.cancel();
    setState(() {
      _showControls = !_showControls;
    });
    if (_showControls) {
      _showControlsTemporarily();
    }
  }

  void _startTimer() {
    if (_timerStarted) return;
    _timerStarted = true;
    _stopwatch.start();
    setState(() {});
  }

  void _handleRemoteCallEnd() async {
    try {
      // Just dispose Agora, don't end call (already ended by other party)
      await widget.agoraService.dispose();
    } catch (e) {
      print('[EnhancedInCallScreen] Error disposing: $e');
    }

    // Safely pop after current frame
    if (mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
        }
      });
    }
  }

  void _updateDuration() {
    if (mounted) {
      setState(() {
        _callDuration = Duration(seconds: _stopwatch.elapsed.inSeconds);
      });
      Future.delayed(const Duration(seconds: 1), _updateDuration);
    }
  }

  @override
  void dispose() {
    _stopwatch.stop();
    _callStatusSubscription?.cancel();
    _controlsAutoHideTimer?.cancel();
    widget.agoraService.removeListener(_onAgoraStateChanged);
    super.dispose();
  }

  Offset _clampFloatingOffset(Offset candidate, Size screenSize) {
    final minX = _floatingVideoMargin;
    final maxX = screenSize.width - _floatingVideoWidth - _floatingVideoMargin;
    final minY = 70.0;
    final maxY = screenSize.height - _floatingVideoHeight - 150;

    return Offset(
      candidate.dx.clamp(minX, maxX).toDouble(),
      candidate.dy.clamp(minY, maxY).toDouble(),
    );
  }

  void _swapPrimaryVideo() {
    setState(() {
      _isLocalPrimary = !_isLocalPrimary;
    });
  }

  Widget _buildRemoteVideo({required bool compact}) {
    if (!widget.agoraService.hasRemoteUser) {
      return Center(
        key: const ValueKey('remote-connecting'),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(
              color: Colors.white,
              strokeWidth: compact ? 2 : 3,
            ),
            SizedBox(height: compact ? 8 : 12),
            Text(
              'Connecting...',
              style: TextStyle(
                color: Colors.white.withOpacity(0.7),
                fontSize: compact ? 10 : 14,
              ),
            ),
          ],
        ),
      );
    }

    return AgoraVideoView(
      key: const ValueKey('remote-video'),
      controller: VideoViewController.remote(
        rtcEngine: widget.agoraService.engine,
        canvas: VideoCanvas(uid: widget.remoteUid),
        connection: RtcConnection(channelId: widget.callModel.callId),
      ),
    );
  }

  Widget _buildLocalVideo() {
    return AgoraVideoView(
      controller: VideoViewController(
        rtcEngine: widget.agoraService.engine,
        canvas: const VideoCanvas(uid: 0),
      ),
    );
  }

  Widget _buildLocalVideoPanel({required bool compact}) {
    if (widget.agoraService.isVideoEnabled) {
      return _buildLocalVideo();
    }

    return Container(
      color: Colors.black,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.videocam_off,
              color: Colors.white70,
              size: compact ? 24 : 56,
            ),
            SizedBox(height: compact ? 6 : 12),
            Text(
              'Camera off',
              style: TextStyle(
                color: Colors.white70,
                fontSize: compact ? 10 : 16,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isVideoCall = widget.callModel.callType == CallType.video;
    final screenSize = MediaQuery.of(context).size;
    final defaultFloatingOffset = Offset(
      screenSize.width - _floatingVideoWidth - _floatingVideoMargin,
      90,
    );
    final floatingOffset = _floatingVideoOffset ?? defaultFloatingOffset;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Video/Audio area
          GestureDetector(
            onTap: _toggleControlsVisibility,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 320),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              child: isVideoCall
                  ? Container(
                      key: const ValueKey('video-call-stage'),
                      color: Colors.black,
                      child: Center(
                        child: _isChannelJoined
                            ? (_isLocalPrimary
                                  ? _buildLocalVideoPanel(compact: false)
                                  : _buildRemoteVideo(compact: false))
                            : Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  _buildProfileView(),
                                  if (!_isChannelJoined)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 24),
                                      child: Column(
                                        children: [
                                          const CircularProgressIndicator(
                                            color: Colors.white,
                                          ),
                                          const SizedBox(height: 16),
                                          Text(
                                            'Connecting...',
                                            style: TextStyle(
                                              color: Colors.white.withOpacity(
                                                0.7,
                                              ),
                                              fontSize: 16,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                ],
                              ),
                      ),
                    )
                  : SizedBox(
                      key: const ValueKey('audio-call-stage'),
                      child: _buildAudioCallView(),
                    ),
            ),
          ),

          // Floating picture-in-picture video (draggable + tap to swap)
          if (isVideoCall && _isChannelJoined)
            Positioned(
              left: floatingOffset.dx,
              top: floatingOffset.dy,
              child: GestureDetector(
                onTap: _swapPrimaryVideo,
                onPanUpdate: (details) {
                  final current = _floatingVideoOffset ?? defaultFloatingOffset;
                  final next = current + details.delta;
                  setState(() {
                    _floatingVideoOffset = _clampFloatingOffset(
                      next,
                      screenSize,
                    );
                  });
                },
                child: Container(
                  width: _floatingVideoWidth,
                  height: _floatingVideoHeight,
                  decoration: BoxDecoration(
                    color: Colors.grey[900],
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white24, width: 2),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: _isLocalPrimary
                        ? _buildRemoteVideo(compact: true)
                        : _buildLocalVideoPanel(compact: true),
                  ),
                ),
              ),
            ),

          // Network quality indicator
          Positioned(
            top: 50,
            left: 16,
            child: AnimatedOpacity(
              opacity: _showControls ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 200),
              child: _buildNetworkQualityIndicator(),
            ),
          ),

          // Recording indicator
          if (widget.agoraService.isRecording)
            Positioned(
              top: 50,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.red,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        'Recording',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

          // Top info bar
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: AnimatedOpacity(
              opacity: _showControls ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 200),
              child: Container(
                padding: const EdgeInsets.only(
                  top: 50,
                  left: 16,
                  right: 16,
                  bottom: 20,
                ),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.black.withOpacity(0.7), Colors.transparent],
                  ),
                ),
                child: Column(
                  children: [
                    Text(
                      widget.callModel.receiverName,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      DateTimeUtils.formatDurationMMSS(_callDuration),
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Bottom controls
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: AnimatedOpacity(
              opacity: _showControls ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 200),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  vertical: 24,
                  horizontal: 16,
                ),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [Colors.black.withOpacity(0.8), Colors.transparent],
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Advanced menu (expandable)
                    if (_showAdvancedMenu) _buildAdvancedMenu(),

                    const SizedBox(height: 16),

                    // Main controls
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        // Mute button
                        _buildCallControl(
                          icon: widget.agoraService.isAudioMuted
                              ? Icons.mic_off
                              : Icons.mic,
                          label: 'Mute',
                          onTap: () async {
                            if (_isTogglingAudio) return;
                            _showControlsTemporarily();
                            _isTogglingAudio = true;
                            try {
                              final mute = !widget.agoraService.isAudioMuted;
                              await widget.agoraService.toggleAudio(mute);
                              if (mounted) {
                                setState(() {});
                              }
                            } catch (e) {
                              print('[InCallScreen] Error toggling audio: $e');
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      'Failed to toggle microphone',
                                    ),
                                    duration: Duration(seconds: 2),
                                  ),
                                );
                              }
                            } finally {
                              _isTogglingAudio = false;
                            }
                          },
                          isActive: widget.agoraService.isAudioMuted,
                        ),

                        // Video toggle (if video call)
                        if (isVideoCall)
                          _buildCallControl(
                            icon: widget.agoraService.isVideoEnabled
                                ? Icons.videocam
                                : Icons.videocam_off,
                            label: 'Video',
                            onTap: () async {
                              if (_isTogglingVideo) return;
                              _showControlsTemporarily();
                              _isTogglingVideo = true;
                              try {
                                final enable =
                                    !widget.agoraService.isVideoEnabled;
                                await widget.agoraService.toggleVideo(enable);
                                if (mounted) {
                                  setState(() {});
                                }
                              } catch (e) {
                                print(
                                  '[InCallScreen] Error toggling video: $e',
                                );
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('Failed to toggle video'),
                                      duration: Duration(seconds: 2),
                                    ),
                                  );
                                }
                              } finally {
                                _isTogglingVideo = false;
                              }
                            },
                            isActive: !widget.agoraService.isVideoEnabled,
                          ),

                        // End call button
                        _buildCallControl(
                          icon: Icons.call_end,
                          label: 'End',
                          onTap: () {
                            _showControlsTemporarily();
                            Navigator.of(context).pop();
                            widget.onEndCall();
                          },
                          isActive: false,
                          color: Colors.red,
                        ),

                        // Camera flip (if video call)
                        if (isVideoCall)
                          _buildCallControl(
                            icon: Icons.flip_camera_ios,
                            label: 'Flip',
                            onTap: () {
                              _showControlsTemporarily();
                              widget.agoraService.switchCamera();
                            },
                            isActive: false,
                          ),

                        // Speaker toggle
                        _buildCallControl(
                          icon: widget.agoraService.isSpeakerEnabled
                              ? Icons.volume_up
                              : Icons.volume_off,
                          label: 'Speaker',
                          onTap: () async {
                            if (_isTogglingSpeaker) return;
                            _showControlsTemporarily();
                            _isTogglingSpeaker = true;
                            try {
                              final enable =
                                  !widget.agoraService.isSpeakerEnabled;
                              await widget.agoraService.toggleSpeaker(enable);
                              if (mounted) {
                                setState(() {});
                              }
                            } finally {
                              _isTogglingSpeaker = false;
                            }
                          },
                          isActive: widget.agoraService.isSpeakerEnabled,
                        ),

                        // Advanced menu toggle
                        _buildCallControl(
                          icon: Icons.more_vert,
                          label: 'More',
                          onTap: () {
                            setState(() {
                              _showAdvancedMenu = !_showAdvancedMenu;
                            });
                            _showControlsTemporarily();
                          },
                          isActive: _showAdvancedMenu,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProfileView() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        CachedNetworkImage(
          imageUrl: widget.callModel.getOtherUserProfilePic(
            FirebaseAuth.instance.currentUser?.uid ?? '',
          ),
          width: 150,
          height: 150,
          fit: BoxFit.cover,
          imageBuilder: (context, imageProvider) =>
              CircleAvatar(backgroundImage: imageProvider, radius: 75),
          placeholder: (context, url) => const CircleAvatar(
            radius: 75,
            child: CircularProgressIndicator(),
          ),
          errorWidget: (context, url, error) => const CircleAvatar(
            radius: 75,
            child: Icon(Icons.person, size: 50),
          ),
        ),
        const SizedBox(height: 24),
        Text(
          widget.callModel.getOtherUserName(
            FirebaseAuth.instance.currentUser?.uid ?? '',
          ),
          style: const TextStyle(
            color: Colors.white,
            fontSize: 24,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  Widget _buildAudioCallView() {
    final connectedLabel = widget.agoraService.hasRemoteUser
        ? 'Connected'
        : 'Ringing';

    return Stack(
      children: [
        Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF0E1E2B), Color(0xFF1F3646), Color(0xFF0A121A)],
            ),
          ),
        ),
        Positioned(
          top: -80,
          right: -40,
          child: Container(
            width: 220,
            height: 220,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFF5BC0BE).withOpacity(0.18),
            ),
          ),
        ),
        Positioned(
          bottom: 120,
          left: -60,
          child: Container(
            width: 180,
            height: 180,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFFF4A261).withOpacity(0.16),
            ),
          ),
        ),
        SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.14),
                      borderRadius: BorderRadius.circular(30),
                      border: Border.all(color: Colors.white24),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          widget.agoraService.hasRemoteUser
                              ? Icons.call
                              : Icons.ring_volume,
                          size: 16,
                          color: Colors.white,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          connectedLabel,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 22),
                  Text(
                    DateTimeUtils.formatDurationMMSS(_callDuration),
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 16,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const SizedBox(height: 32),
                  Container(
                    width: 200,
                    height: 200,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white30, width: 2),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.35),
                          blurRadius: 30,
                          offset: const Offset(0, 14),
                        ),
                      ],
                    ),
                    child: ClipOval(
                      child: CachedNetworkImage(
                        imageUrl: widget.callModel.getOtherUserProfilePic(
                          FirebaseAuth.instance.currentUser?.uid ?? '',
                        ),
                        fit: BoxFit.cover,
                        placeholder: (context, url) => Container(
                          color: Colors.white12,
                          child: const Center(
                            child: CircularProgressIndicator(
                              color: Colors.white,
                            ),
                          ),
                        ),
                        errorWidget: (context, url, error) => Container(
                          color: Colors.white12,
                          child: const Icon(
                            Icons.person,
                            size: 72,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 28),
                  Text(
                    widget.callModel.getOtherUserName(
                      FirebaseAuth.instance.currentUser?.uid ?? '',
                    ),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 30,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    widget.agoraService.isAudioMuted
                        ? 'Your microphone is muted'
                        : 'Tap controls below to manage the call',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white70, fontSize: 14),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCallControl({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    required bool isActive,
    Color? color,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Material(
          color: color ?? (isActive ? Colors.white : Colors.white24),
          shape: const CircleBorder(),
          child: InkWell(
            onTap: onTap,
            customBorder: const CircleBorder(),
            child: Container(
              width: 60,
              height: 60,
              alignment: Alignment.center,
              child: Icon(
                icon,
                color: color != null
                    ? Colors.white
                    : (isActive ? Colors.black : Colors.white),
                size: 28,
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(label, style: const TextStyle(color: Colors.white, fontSize: 12)),
      ],
    );
  }

  Widget _buildAdvancedMenu() {
    final isVideoCall = widget.callModel.callType == CallType.video;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.black87,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Advanced Features',
            style: TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),

          // Screen sharing
          _buildAdvancedOption(
            icon: Icons.screen_share,
            label: 'Screen Share',
            value: widget.agoraService.isScreenSharing,
            onChanged: (value) async {
              await widget.agoraService.toggleScreenSharing(value);
              if (mounted) {
                setState(() {});
              }
            },
          ),

          // Call recording
          _buildAdvancedOption(
            icon: Icons.fiber_manual_record,
            label: 'Record Call',
            value: widget.agoraService.isRecording,
            onChanged: (value) async {
              await widget.agoraService.toggleRecording(value);
              if (mounted) {
                setState(() {});
              }
            },
          ),

          // Noise suppression
          _buildAdvancedOption(
            icon: Icons.noise_control_off,
            label: 'Noise Cancellation',
            value: widget.agoraService.isNoiseSuppressionEnabled,
            onChanged: (value) async {
              await widget.agoraService.toggleNoiseSuppression(value);
              if (mounted) {
                setState(() {});
              }
            },
          ),

          // Beauty filter (video only)
          if (isVideoCall)
            _buildAdvancedOption(
              icon: Icons.face_retouching_natural,
              label: 'Beauty Filter',
              value: widget.agoraService.isBeautyFilterEnabled,
              onChanged: (value) async {
                await widget.agoraService.toggleBeautyFilter(value);
                if (mounted) {
                  setState(() {});
                }
              },
            ),

          if (isVideoCall && widget.agoraService.isBeautyFilterEnabled)
            _buildBeautyLevelControls(),

          // Camera flip (video only)
          if (isVideoCall)
            ListTile(
              dense: true,
              leading: const Icon(Icons.flip_camera_ios, color: Colors.white),
              title: const Text(
                'Flip Camera',
                style: TextStyle(color: Colors.white),
              ),
              onTap: () {
                widget.agoraService.switchCamera();
              },
            ),

          // Video quality selector
          if (isVideoCall) _buildVideoQualitySelector(),

          // Voice effects selector
          _buildVoiceEffectSelector(),
        ],
      ),
    );
  }

  Widget _buildAdvancedOption({
    required IconData icon,
    required String label,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return SwitchListTile(
      dense: true,
      secondary: Icon(icon, color: Colors.white),
      title: Text(label, style: const TextStyle(color: Colors.white)),
      value: value,
      onChanged: onChanged,
      activeColor: AppColors.primary,
    );
  }

  Widget _buildVideoQualitySelector() {
    return ExpansionTile(
      dense: true,
      leading: const Icon(Icons.high_quality, color: Colors.white),
      title: const Text('Video Quality', style: TextStyle(color: Colors.white)),
      children: [
        RadioListTile<VideoQualityPreset>(
          dense: true,
          title: const Text(
            '360p (Low)',
            style: TextStyle(color: Colors.white70),
          ),
          value: VideoQualityPreset.low,
          groupValue: _selectedVideoQuality,
          onChanged: (value) {
            if (value != null) {
              setState(() {
                _selectedVideoQuality = value;
              });
              widget.agoraService.setVideoQuality(value);
            }
          },
        ),
        RadioListTile<VideoQualityPreset>(
          dense: true,
          title: const Text(
            '540p (Medium)',
            style: TextStyle(color: Colors.white70),
          ),
          value: VideoQualityPreset.medium,
          groupValue: _selectedVideoQuality,
          onChanged: (value) {
            if (value != null) {
              setState(() {
                _selectedVideoQuality = value;
              });
              widget.agoraService.setVideoQuality(value);
            }
          },
        ),
        RadioListTile<VideoQualityPreset>(
          dense: true,
          title: const Text(
            '720p (High)',
            style: TextStyle(color: Colors.white70),
          ),
          value: VideoQualityPreset.high,
          groupValue: _selectedVideoQuality,
          onChanged: (value) {
            if (value != null) {
              setState(() {
                _selectedVideoQuality = value;
              });
              widget.agoraService.setVideoQuality(value);
            }
          },
        ),
        RadioListTile<VideoQualityPreset>(
          dense: true,
          title: const Text(
            '1080p (Ultra)',
            style: TextStyle(color: Colors.white70),
          ),
          value: VideoQualityPreset.ultra,
          groupValue: _selectedVideoQuality,
          onChanged: (value) {
            if (value != null) {
              setState(() {
                _selectedVideoQuality = value;
              });
              widget.agoraService.setVideoQuality(value);
            }
          },
        ),
      ],
    );
  }

  Widget _buildVoiceEffectSelector() {
    return ExpansionTile(
      dense: true,
      leading: const Icon(Icons.record_voice_over, color: Colors.white),
      title: const Text('Voice Effects', style: TextStyle(color: Colors.white)),
      children: [
        RadioListTile<VoiceEffectPreset>(
          dense: true,
          title: const Text('None', style: TextStyle(color: Colors.white70)),
          value: VoiceEffectPreset.none,
          groupValue: _selectedVoiceEffect,
          onChanged: (value) {
            if (value != null) {
              setState(() {
                _selectedVoiceEffect = value;
              });
              widget.agoraService.setVoiceEffect(value);
            }
          },
        ),
        RadioListTile<VoiceEffectPreset>(
          dense: true,
          title: const Text(
            'Vigorous',
            style: TextStyle(color: Colors.white70),
          ),
          value: VoiceEffectPreset.vigorous,
          groupValue: _selectedVoiceEffect,
          onChanged: (value) {
            if (value != null) {
              setState(() {
                _selectedVoiceEffect = value;
              });
              widget.agoraService.setVoiceEffect(value);
            }
          },
        ),
        RadioListTile<VoiceEffectPreset>(
          dense: true,
          title: const Text('Deep', style: TextStyle(color: Colors.white70)),
          value: VoiceEffectPreset.deep,
          groupValue: _selectedVoiceEffect,
          onChanged: (value) {
            if (value != null) {
              setState(() {
                _selectedVoiceEffect = value;
              });
              widget.agoraService.setVoiceEffect(value);
            }
          },
        ),
        RadioListTile<VoiceEffectPreset>(
          dense: true,
          title: const Text('Mellow', style: TextStyle(color: Colors.white70)),
          value: VoiceEffectPreset.mellow,
          groupValue: _selectedVoiceEffect,
          onChanged: (value) {
            if (value != null) {
              setState(() {
                _selectedVoiceEffect = value;
              });
              widget.agoraService.setVoiceEffect(value);
            }
          },
        ),
      ],
    );
  }

  Widget _buildBeautyLevelControls() {
    return ExpansionTile(
      dense: true,
      initiallyExpanded: true,
      leading: const Icon(Icons.tune, color: Colors.white),
      title: const Text('Beauty Levels', style: TextStyle(color: Colors.white)),
      children: [
        _buildBeautySlider(
          label: 'Smoothness',
          value: _smoothness,
          onChanged: (value) {
            setState(() => _smoothness = value);
            widget.agoraService.setBeautyLevels(smoothness: value);
          },
        ),
        _buildBeautySlider(
          label: 'Lightening',
          value: _lightening,
          onChanged: (value) {
            setState(() => _lightening = value);
            widget.agoraService.setBeautyLevels(lightening: value);
          },
        ),
        _buildBeautySlider(
          label: 'Redness',
          value: _redness,
          onChanged: (value) {
            setState(() => _redness = value);
            widget.agoraService.setBeautyLevels(redness: value);
          },
        ),
        _buildBeautySlider(
          label: 'Sharpness',
          value: _sharpness,
          onChanged: (value) {
            setState(() => _sharpness = value);
            widget.agoraService.setBeautyLevels(sharpness: value);
          },
        ),
      ],
    );
  }

  Widget _buildBeautySlider({
    required String label,
    required double value,
    required ValueChanged<double> onChanged,
  }) {
    return ListTile(
      dense: true,
      title: Text(label, style: const TextStyle(color: Colors.white70)),
      subtitle: Slider(
        value: value,
        min: 0,
        max: 1,
        divisions: 10,
        label: value.toStringAsFixed(1),
        activeColor: AppColors.primary,
        onChanged: onChanged,
      ),
      trailing: Text(
        value.toStringAsFixed(1),
        style: const TextStyle(color: Colors.white70),
      ),
    );
  }

  Widget _buildNetworkQualityIndicator() {
    final quality = widget.agoraService.getNetworkQualityText();
    Color indicatorColor;

    switch (widget.agoraService.networkQuality) {
      case 1:
      case 2:
        indicatorColor = Colors.green;
        break;
      case 3:
        indicatorColor = Colors.orange;
        break;
      case 4:
      case 5:
        indicatorColor = Colors.red;
        break;
      default:
        indicatorColor = Colors.grey;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.signal_cellular_alt, color: indicatorColor, size: 16),
          const SizedBox(width: 6),
          Text(
            quality,
            style: const TextStyle(color: Colors.white, fontSize: 12),
          ),
        ],
      ),
    );
  }
}
