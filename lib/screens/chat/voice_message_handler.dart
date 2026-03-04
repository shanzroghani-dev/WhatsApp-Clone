import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:record/record.dart';
import 'package:whatsapp_clone/chat/chat_service.dart';
import 'package:whatsapp_clone/models/message_model.dart';
import 'package:whatsapp_clone/providers/recording_provider.dart';
import 'package:whatsapp_clone/providers/upload_provider.dart';

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

  /// Provider accessors
  RecordingStateNotifier get recordingProvider =>
      Provider.of<RecordingStateNotifier>(context, listen: false);

  UploadStateNotifier get uploadProvider =>
      Provider.of<UploadStateNotifier>(context, listen: false);

  /// State update method
  void setState(VoidCallback fn);

  /// Voice recording state setters (implemented by host class)
  void setIsRecordingVoice(bool value);
  void setRecordingDuration(Duration duration);
  void setRecordingTimer(Timer? timer);
  void setRecordingSlideOffset(double offset);
  void setRecordingCancelTriggered(bool value);
  void setPlayingAudioMessageId(String? id);

  /// Message management methods (implemented by host class)
  void insertMessage(MessageModel message);
  void removeMessage(String id);
  void updateCachedAttachmentPath(String key, String path);
  void removeCachedAttachmentPath(String key);
  Future<void> loadMessages({bool scrollToBottom});
  ScrollController get scrollController;

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
      recordingProvider.setRecordingTimer(
        Timer.periodic(const Duration(seconds: 1), (_) {
          if (!mounted || !isRecordingVoice) return;
          recordingProvider.setRecordingDuration(
            Duration(seconds: recordingDuration.inSeconds + 1),
          );
        }),
      );

      if (!mounted) return;
      recordingProvider.setIsRecording(true);
      recordingProvider.setRecordingDuration(Duration.zero);
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
    recordingProvider.setIsRecording(false);
    recordingProvider.setRecordingDuration(Duration.zero);
    recordingProvider.setRecordingSlideOffset(0);
    recordingProvider.setRecordingCancelTriggered(false);

    if (path == null || duration.inSeconds <= 0) {
      return;
    }

    unawaited(sendVoiceMessage(filePath: path, duration: duration));
  }

  /// Long press start handler
  void onVoiceLongPressStart(LongPressStartDetails _) {
    recordingProvider.setRecordingCancelTriggered(false);
    recordingProvider.setRecordingSlideOffset(0);
    unawaited(startVoiceRecording());
  }

  /// Long press move handler
  void onVoiceLongPressMove(LongPressMoveUpdateDetails details) {
    if (!isRecordingVoice || recordingCancelTriggered) return;
    final dx = details.offsetFromOrigin.dx;
    final clamped = dx < 0 ? dx.clamp(-140.0, 0.0) : 0.0;
    if (mounted) {
      recordingProvider.setRecordingSlideOffset(clamped);
    }

    if (dx <= -100) {
      recordingProvider.setRecordingCancelTriggered(true);
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

    final fileName = 'voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
    final tempMessageId = 'uploading_${DateTime.now().millisecondsSinceEpoch}';

    try {
      // Create temporary message payload
      final tempPayload = jsonEncode({
        'type': 'audio',
        'url': '',
        'name': fileName,
        'storagePath': '',
        'sizeBytes': await file.length(),
        'durationMs': duration.inMilliseconds,
      });

      // Create temporary message to show immediately
      final tempMessage = MessageModel(
        id: tempMessageId,
        fromId: currentUserId,
        toId: peerUserId,
        text: '${ChatService.attachmentPrefix}$tempPayload',
        timestamp: DateTime.now().millisecondsSinceEpoch,
        delivered: false,
      );

      // Add to uploading set and insert message
      uploadProvider.addUploadingMessageId(tempMessageId);
      insertMessage(tempMessage);
      updateCachedAttachmentPath(tempMessageId, filePath);

      // Scroll to show new message
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (scrollController.hasClients) {
          scrollController.jumpTo(0);
        }
      });

      // Send in background
      unawaited(_sendVoiceInBackground(
        file: file,
        fileName: fileName,
        duration: duration,
        tempMessageId: tempMessageId,
      ));
    } catch (e) {
      if (!mounted) return;
      uploadProvider.removeUploadingMessageId(tempMessageId);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to send voice message')),
      );
    }
  }

  /// Send voice message in background
  Future<void> _sendVoiceInBackground({
    required File file,
    required String fileName,
    required Duration duration,
    required String tempMessageId,
  }) async {
    try {
      final bytes = await file.readAsBytes();

      // Cache the file
      if (attachmentCacheDirPath != null) {
        final cachePath = '$attachmentCacheDirPath/${tempMessageId}_$fileName';
        final cacheFile = File(cachePath);
        await cacheFile.writeAsBytes(bytes, flush: true);
        if (mounted) {
          updateCachedAttachmentPath(tempMessageId, cachePath);
        }
      }

      // Delete original recording file
      await file.delete();

      // Upload
      final realMessage = await ChatService.sendVoiceAttachment(
        fromId: currentUserId,
        toId: peerUserId,
        bytes: bytes,
        fileName: fileName,
        durationMs: duration.inMilliseconds,
      );

      if (realMessage.id.isEmpty) {
        throw Exception('Failed to send voice message');
      }

      // Reload messages to replace temp with real message
      await loadMessages(scrollToBottom: false);

      // Remove the temporary message now that real message is loaded
      if (mounted) {
        removeMessage(tempMessageId);
      }

      // Update cache path to use real message ID
      if (mounted) {
        uploadProvider.removeUploadingMessageId(tempMessageId);
        if (uploadProvider.cachedAttachmentPaths.containsKey(tempMessageId)) {
          final tempPath = uploadProvider.cachedAttachmentPaths[tempMessageId]!;
          uploadProvider.updateCachedAttachmentPath(realMessage.id, tempPath);
          uploadProvider.removeCachedAttachmentPath(tempMessageId);
        }
      }
    } catch (e) {
      if (!mounted) return;
      uploadProvider.removeUploadingMessageId(tempMessageId);
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
        recordingProvider.setPlayingAudioMessageId(null);
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
      recordingProvider.setPlayingAudioMessageId(message.id);
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
