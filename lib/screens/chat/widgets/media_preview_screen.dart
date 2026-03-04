import 'dart:io';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:whatsapp_clone/core/design_tokens.dart';
import 'package:whatsapp_clone/screens/chat/helpers/chat_helpers.dart';

class MediaPreviewScreen extends StatefulWidget {
  final String filePath;
  final bool isVideo;
  final String title;

  const MediaPreviewScreen({
    required this.filePath,
    required this.isVideo,
    required this.title,
  });

  @override
  State<MediaPreviewScreen> createState() => _MediaPreviewScreenState();
}

class _MediaPreviewScreenState extends State<MediaPreviewScreen> {
  late VideoPlayerController _videoController;
  bool _isInitialized = false;
  bool _isePlaying = false;

  @override
  void initState() {
    super.initState();
    if (widget.isVideo) {
      _initializeVideoPlayer();
    }
  }

  Future<void> _initializeVideoPlayer() async {
    try {
      _videoController = VideoPlayerController.file(File(widget.filePath));
      await _videoController.initialize();
      setState(() {
        _isInitialized = true;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _isInitialized = false;
        });
      }
    }
  }

  @override
  void dispose() {
    if (widget.isVideo && _isInitialized) {
      _videoController.dispose();
    }
    super.dispose();
  }

  void _togglePlayPause() {
    setState(() {
      _isePlaying = !_isePlaying;
      if (_isePlaying) {
        _videoController.play();
      } else {
        _videoController.pause();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final file = File(widget.filePath);
    final fileExists = file.existsSync();

    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: !fileExists
              ? Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.error_rounded,
                      size: 72,
                      color: Colors.red.shade400,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Media file not found',
                      style: theme.textTheme.titleMedium,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'The media may have been deleted or is no longer available',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                )
              : widget.isVideo
                  ? !_isInitialized
                      ? Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            SizedBox(
                              width: 40,
                              height: 40,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'Loading video...',
                              style: theme.textTheme.bodyMedium,
                              textAlign: TextAlign.center,
                            ),
                          ],
                        )
                      : Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            AspectRatio(
                              aspectRatio: _videoController.value.aspectRatio,
                              child: Stack(
                                alignment: Alignment.center,
                                children: [
                                  VideoPlayer(_videoController),
                                  GestureDetector(
                                    onTap: _togglePlayPause,
                                    child: Container(
                                      decoration: BoxDecoration(
                                        color: Colors.black.withValues(alpha: _isePlaying ? 0.3 : 0.5),
                                        shape: BoxShape.circle,
                                      ),
                                      padding: const EdgeInsets.all(12),
                                      child: Icon(
                                        _isePlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                                        color: Colors.white,
                                        size: 48,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 16),
                            VideoProgressIndicator(
                              _videoController,
                              allowScrubbing: true,
                              padding: const EdgeInsets.symmetric(horizontal: 8),
                            ),
                            const SizedBox(height: 12),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  ChatHelpers.formatDuration(_videoController.value.position),
                                  style: theme.textTheme.labelMedium?.copyWith(
                                    color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                                  ),
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  '/',
                                  style: theme.textTheme.labelMedium?.copyWith(
                                    color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                                  ),
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  ChatHelpers.formatDuration(_videoController.value.duration),
                                  style: theme.textTheme.labelMedium?.copyWith(
                                    color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        )
                  : ClipRRect(
                      borderRadius: BorderRadius.circular(AppRadius.md),
                      child: Image.file(
                        file,
                        fit: BoxFit.contain,
                        errorBuilder: (_, error, __) => Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.broken_image_rounded,
                              size: 72,
                              color: Colors.red.shade400,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'Could not display image',
                              style: theme.textTheme.bodyMedium,
                            ),
                          ],
                        ),
                      ),
                    ),
        ),
      ),
    );
  }
}
