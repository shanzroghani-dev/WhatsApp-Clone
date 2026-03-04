import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:record/record.dart';
import 'package:whatsapp_clone/chat/chat_service.dart';
import 'package:whatsapp_clone/models/message_model.dart';

/// Mixin for voice message handling
mixin VoiceMessageHandler {
  /// Voice recording state variables
  bool get isRecordingVoice;
  Duration get recordingDuration;
  Timer? get recordingTimer;
  String? get playingAudioMessageId;
  double get recordingSlideOffset;
  bool get recordingCancelTriggered;
  String? get attachmentCacheDirPath;
  Set<String> get uploadingMessageIds;
  Set<String> get downloadingMessageIds;

  /// Audio instances
  AudioRecorder get audioRecorder;
  AudioPlayer get audioPlayer;

  /// Widget context for showing snackbars
  BuildContext get context;

  /// Mounted check
  bool get mounted;

  /// Getters for dependent state
  String get currentUserId;
  String get peerUserId;

  /// State update method
  void setState(VoidCallback fn);

  /// Voice recording state setters (implemented by host class)
  void setIsRecordingVoice(bool value);
  void setRecordingDuration(Duration duration);
  void setRecordingTimer(Timer? timer);
  void setRecordingSlideOffset(double offset);
  void setRecordingCancelTriggered(bool value);
  void setPlayingAudioMessageId(String? id);

  /// Helper methods
  String formatRecordingDuration(Duration duration) {
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  /// Start voice recording
  Future<void> startVoiceRecording() async {
    if (isRecordingVoice) return;

    try {
      final hasPermission = await audioRecorder.hasPermission();
      if (!hasPermission) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Microphone permission is required')),
        );
        return;
      }

      final baseDir = attachmentCacheDirPath;
      if (baseDir == null) {
        throw Exception('Cache directory unavailable');
      }

      final filePath =
          '$baseDir/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
      await audioRecorder.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          bitRate: 128000,
          sampleRate: 44100,
        ),
        path: filePath,
      );

      recordingTimer?.cancel();
      setRecordingTimer(
        Timer.periodic(const Duration(seconds: 1), (_) {
          if (!mounted || !isRecordingVoice) return;
          setRecordingDuration(
            Duration(seconds: recordingDuration.inSeconds + 1),
          );
        }),
      );

      if (!mounted) return;
      setIsRecordingVoice(true);
      setRecordingDuration(Duration.zero);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not start recording')),
      );
    }
  }

  /// Cancel voice recording
  Future<void> cancelVoiceRecording() async {
    if (!isRecordingVoice) return;

    recordingTimer?.cancel();
    final path = await audioRecorder.stop();
    if (path != null) {
      final file = File(path);
      if (await file.exists()) {
        await file.delete();
      }
    }

    if (!mounted) return;
    setIsRecordingVoice(false);
    setRecordingDuration(Duration.zero);
    setRecordingSlideOffset(0);
    setRecordingCancelTriggered(false);
  }

  /// Stop recording and send voice message
  Future<void> stopAndSendVoiceRecording() async {
    if (!isRecordingVoice) return;

    recordingTimer?.cancel();
    final path = await audioRecorder.stop();
    final duration = recordingDuration;

    if (!mounted) return;
    setIsRecordingVoice(false);
    setRecordingDuration(Duration.zero);
    setRecordingSlideOffset(0);
    setRecordingCancelTriggered(false);

    if (path == null || duration.inSeconds <= 0) {
      return;
    }

    unawaited(sendVoiceMessage(filePath: path, duration: duration));
  }

  /// Long press start handler
  void onVoiceLongPressStart(LongPressStartDetails _) {
    setRecordingCancelTriggered(false);
    setRecordingSlideOffset(0);
    unawaited(startVoiceRecording());
  }

  /// Long press move handler
  void onVoiceLongPressMove(LongPressMoveUpdateDetails details) {
    if (!isRecordingVoice || recordingCancelTriggered) return;
    final dx = details.offsetFromOrigin.dx;
    final clamped = dx < 0 ? dx.clamp(-140.0, 0.0) : 0.0;
    if (mounted) {
      setRecordingSlideOffset(clamped);
    }

    if (dx <= -100) {
      setRecordingCancelTriggered(true);
      unawaited(cancelVoiceRecording());
    }
  }

  /// Long press end handler
  void onVoiceLongPressEnd(LongPressEndDetails _) {
    if (!isRecordingVoice) return;
    if (recordingCancelTriggered) return;
    unawaited(stopAndSendVoiceRecording());
  }

  /// Send voice message
  Future<void> sendVoiceMessage({
    required String filePath,
    required Duration duration,
  }) async {
    final file = File(filePath);
    if (!await file.exists()) return;

    try {
      final bytes = await file.readAsBytes();
      final fileName = 'voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
      await file.delete();

      final message = await ChatService.sendVoiceAttachment(
        fromId: currentUserId,
        toId: peerUserId,
        bytes: bytes,
        fileName: fileName,
        durationMs: duration.inMilliseconds,
      );

      // Reload messages to get the real message
      // Note: This is called from the parent class
      // For now, just ensure the message was sent
      if (message.id.isEmpty) {
        throw Exception('Failed to send voice message');
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to send voice message')),
      );
    }
  }

  /// Toggle audio playback
  Future<void> toggleAudioPlayback({
    required MessageModel message,
    required Map<String, dynamic> attachment,
  }) async {
    try {
      if (playingAudioMessageId == message.id) {
        await audioPlayer.stop();
        if (!mounted) return;
        setPlayingAudioMessageId(null);
        return;
      }

      String? localPath = getCachedAttachmentPath(message, attachment);
      localPath ??= await downloadAttachment(
        message: message,
        attachment: attachment,
      );
      if (localPath == null) return;

      await audioPlayer.stop();
      await audioPlayer.play(DeviceFileSource(localPath));
      if (!mounted) return;
      setPlayingAudioMessageId(message.id);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not play voice message')),
      );
    }
  }

  /// Get cached attachment path (from media handler)
  String? getCachedAttachmentPath(
    MessageModel message,
    Map<String, dynamic> attachment,
  );

  /// Download attachment (from media handler)
  Future<String?> downloadAttachment({
    required MessageModel message,
    required Map<String, dynamic> attachment,
  });
}
