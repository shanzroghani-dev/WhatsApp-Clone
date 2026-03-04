import 'dart:io';

import 'package:flutter/material.dart';
import 'package:whatsapp_clone/chat/chat_service.dart';
import 'package:whatsapp_clone/core/design_tokens.dart';
import 'package:whatsapp_clone/models/message_model.dart';

class MessageBubble extends StatelessWidget {
  final MessageModel message;
  final bool mine;
  final bool isDark;
  final Set<String> downloadingMessageIds;
  final Map<String, String> cachedAttachmentPaths;
  final Map<String, String> videoThumbnailPaths;
  final VoidCallback Function(Map<String, dynamic> attachment) onMediaTap;

  const MessageBubble({
    required this.message,
    required this.mine,
    required this.isDark,
    required this.downloadingMessageIds,
    required this.cachedAttachmentPaths,
    required this.videoThumbnailPaths,
    required this.onMediaTap,
  });

  @override
  Widget build(BuildContext context) {
    final attachment = ChatService.parseAttachmentPayload(message.text);
    if (attachment == null) {
      return _buildTextMessage();
    }

    final type = attachment['type'] as String?;
    if (type == 'image' || type == 'video') {
      return _buildMediaMessage(attachment);
    }

    return _buildTextMessage();
  }

  Widget _buildTextMessage() {
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

  Widget _buildMediaMessage(Map<String, dynamic> attachment) {
    final isVideo = (attachment['type'] as String?) == 'video';
    final name = attachment['name'] as String? ?? (isVideo ? 'Video' : 'Photo');
    final isDownloading = downloadingMessageIds.contains(message.id);
    final cachedPath = _getCachedAttachmentPath(attachment);
    final videoThumbnailPath = isVideo ? videoThumbnailPaths[message.id] : null;

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
              errorBuilder: (_, __, ___) => _buildPlaceholder(isVideo),
            ),
          )
        else if (isVideo &&
            videoThumbnailPath != null &&
            File(videoThumbnailPath).existsSync())
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Stack(
              fit: StackFit.expand,
              children: [
                Image.file(
                  File(videoThumbnailPath),
                  width: 220,
                  height: 220,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => _buildPlaceholder(isVideo),
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
          )
        else
          _buildPlaceholder(isVideo),
        if (isDownloading)
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.25),
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
      ],
    );

    return Column(
      crossAxisAlignment: mine
          ? CrossAxisAlignment.end
          : CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: () => onMediaTap(attachment),
          borderRadius: BorderRadius.circular(12),
          child: mediaCard,
        ),
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

  Widget _buildPlaceholder(bool isVideo) {
    return Container(
      width: 220,
      height: 120,
      decoration: BoxDecoration(
        color: mine
            ? Colors.white.withOpacity(0.18)
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
    );
  }

  String? _getCachedAttachmentPath(Map<String, dynamic> attachment) {
    final inMemory = cachedAttachmentPaths[message.id];
    if (inMemory != null && File(inMemory).existsSync()) {
      return inMemory;
    }
    return null;
  }
}
