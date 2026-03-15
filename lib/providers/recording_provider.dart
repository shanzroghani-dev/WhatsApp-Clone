import 'dart:async';

import 'package:flutter/foundation.dart';

/// Recording state notifier for voice message recording
class RecordingStateNotifier extends ChangeNotifier {
  bool _isRecording = false;
  Duration _recordingDuration = Duration.zero;
  Timer? _recordingTimer;
  double _recordingSlideOffset = 0;
  bool _recordingCancelTriggered = false;
  String? _playingAudioMessageId;

  // Getters
  bool get isRecording => _isRecording;
  Duration get recordingDuration => _recordingDuration;
  Timer? get recordingTimer => _recordingTimer;
  double get recordingSlideOffset => _recordingSlideOffset;
  bool get recordingCancelTriggered => _recordingCancelTriggered;
  String? get playingAudioMessageId => _playingAudioMessageId;

  // Setters
  void setIsRecording(bool value) {
    _isRecording = value;
    notifyListeners();
  }

  void setRecordingDuration(Duration duration) {
    _recordingDuration = duration;
    notifyListeners();
  }

  void setRecordingTimer(Timer? timer) {
    _recordingTimer = timer;
    notifyListeners();
  }

  void setRecordingSlideOffset(double offset) {
    _recordingSlideOffset = offset;
    notifyListeners();
  }

  void setRecordingCancelTriggered(bool value) {
    _recordingCancelTriggered = value;
    notifyListeners();
  }

  void setPlayingAudioMessageId(String? id) {
    _playingAudioMessageId = id;
    notifyListeners();
  }

  void reset() {
    _isRecording = false;
    _recordingDuration = Duration.zero;
    _recordingSlideOffset = 0;
    _recordingCancelTriggered = false;
    notifyListeners();
  }
}
