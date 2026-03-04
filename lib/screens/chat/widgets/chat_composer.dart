import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:whatsapp_clone/core/design_tokens.dart';

class ChatComposer extends StatelessWidget {
  final bool isDark;
  final bool isRecordingVoice;
  final Duration recordingDuration;
  final double recordingSlideOffset;
  final Widget recordingWaveform;
  final File? selectedMediaFile;
  final String? selectedMediaType;
  final Uint8List? selectedVideoThumbnail;
  final TextEditingController messageController;
  final VoidCallback onAttachmentTap;
  final VoidCallback onSendTap;
  final VoidCallback onCancelSelectedMedia;
  final void Function(String) onSubmitted;
  final GestureLongPressStartCallback onVoiceLongPressStart;
  final GestureLongPressMoveUpdateCallback onVoiceLongPressMoveUpdate;
  final GestureLongPressEndCallback onVoiceLongPressEnd;

  const ChatComposer({
    super.key,
    required this.isDark,
    required this.isRecordingVoice,
    required this.recordingDuration,
    required this.recordingSlideOffset,
    required this.recordingWaveform,
    required this.selectedMediaFile,
    required this.selectedMediaType,
    required this.selectedVideoThumbnail,
    required this.messageController,
    required this.onAttachmentTap,
    required this.onSendTap,
    required this.onCancelSelectedMedia,
    required this.onSubmitted,
    required this.onVoiceLongPressStart,
    required this.onVoiceLongPressMoveUpdate,
    required this.onVoiceLongPressEnd,
  });

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final canSendText =
        messageController.text.trim().isNotEmpty || selectedMediaFile != null;

    return SafeArea(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 8,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isRecordingVoice)
              Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: isDark
                      ? AppColors.darkSurface
                      : AppColors.lightSurface,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  border: Border.all(
                    color: AppColors.error.withValues(alpha: 0.35),
                    width: 1,
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.mic_rounded,
                      color: AppColors.error,
                      size: 18,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Recording... ${_formatDuration(recordingDuration)}',
                      style: TextStyle(
                        color: isDark
                            ? AppColors.darkText
                            : AppColors.lightText,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(width: 10),
                    recordingWaveform,
                    const Spacer(),
                    Transform.translate(
                      offset: Offset(recordingSlideOffset, 0),
                      child: Text(
                        '← Slide to cancel',
                        style: TextStyle(
                          color: isDark
                              ? AppColors.darkTextSecondary
                              : AppColors.lightTextSecondary,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            if (selectedMediaFile != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(
                  mainAxisSize: MainAxisSize.max,
                  children: [
                    Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        color: Colors.black12,
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child:
                            selectedMediaType == 'video' &&
                                selectedVideoThumbnail != null
                            ? Stack(
                                fit: StackFit.expand,
                                children: [
                                  Image.memory(
                                    selectedVideoThumbnail!,
                                    fit: BoxFit.cover,
                                  ),
                                  Center(
                                    child: Container(
                                      padding: const EdgeInsets.all(8),
                                      decoration: const BoxDecoration(
                                        color: Colors.black45,
                                        shape: BoxShape.circle,
                                      ),
                                      child: const Icon(
                                        Icons.play_arrow,
                                        color: Colors.white,
                                        size: 24,
                                      ),
                                    ),
                                  ),
                                ],
                              )
                            : Image.file(selectedMediaFile!, fit: BoxFit.cover),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            selectedMediaType == 'video' ? 'Video' : 'Photo',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                              color: isDark
                                  ? AppColors.darkText
                                  : AppColors.lightText,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Add caption below and send',
                            style: TextStyle(
                              fontSize: 12,
                              color: isDark
                                  ? AppColors.darkTextSecondary
                                  : AppColors.lightTextSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: onCancelSelectedMedia,
                      icon: const Icon(Icons.close, size: 20),
                      tooltip: 'Remove',
                      constraints: const BoxConstraints(),
                      padding: EdgeInsets.zero,
                    ),
                  ],
                ),
              ),
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: isDark
                        ? AppColors.darkSurface
                        : AppColors.lightSurface,
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                  ),
                  child: IconButton(
                    onPressed: onAttachmentTap,
                    icon: const Icon(Icons.attach_file_rounded, size: 20),
                    color: isDark
                        ? AppColors.darkTextSecondary
                        : AppColors.lightTextSecondary,
                    padding: EdgeInsets.zero,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: isDark
                          ? AppColors.darkSurface
                          : AppColors.lightSurface,
                      borderRadius: BorderRadius.circular(AppRadius.md),
                      border: Border.all(
                        color: isDark
                            ? Colors.white.withValues(alpha: 0.08)
                            : Colors.black.withValues(alpha: 0.08),
                        width: 1,
                      ),
                    ),
                    child: TextField(
                      controller: messageController,
                      decoration: InputDecoration(
                        hintText: selectedMediaFile != null
                            ? 'Add caption...'
                            : 'Type a message...',
                        hintStyle: TextStyle(
                          color: isDark
                              ? AppColors.darkTextSecondary
                              : AppColors.lightTextSecondary,
                        ),
                        filled: false,
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                      ),
                      maxLines: 4,
                      minLines: 1,
                      style: TextStyle(
                        color: isDark
                            ? AppColors.darkText
                            : AppColors.lightText,
                      ),
                      textInputAction: TextInputAction.send,
                      onSubmitted: onSubmitted,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    gradient: isRecordingVoice
                        ? const LinearGradient(
                            colors: [
                              AppColors.lightSurfaceVariant,
                              AppColors.lightSurfaceVariant,
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          )
                        : AppColors.primaryGradient,
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    boxShadow: [
                      AppShadows.coloredShadow(
                        isRecordingVoice ? AppColors.error : AppColors.accent,
                      ),
                    ],
                  ),
                  child: canSendText
                      ? IconButton(
                          onPressed: onSendTap,
                          icon: const Icon(
                            Icons.send_rounded,
                            color: Colors.white,
                            size: 20,
                          ),
                          tooltip: 'Send',
                        )
                      : GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onLongPressStart: onVoiceLongPressStart,
                          onLongPressMoveUpdate: onVoiceLongPressMoveUpdate,
                          onLongPressEnd: onVoiceLongPressEnd,
                          child: Center(
                            child: Icon(
                              Icons.mic_rounded,
                              color: isRecordingVoice
                                  ? AppColors.error
                                  : Colors.white,
                              size: 22,
                            ),
                          ),
                        ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
