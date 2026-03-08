import 'package:flutter/material.dart';
import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:whatsapp_clone/models/call_model.dart';
import 'package:whatsapp_clone/core/design_tokens.dart';
import 'package:whatsapp_clone/core/agora_service.dart';

class InCallScreen extends StatefulWidget {
  final CallModel callModel;
  final AgoraService agoraService;
  final VoidCallback onEndCall;
  final int remoteUid;

  const InCallScreen({
    super.key,
    required this.callModel,
    required this.agoraService,
    required this.onEndCall,
    required this.remoteUid,
  });

  @override
  State<InCallScreen> createState() => _InCallScreenState();
}

class _InCallScreenState extends State<InCallScreen> {
  late RtcEngine _engine;
  bool _isVideoVisible = true;
  Duration _callDuration = Duration.zero;
  late Stopwatch _stopwatch;

  @override
  void initState() {
    super.initState();
    _engine =
        RtcEngineContext(
              appId: widget.agoraService.runtimeType.toString(),
            ).createAgoraRtcEngine()
            as RtcEngine;
    _stopwatch = Stopwatch()..start();

    // Update call duration every second
    Future.delayed(const Duration(seconds: 1), _updateDuration);
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
    super.dispose();
  }

  String _formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes % 60;
    final seconds = duration.inSeconds % 60;

    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final isVideoCall = widget.callModel.callType == 'video';

    return WillPopScope(
      onWillPop: () async => false,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          children: [
            // Video/Audio area
            if (isVideoCall)
              Container(
                color: Colors.black,
                child: Center(
                  child: _isVideoVisible
                      ? AgoraVideoView(
                          controller: VideoViewController(
                            rtcEngine: _engine,
                            canvas: const VideoCanvas(uid: 0),
                          ),
                        )
                      : Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            CachedNetworkImage(
                              imageUrl: widget.callModel.receiverProfilePic,
                              width: 150,
                              height: 150,
                              fit: BoxFit.cover,
                              imageBuilder: (context, imageProvider) =>
                                  CircleAvatar(
                                    backgroundImage: imageProvider,
                                    radius: 75,
                                  ),
                              errorWidget: (context, url, error) =>
                                  CircleAvatar(
                                    radius: 75,
                                    child: const Icon(Icons.person),
                                  ),
                            ),
                            const SizedBox(height: AppSpacing.lg),
                            Text(
                              widget.callModel.receiverName,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                ),
              )
            else
              // Audio call background
              Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CachedNetworkImage(
                      imageUrl: widget.callModel.receiverProfilePic,
                      imageBuilder: (context, imageProvider) => CircleAvatar(
                        backgroundImage: imageProvider,
                        radius: 75,
                      ),
                      errorWidget: (context, url, error) => CircleAvatar(
                        radius: 75,
                        child: const Icon(Icons.person),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    Text(
                      widget.callModel.receiverName,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),

            // Top bar with duration
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        _formatDuration(_callDuration),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (isVideoCall)
                        IconButton(
                          icon: const Icon(
                            Icons.fullscreen,
                            color: Colors.white,
                          ),
                          onPressed: () {
                            setState(() {
                              _isVideoVisible = !_isVideoVisible;
                            });
                          },
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
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      // Mute audio button
                      FloatingActionButton(
                        onPressed: () async {
                          // Toggle audio mute
                          await widget.agoraService.toggleAudio(
                            !widget.agoraService.isAudioMuted,
                          );
                        },
                        backgroundColor: widget.agoraService.isAudioMuted
                            ? Colors.red
                            : Colors.grey.shade700,
                        heroTag: 'audio_btn',
                        child: Icon(
                          widget.agoraService.isAudioMuted
                              ? Icons.mic_off
                              : Icons.mic,
                        ),
                      ),

                      // End call button
                      FloatingActionButton(
                        onPressed: widget.onEndCall,
                        backgroundColor: Colors.red,
                        heroTag: 'end_btn',
                        child: const Icon(Icons.call_end),
                      ),

                      // Toggle video button (only for video calls)
                      if (isVideoCall)
                        FloatingActionButton(
                          onPressed: () async {
                            await widget.agoraService.toggleVideo(
                              !widget.agoraService.isVideoEnabled,
                            );
                          },
                          backgroundColor: widget.agoraService.isVideoEnabled
                              ? Colors.grey.shade700
                              : Colors.red,
                          heroTag: 'video_btn',
                          child: Icon(
                            widget.agoraService.isVideoEnabled
                                ? Icons.videocam
                                : Icons.videocam_off,
                          ),
                        ),

                      // Speaker button
                      FloatingActionButton(
                        onPressed: () async {
                          await widget.agoraService.toggleSpeaker(
                            !widget.agoraService.isSpeakerEnabled,
                          );
                        },
                        backgroundColor: widget.agoraService.isSpeakerEnabled
                            ? Colors.grey.shade700
                            : Colors.orange,
                        heroTag: 'speaker_btn',
                        child: Icon(
                          widget.agoraService.isSpeakerEnabled
                              ? Icons.speaker
                              : Icons.speaker_off,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
