import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart';

class CallRingtoneService {
  static final CallRingtoneService _instance = CallRingtoneService._internal();
  factory CallRingtoneService() => _instance;
  CallRingtoneService._internal();

  final AudioPlayer _audioPlayer = AudioPlayer();
  bool _isPlaying = false;
  String? _currentCallId;

  /// Start playing ringtone for an incoming call
  Future<void> startRingtone(String callId) async {
    if (_isPlaying && _currentCallId == callId) {
      print('[Ringtone] Already playing for call $callId');
      return;
    }

    await stopRingtone();

    _currentCallId = callId;
    _isPlaying = true;

    try {
      // Configure audio player for continuous looping
      await _audioPlayer.setReleaseMode(ReleaseMode.loop);
      await _audioPlayer.setVolume(1.0);

      // Try multiple ringtone sources in order of preference
      bool played = false;

      // 1. Try to play custom ringtone from assets (if available)
      try {
        await _audioPlayer.play(AssetSource('sounds/ringtone.mp3'));
        played = true;
        print('[Ringtone] Playing custom ringtone for call $callId');
      } catch (e) {
        print('[Ringtone] Custom ringtone not found: $e');
      }

      // 2. If custom ringtone failed, try online fallback
      if (!played) {
        try {
          await _audioPlayer.play(
            UrlSource(
              'https://www.soundjay.com/phone/sounds/phone-calling-1.mp3',
            ),
          );
          played = true;
          print('[Ringtone] Playing online ringtone for call $callId');
        } catch (e) {
          print('[Ringtone] Online ringtone failed: $e');
        }
      }

      // 3. Final fallback: use native system ringtone
      if (!played) {
        print('[Ringtone] Using system ringtone fallback');
        await _playSystemRingtone();
      }
    } catch (e) {
      print('[Ringtone] Error starting ringtone: $e');
      _isPlaying = false;
      _currentCallId = null;
    }
  }

  /// Play system ringtone as fallback
  Future<void> _playSystemRingtone() async {
    try {
      // Use system method channel to play ringtone
      const platform = MethodChannel('com.whatsapp.clone/ringtone');
      await platform.invokeMethod('playRingtone');
      print('[Ringtone] Playing system ringtone');
    } catch (e) {
      print('[Ringtone] System ringtone fallback failed: $e');
    }
  }

  /// Stop playing ringtone
  Future<void> stopRingtone() async {
    if (!_isPlaying) return;

    try {
      await _audioPlayer.stop();
      print('[Ringtone] Stopped for call $_currentCallId');
    } catch (e) {
      print('[Ringtone] Error stopping ringtone: $e');
    }

    _isPlaying = false;
    _currentCallId = null;

    // Stop system ringtone if it was playing
    try {
      const platform = MethodChannel('com.whatsapp.clone/ringtone');
      await platform.invokeMethod('stopRingtone');
    } catch (e) {
      // Ignore, system ringtone might not be playing
    }
  }

  /// Check if ringtone is currently playing
  bool get isPlaying => _isPlaying;

  /// Get current call ID that's ringing
  String? get currentCallId => _currentCallId;

  /// Dispose resources
  Future<void> dispose() async {
    await stopRingtone();
    await _audioPlayer.dispose();
  }
}
