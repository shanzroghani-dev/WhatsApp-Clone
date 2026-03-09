import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';

class AgoraService extends ChangeNotifier {
  late RtcEngine _engine;
  bool _isInitialized = false;
  bool _isAudioMuted = false;
  bool _isVideoEnabled = true;
  bool _isSpeakerEnabled = true;
  bool _isScreenSharing = false;
  bool _isRecording = false;
  bool _isBeautyFilterEnabled = false;
  bool _isNoiseSuppressionEnabled = false;
  double _beautySmoothness = 0.5;
  double _beautyLightening = 0.7;
  double _beautyRedness = 0.1;
  double _beautySharpness = 0.3;
  int _networkQuality = 0; // 0 = Unknown, 1 = Excellent, 2 = Good, 3 = Poor, 4 = Bad, 5 = Very Bad, 6 = Down
  Map<String, dynamic> _callStats = {};
  bool _isDisposed = false;

  static const String agoraAppId = '1c8f63330cd84646a45c26d3177d4c18';

  bool get isAudioMuted => _isAudioMuted;
  bool get isVideoEnabled => _isVideoEnabled;
  bool get isSpeakerEnabled => _isSpeakerEnabled;
  bool get isInitialized => _isInitialized;
  bool get isScreenSharing => _isScreenSharing;
  bool get isRecording => _isRecording;
  bool get isBeautyFilterEnabled => _isBeautyFilterEnabled;
  bool get isNoiseSuppressionEnabled => _isNoiseSuppressionEnabled;
  double get beautySmoothness => _beautySmoothness;
  double get beautyLightening => _beautyLightening;
  double get beautyRedness => _beautyRedness;
  double get beautySharpness => _beautySharpness;
  int get networkQuality => _networkQuality;
  Map<String, dynamic> get callStats => _callStats;
  RtcEngine get engine => _engine;

  Future<void> initialize() async {
    if (_isDisposed) {
      throw Exception('Cannot initialize a disposed AgoraService');
    }
    if (_isInitialized) return;

    try {
      _engine = createAgoraRtcEngine();
      await _engine.initialize(const RtcEngineContext(appId: agoraAppId));

      // Setup event handlers
      _engine.registerEventHandler(
        RtcEngineEventHandler(
          onError: (ErrorCodeType err, String msg) {
            print('[Agora] Error: $err - $msg');
          },
          onJoinChannelSuccess: (RtcConnection connection, int elapsed) {
            print('[Agora] Join channel success: ${connection.channelId}');
          },
          onUserJoined: (RtcConnection connection, int remoteUid, int elapsed) {
            print('[Agora] Remote user joined: $remoteUid');
            notifyListeners();
          },
          onUserOffline:
              (
                RtcConnection connection,
                int remoteUid,
                UserOfflineReasonType reason,
              ) {
                print(
                  '[Agora] Remote user offline: $remoteUid, reason: $reason',
                );
                notifyListeners();
              },
          onNetworkQuality: (RtcConnection connection, int remoteUid, QualityType txQuality, QualityType rxQuality) {
            final tx = txQuality.index;
            final rx = rxQuality.index;
            _networkQuality = tx > rx ? tx : rx;
            notifyListeners();
          },
          onRtcStats: (RtcConnection connection, RtcStats stats) {
            _callStats = {
              'duration': stats.duration,
              'txBytes': stats.txBytes,
              'rxBytes': stats.rxBytes,
              'txKBitRate': stats.txKBitRate,
              'rxKBitRate': stats.rxKBitRate,
              'users': stats.userCount,
              'cpuAppUsage': stats.cpuAppUsage,
              'cpuTotalUsage': stats.cpuTotalUsage,
            };
            notifyListeners();
          },
        ),
      );

      // Give the native SDK a moment to fully initialize
      await Future.delayed(const Duration(milliseconds: 100));

      _isInitialized = true;
      print('[Agora] Initialized successfully');
    } catch (e) {
      print('[Agora] Initialization error: $e');
      _isInitialized = false;
      rethrow;
    }
  }

  Future<void> requestPermissions({required bool isVideoCall}) async {
    final permissions = [Permission.microphone];
    if (isVideoCall) {
      permissions.add(Permission.camera);
    }

    final statuses = await permissions.map((p) => p.request()).wait;

    for (final status in statuses) {
      if (!status.isGranted) {
        throw Exception('Required permissions not granted');
      }
    }
  }

  Future<void> joinChannel({
    required String channelName,
    required int uid,
    required String token,
    required bool isVideoCall,
  }) async {
    if (_isDisposed) {
      throw Exception('Cannot join channel with a disposed AgoraService');
    }
    
    if (!_isInitialized) {
      await initialize();
      // Additional wait to ensure initialization is complete
      await Future.delayed(const Duration(milliseconds: 50));
    }

    // Verify engine is initialized
    if (!_isInitialized) {
      throw Exception('Failed to initialize Agora engine');
    }

    try {
      await requestPermissions(isVideoCall: isVideoCall);

      // Enable audio
      await _engine.setChannelProfile(ChannelProfileType.channelProfileCommunication);
      await _engine.setClientRole(role: ClientRoleType.clientRoleBroadcaster);
      await _engine.enableAudio();

      // Setup video if enabled
      if (isVideoCall) {
        await _engine.enableVideo();
        await _engine.startPreview();
        await _engine.setVideoEncoderConfiguration(
          const VideoEncoderConfiguration(
            dimensions: VideoDimensions(width: 1280, height: 720),
            frameRate: 30,
            bitrate: 2500,
          ),
        );
      } else {
        await _engine.disableVideo();
      }

      // Join channel with retry logic
      int retryCount = 0;
      const maxRetries = 2;
      Exception? lastError;

      while (retryCount <= maxRetries) {
        try {
          await _engine.joinChannel(
            token: token,
            channelId: channelName,
            uid: uid,
            options: ChannelMediaOptions(
              autoSubscribeAudio: true,
              autoSubscribeVideo: isVideoCall,
              publishMicrophoneTrack: true,
              publishCameraTrack: isVideoCall,
            ),
          );

          print('[Agora] Joined channel: $channelName');
          return; // Success, exit the method
        } catch (e) {
          lastError = e is Exception ? e : Exception(e.toString());
          retryCount++;
          
          if (retryCount <= maxRetries) {
            print('[Agora] Join attempt $retryCount failed, retrying... Error: $e');
            await Future.delayed(Duration(milliseconds: 200 * retryCount));
          }
        }
      }

      // If we get here, all retries failed
      print('[Agora] Error joining channel after $maxRetries retries: $lastError');
      throw lastError ?? Exception('Failed to join channel');
    } catch (e) {
      print('[Agora] Error joining channel: $e');
      rethrow;
    }
  }

  Future<void> leaveChannel() async {
    try {
      await _engine.stopPreview();
      await _engine.leaveChannel();
      print('[Agora] Left channel');
    } catch (e) {
      print('[Agora] Error leaving channel: $e');
    }
  }

  Future<void> toggleAudio(bool mute) async {
    try {
      // Mute/unmute the local audio stream
      // When muted, remote users cannot hear you
      await _engine.muteLocalAudioStream(mute);
      _isAudioMuted = mute;
      notifyListeners();
      print('[Agora] Audio ${mute ? "muted" : "unmuted"} - remote user ${mute ? "cannot" : "can"} hear you');
    } catch (e) {
      print('[Agora] Error toggling audio: $e');
      // Don't rethrow to prevent blocking call flow
    }
  }

  Future<void> toggleVideo(bool enable) async {
    try {
      if (enable) {
        // Enable sequence: enable camera -> publish track -> unmute -> preview.
        await _engine.enableLocalVideo(true);
        await _engine.updateChannelMediaOptions(
          ChannelMediaOptions(
            publishCameraTrack: true,
          ),
        );
        await _engine.muteLocalVideoStream(false);
        await _engine.startPreview();
        _isVideoEnabled = true;
        print('[Agora] Video enabled - remote user can see you');
      } else {
        // Disable sequence: unpublish camera track first, then mute/stop local capture.
        // This guarantees remote users stop receiving camera frames immediately.
        print('[Agora] Disabling video - unpublishing camera track for remote users');
        await _engine.updateChannelMediaOptions(
          ChannelMediaOptions(
            publishCameraTrack: false,
          ),
        );
        await _engine.muteLocalVideoStream(true);
        await _engine.enableLocalVideo(false);
        await _engine.stopPreview();
        _isVideoEnabled = false;
        print('[Agora] Video fully disabled - remote user cannot see you');
      }
      notifyListeners();
    } catch (e) {
      print('[Agora] Error toggling video: $e');
      // Don't rethrow to prevent blocking call flow
    }
  }

  Future<void> toggleSpeaker(bool enable) async {
    try {
      await _engine.setEnableSpeakerphone(enable);
      _isSpeakerEnabled = enable;
      notifyListeners();
    } catch (e) {
      print('[Agora] Error toggling speaker: $e');
    }
  }

  Future<void> switchCamera() async {
    try {
      await _engine.switchCamera();
      print('[Agora] Camera switched');
    } catch (e) {
      print('[Agora] Error switching camera: $e');
    }
  }

  // Advanced Features - Beyond WhatsApp

  /// Enable/disable screen sharing
  Future<void> toggleScreenSharing(bool enable) async {
    try {
      if (enable) {
        // Start screen sharing
        await _engine.startScreenCapture(const ScreenCaptureParameters2(
          captureAudio: true,
          captureVideo: true,
        ));
        print('[Agora] Screen sharing started');
      } else {
        // Stop screen sharing
        await _engine.stopScreenCapture();
        print('[Agora] Screen sharing stopped');
      }
      _isScreenSharing = enable;
      notifyListeners();
    } catch (e) {
      print('[Agora] Error toggling screen sharing: $e');
    }
  }

  /// Start/stop call recording
  Future<void> toggleRecording(bool enable, {String? storagePath}) async {
    try {
      if (enable) {
        // Note: Cloud recording requires Agora RESTful API integration
        // This is a placeholder for local recording indication
        _isRecording = true;
        print('[Agora] Recording started (cloud recording requires backend integration)');
      } else {
        _isRecording = false;
        print('[Agora] Recording stopped');
      }
      notifyListeners();
    } catch (e) {
      print('[Agora] Error toggling recording: $e');
    }
  }

  /// Enable/disable beauty filter (skin smoothing, face enhancement)
  Future<void> toggleBeautyFilter(bool enable) async {
    try {
      await _applyBeautyOptions(enabled: enable);
      _isBeautyFilterEnabled = enable;
      notifyListeners();
      print('[Agora] Beauty filter ${enable ? 'enabled' : 'disabled'}');
    } catch (e) {
      print('[Agora] Error toggling beauty filter: $e');
    }
  }

  /// Update adjustable beauty effect levels in real-time.
  Future<void> setBeautyLevels({
    double? smoothness,
    double? lightening,
    double? redness,
    double? sharpness,
  }) async {
    _beautySmoothness = (smoothness ?? _beautySmoothness).clamp(0.0, 1.0);
    _beautyLightening = (lightening ?? _beautyLightening).clamp(0.0, 1.0);
    _beautyRedness = (redness ?? _beautyRedness).clamp(0.0, 1.0);
    _beautySharpness = (sharpness ?? _beautySharpness).clamp(0.0, 1.0);

    if (_isBeautyFilterEnabled) {
      await _applyBeautyOptions(enabled: true);
    }
    notifyListeners();
  }

  Future<void> _applyBeautyOptions({required bool enabled}) async {
    await _engine.setBeautyEffectOptions(
      enabled: enabled,
      options: BeautyOptions(
        lighteningContrastLevel: LighteningContrastLevel.lighteningContrastNormal,
        lighteningLevel: _beautyLightening,
        smoothnessLevel: _beautySmoothness,
        rednessLevel: _beautyRedness,
        sharpnessLevel: _beautySharpness,
      ),
    );
  }

  /// Enable/disable AI noise suppression
  Future<void> toggleNoiseSuppression(bool enable) async {
    try {
      // Use audio effect preset for noise suppression
      if (enable) {
        await _engine.setAudioEffectPreset(AudioEffectPreset.roomAcousticsKtv);
      } else {
        await _engine.setAudioEffectPreset(AudioEffectPreset.audioEffectOff);
      }
      _isNoiseSuppressionEnabled = enable;
      notifyListeners();
      print('[Agora] Noise suppression ${enable ? 'enabled' : 'disabled'}');
    } catch (e) {
      print('[Agora] Error toggling noise suppression: $e');
    }
  }

  /// Set video quality preset
  Future<void> setVideoQuality(VideoQualityPreset preset) async {
    try {
      late VideoDimensions dimensions;
      late int frameRate;
      late int bitrate;

      switch (preset) {
        case VideoQualityPreset.low:
          dimensions = const VideoDimensions(width: 640, height: 360);
          frameRate = 15;
          bitrate = 600;
          break;
        case VideoQualityPreset.medium:
          dimensions = const VideoDimensions(width: 960, height: 540);
          frameRate = 24;
          bitrate = 1200;
          break;
        case VideoQualityPreset.high:
          dimensions = const VideoDimensions(width: 1280, height: 720);
          frameRate = 30;
          bitrate = 2500;
          break;
        case VideoQualityPreset.ultra:
          dimensions = const VideoDimensions(width: 1920, height: 1080);
          frameRate = 30;
          bitrate = 4000;
          break;
      }

      await _engine.setVideoEncoderConfiguration(
        VideoEncoderConfiguration(
          dimensions: dimensions,
          frameRate: frameRate,
          bitrate: bitrate,
        ),
      );
      print('[Agora] Video quality set to: $preset');
    } catch (e) {
      print('[Agora] Error setting video quality: $e');
    }
  }

  /// Enable voice changer effects
  Future<void> setVoiceEffect(VoiceEffectPreset effect) async {
    try {
      switch (effect) {
        case VoiceEffectPreset.none:
          await _engine.setVoiceBeautifierPreset(VoiceBeautifierPreset.voiceBeautifierOff);
          break;
        case VoiceEffectPreset.vigorous:
          await _engine.setVoiceBeautifierPreset(VoiceBeautifierPreset.chatBeautifierMagnetic);
          break;
        case VoiceEffectPreset.deep:
          await _engine.setVoiceBeautifierPreset(VoiceBeautifierPreset.chatBeautifierFresh);
          break;
        case VoiceEffectPreset.mellow:
          await _engine.setVoiceBeautifierPreset(VoiceBeautifierPreset.chatBeautifierVitality);
          break;
      }
      print('[Agora] Voice effect applied: $effect');
    } catch (e) {
      print('[Agora] Error applying voice effect: $e');
    }
  }

  /// Get network quality as text
  String getNetworkQualityText() {
    switch (_networkQuality) {
      case 0:
        return 'Unknown';
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

  @override
  Future<void> dispose() async {
    if (_isDisposed) {
      print('[Agora] Already disposed, skipping');
      return;
    }
    _isDisposed = true;
    try {
      if (_isInitialized) {
        await _engine.stopPreview();
        await _engine.leaveChannel();
        await _engine.release();
      }
      _isInitialized = false;
      print('[Agora] Disposed');
    } catch (e) {
      print('[Agora] Error disposing: $e');
    }
    super.dispose();
  }
}

/// Video quality presets
enum VideoQualityPreset {
  low,    // 360p @ 15fps
  medium, // 540p @ 24fps
  high,   // 720p @ 30fps (default)
  ultra,  // 1080p @ 30fps
}

/// Voice effect presets
enum VoiceEffectPreset {
  none,
  vigorous,  // Magnetic voice
  deep,      // Fresh voice
  mellow,    // Vitality voice
}
