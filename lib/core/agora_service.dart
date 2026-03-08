import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';

class AgoraService extends ChangeNotifier {
  late RtcEngine _engine;
  bool _isInitialized = false;
  bool _isAudioMuted = false;
  bool _isVideoEnabled = true;
  bool _isSpeakerEnabled = true;

  static const String agoraAppId = '1c8f63330cd84646a45c26d3177d4c18';

  bool get isAudioMuted => _isAudioMuted;
  bool get isVideoEnabled => _isVideoEnabled;
  bool get isSpeakerEnabled => _isSpeakerEnabled;
  bool get isInitialized => _isInitialized;

  Future<void> initialize() async {
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
              },
        ),
      );

      _isInitialized = true;
      print('[Agora] Initialized successfully');
    } catch (e) {
      print('[Agora] Initialization error: $e');
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
    if (!_isInitialized) await initialize();

    try {
      await requestPermissions(isVideoCall: isVideoCall);

      // Enable audio
      await _engine.enableAudio();

      // Setup video if enabled
      if (isVideoCall) {
        await _engine.enableVideo();
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

      // Join channel
      await _engine.joinChannel(
        token: token,
        channelId: channelName,
        uid: uid,
        options: const RtcChannelMediaOptions(
          autoSubscribeAudio: true,
          autoSubscribeVideo: isVideoCall,
          publishMicrophoneTrack: true,
          publishCameraTrack: isVideoCall,
        ),
      );

      print('[Agora] Joined channel: $channelName');
    } catch (e) {
      print('[Agora] Error joining channel: $e');
      rethrow;
    }
  }

  Future<void> leaveChannel() async {
    try {
      await _engine.leaveChannel();
      print('[Agora] Left channel');
    } catch (e) {
      print('[Agora] Error leaving channel: $e');
    }
  }

  Future<void> toggleAudio(bool mute) async {
    try {
      await _engine.muteLocalAudioStream(mute);
      _isAudioMuted = mute;
      notifyListeners();
    } catch (e) {
      print('[Agora] Error toggling audio: $e');
    }
  }

  Future<void> toggleVideo(bool enable) async {
    try {
      await _engine.muteLocalVideoStream(!enable);
      _isVideoEnabled = enable;
      notifyListeners();
    } catch (e) {
      print('[Agora] Error toggling video: $e');
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

  Future<void> dispose() async {
    try {
      await _engine.leaveChannel();
      await _engine.release();
      print('[Agora] Disposed');
    } catch (e) {
      print('[Agora] Error disposing: $e');
    }
  }
}
