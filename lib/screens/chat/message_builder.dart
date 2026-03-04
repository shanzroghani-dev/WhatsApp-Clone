import 'dart:io';

import 'package:flutter/material.dart';
import 'package:whatsapp_clone/chat/chat_service.dart';
import 'package:whatsapp_clone/core/design_tokens.dart';
import 'package:whatsapp_clone/models/message_model.dart';

/// Mixin for message content building and UI rendering
mixin MessageBuilder {
  /// State getters
  Duration get recordingDuration;
  String? get playingAudioMessageId;
  Set<String> get uploadingMessageIds;
  Set<String> get downloadingMessageIds;

  /// Context
  BuildContext get context;
  String get currentUserId;

  /// Callbacks for message actions
  Future<void> toggleAudioPlayback({
    required MessageModel message,
    required Map<String, dynamic> attachment,
  });

  Future<void> onMediaMessageTap({
    required MessageModel message,
    required Map<String, dynamic> attachment,
  });

  String? getCachedAttachmentPath(
    MessageModel message,
    Map<String, dynamic> attachment,
  );

  String? getCachedVideoThumbnailPath(MessageModel message);

  /// Format recording duration
  String formatRecordingDuration(Duration duration) {
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  /// Build waveform animation widget
  Widget buildRecordingWaveform(bool isDark) {
    final tick = recordingDuration.inMilliseconds ~/ 250;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(18, (index) {
        final phase = (tick + index) % 6;
        final height = 6.0 + (phase * 2.0);
        return AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          margin: const EdgeInsets.symmetric(horizontal: 1.5),
          width: 3,
          height: height,
          decoration: BoxDecoration(
            color: isDark
                ? AppColors.darkTextSecondary
                : AppColors.lightTextSecondary,
            borderRadius: BorderRadius.circular(2),
          ),
        );
      }),
    );
  }

  /// Build message content widget
  Widget buildMessageContent(MessageModel message, bool mine, bool isDark) {
    final attachment = _parseAttachment(message.text);
    if (attachment == null) {
      return Text(
        message.text,
        style: TextStyle(
          color: mine
              ? Colors.white
              : (isDark ? AppColors.darkText : AppColors.lightText),
          fontSize: 15,
          fontWeight: FontWeight.w500,
        ),
      );
    }

    final type = attachment['type'] as String?;
    if (type == 'audio') {
      return _buildAudioContent(message, mine, isDark, attachment);
    }

    if (type == 'image' || type == 'video') {
      return _buildMediaContent(message, mine, isDark, attachment);
    }

    return Text(
      'Attachment',
      style: TextStyle(
        color: mine
            ? Colors.white
            : (isDark ? AppColors.darkText : AppColors.lightText),
        fontSize: 15,
        fontWeight: FontWeight.w500,
      ),
    );
  }

  /// Build audio message content
  Widget _buildAudioContent(
    MessageModel message,
    bool mine,
    bool isDark,
    Map<String, dynamic> attachment,
  ) {
    final isDownloading = downloadingMessageIds.contains(message.id);
    final isUploading = uploadingMessageIds.contains(message.id);
    final durationMs = (attachment['durationMs'] as num?)?.toInt() ?? 0;
    final durationLabel = formatRecordingDuration(
      Duration(milliseconds: durationMs),
    );
    final isPlaying = playingAudioMessageId == message.id;
    final caption = attachment['caption'] as String?;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: mine
          ? CrossAxisAlignment.end
          : CrossAxisAlignment.start,
      children: [
        Container(
          constraints: const BoxConstraints(maxWidth: 280),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: mine
                ? Colors.white.withValues(alpha: 0.15)
                : (isDark
                      ? AppColors.darkSurfaceVariant
                      : AppColors.lightSurfaceVariant),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Stack(
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  GestureDetector(
                    onTap: isUploading || isDownloading
                        ? null
                        : () => toggleAudioPlayback(
                            message: message,
                            attachment: attachment,
                          ),
                    child: Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: mine
                            ? Colors.white.withValues(alpha: 0.18)
                            : (isDark
                                  ? AppColors.darkSurface
                                  : AppColors.lightSurface),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        isPlaying
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded,
                        size: 20,
                        color: mine
                            ? Colors.white
                            : (isDark
                                  ? AppColors.darkText
                                  : AppColors.lightText),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  buildRecordingWaveform(isDark),
                  const SizedBox(width: 8),
                  Text(
                    durationLabel,
                    style: TextStyle(
                      color: mine
                          ? Colors.white70
                          : (isDark
                                ? AppColors.darkTextSecondary
                                : AppColors.lightTextSecondary),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              if (isDownloading || isUploading)
                Positioned.fill(
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.32),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    alignment: Alignment.center,
                    child: const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.2,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        if (caption != null && caption.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            caption,
            style: TextStyle(
              color: mine
                  ? Colors.white
                  : (isDark ? AppColors.darkText : AppColors.lightText),
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ],
    );
  }

  /// Build media message content
  Widget _buildMediaContent(
    MessageModel message,
    bool mine,
    bool isDark,
    Map<String, dynamic> attachment,
  ) {
    final isVideo = (attachment['type'] as String?) == 'video';
    final name = attachment['name'] as String? ?? (isVideo ? 'Video' : 'Photo');
    final isDownloading = downloadingMessageIds.contains(message.id);
    final isUploading = uploadingMessageIds.contains(message.id);
    final cachedPath = getCachedAttachmentPath(message, attachment);
    final videoThumbnailPath = isVideo
        ? getCachedVideoThumbnailPath(message)
        : null;
    final caption = attachment['caption'] as String?;

    final Widget mediaCard = Stack(
      children: [
        if (!isVideo && cachedPath != null)
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.file(
              File(cachedPath),
              width: 220,
              height: 220,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Container(
                width: 220,
                height: 120,
                decoration: BoxDecoration(
                  color: mine
                      ? Colors.white.withValues(alpha: 0.18)
                      : (isDark
                            ? AppColors.darkSurface
                            : AppColors.lightSurface),
                  borderRadius: BorderRadius.circular(12),
                ),
                alignment: Alignment.center,
                child: Icon(
                  Icons.broken_image_outlined,
                  color: mine
                      ? Colors.white70
                      : (isDark
                            ? AppColors.darkTextSecondary
                            : AppColors.lightTextSecondary),
                ),
              ),
            ),
          )
        else if (isVideo &&
            videoThumbnailPath != null &&
            File(videoThumbnailPath).existsSync())
          SizedBox(
            width: 220,
            height: 220,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Image.file(
                    File(videoThumbnailPath),
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      color: mine
                          ? Colors.white.withValues(alpha: 0.18)
                          : (isDark
                                ? AppColors.darkSurface
                                : AppColors.lightSurface),
                      alignment: Alignment.center,
                      child: Icon(
                        Icons.videocam_rounded,
                        size: 36,
                        color: mine
                            ? Colors.white
                            : (isDark
                                  ? AppColors.darkText
                                  : AppColors.lightText),
                      ),
                    ),
                  ),
                  Center(
                    child: Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.6),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.play_arrow_rounded,
                        color: Colors.white,
                        size: 32,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          )
        else
          Container(
            width: 220,
            height: 120,
            decoration: BoxDecoration(
              color: mine
                  ? Colors.white.withValues(alpha: 0.18)
                  : (isDark ? AppColors.darkSurface : AppColors.lightSurface),
              borderRadius: BorderRadius.circular(12),
            ),
            alignment: Alignment.center,
            child: Icon(
              isVideo ? Icons.videocam_rounded : Icons.image_rounded,
              size: 36,
              color: mine
                  ? Colors.white
                  : (isDark ? AppColors.darkText : AppColors.lightText),
            ),
          ),
        if (isDownloading)
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.25),
                borderRadius: BorderRadius.circular(12),
              ),
              alignment: Alignment.center,
              child: const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2.4),
              ),
            ),
          ),
        if (isUploading)
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(12),
              ),
              alignment: Alignment.center,
              child: const Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.4,
                      color: Colors.white,
                    ),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Uploading...',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: mine
          ? CrossAxisAlignment.end
          : CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: () =>
              onMediaMessageTap(message: message, attachment: attachment),
          borderRadius: BorderRadius.circular(12),
          child: mediaCard,
        ),
        if (caption != null && caption.isNotEmpty) ...[
          const SizedBox(height: 6),
          Container(
            constraints: const BoxConstraints(maxWidth: 280),
            child: Text(
              caption,
              style: TextStyle(
                color: mine
                    ? Colors.white
                    : (isDark ? AppColors.darkText : AppColors.lightText),
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
        const SizedBox(height: 6),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isVideo ? Icons.movie_rounded : Icons.image_outlined,
              size: 14,
              color: mine
                  ? Colors.white70
                  : (isDark
                        ? AppColors.darkTextSecondary
                        : AppColors.lightTextSecondary),
            ),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: mine
                      ? Colors.white70
                      : (isDark
                            ? AppColors.darkTextSecondary
                            : AppColors.lightTextSecondary),
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            if (cachedPath != null) ...[
              const SizedBox(width: 6),
              Icon(
                Icons.offline_pin_rounded,
                size: 14,
                color: mine
                    ? Colors.white70
                    : (isDark
                          ? AppColors.darkTextSecondary
                          : AppColors.lightTextSecondary),
              ),
            ],
          ],
        ),
      ],
    );
  }

  /// Parse attachment from message text
  Map<String, dynamic>? _parseAttachment(String text) {
    if (!text.startsWith(ChatService.attachmentPrefix)) {
      return null;
    }
    try {
      final jsonStr = text.substring(ChatService.attachmentPrefix.length);
      // Simple JSON parsing - in real code should use proper JSON decoder
      return _parseJsonString(jsonStr);
    } catch (_) {
      return null;
    }
  }

  /// Simple JSON string parser - delegates to ChatService
  Map<String, dynamic>? _parseJsonString(String jsonStr) {
    if (!jsonStr.startsWith('{') || !jsonStr.endsWith('}')) return null;
    try {
      // Use ChatService's built-in parser
      return ChatService.parseAttachmentPayload(
        '${ChatService.attachmentPrefix}$jsonStr',
      );
    } catch (_) {
      return null;
    }
  }
}
