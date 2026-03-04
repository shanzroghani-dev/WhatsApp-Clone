import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:whatsapp_clone/chat/chat_service.dart';
import 'package:whatsapp_clone/models/message_model.dart';
import 'package:whatsapp_clone/providers/media_provider.dart';
import 'package:whatsapp_clone/providers/upload_provider.dart';
import 'package:whatsapp_clone/screens/chat/helpers/chat_helpers.dart';
import 'package:whatsapp_clone/screens/chat/widgets/media_preview_screen.dart';

/// Mixin for media attachment handling
mixin MediaHandler {
  /// Media selection state variables
  File? get selectedMediaFile;
  String? get selectedMediaType;
  Uint8List? get selectedVideoThumbnail;
  String? get attachmentCacheDirPath;
  Set<String> get uploadingMessageIds;
  Set<String> get downloadingMessageIds;
  Map<String, String> get cachedAttachmentPaths;
  Map<String, String> get videoThumbnailPaths;

  /// Image picker instance
  ImagePicker get imagePicker;

  /// Widget context
  BuildContext get context;

  /// Mounted check
  bool get mounted;

  /// Getters for dependent state
  String get currentUserId;
  String get peerUserId;

  /// Provider accessors
  MediaStateNotifier get mediaProvider =>
      Provider.of<MediaStateNotifier>(context, listen: false);

  UploadStateNotifier get uploadProvider =>
      Provider.of<UploadStateNotifier>(context, listen: false);

  /// State update method
  void setState(VoidCallback fn);

  /// Setter methods (implemented by host class)
  void setSelectedMediaFile(File? file);
  void setSelectedMediaType(String? type);
  void setSelectedVideoThumbnail(Uint8List? thumbnail);
  void clearSelectedMedia();
  void addUploadingMessageId(String id);
  void removeUploadingMessageId(String id);
  void insertMessage(MessageModel message);
  void updateCachedAttachmentPath(String key, String path);
  void updateVideoThumbnailPath(String key, String path);
  void removeVideoThumbnailPath(String key);
  void removeCachedAttachmentPath(String key);
  void removeMessage(String id);
  void incrementVisibleCount();
  void decrementVisibleCount();

  /// Initialize attachment cache directory
  Future<void> initializeAttachmentCacheDir();

  /// Load messages
  Future<void> loadMessages({bool scrollToBottom = false});

  /// Scroll behavior
  ScrollController get scrollController;

  /// Message controller
  TextEditingController get messageController;

  /// Send selected media
  Future<void> sendSelectedMedia() async {
    if (selectedMediaFile == null || selectedMediaType == null) return;

    final file = selectedMediaFile!;
    final mediaType = selectedMediaType!;
    final isVideo = mediaType == 'video';
    final caption = messageController.text.trim();
    final fileName = file.path.split('/').last;
    final tempMessageId = 'uploading_${DateTime.now().millisecondsSinceEpoch}';

    // Capture thumbnail before clearing state
    final thumbnailBytes = selectedVideoThumbnail;

    try {
      final tempPayload = <String, dynamic>{
        'type': mediaType,
        'url': '',
        'name': fileName,
        'storagePath': '',
        'sizeBytes': 0,
        if (caption.isNotEmpty) 'caption': caption,
      };

      final tempMessage = MessageModel(
        id: tempMessageId,
        fromId: currentUserId,
        toId: peerUserId,
        text: '${ChatService.attachmentPrefix}${jsonEncode(tempPayload)}',
        timestamp: DateTime.now().millisecondsSinceEpoch,
        delivered: true,
      );

      String? previewPath = file.path;
      String? thumbnailPath;

      if (attachmentCacheDirPath == null) {
        unawaited(initializeAttachmentCacheDir());
      }

      if (attachmentCacheDirPath != null && isVideo && thumbnailBytes != null) {
        thumbnailPath =
            '$attachmentCacheDirPath/${tempMessageId}_thumbnail.jpg';
      }

      uploadProvider.addUploadingMessageId(tempMessageId);
      insertMessage(tempMessage);
      incrementVisibleCount();
      uploadProvider.updateCachedAttachmentPath(tempMessageId, previewPath);
      mediaProvider.clear();
      messageController.clear();

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (scrollController.hasClients) {
          scrollController.jumpTo(0);
        }
      });

      unawaited(
        uploadMediaInBackground(
          file: file,
          tempMessageId: tempMessageId,
          mediaType: mediaType,
          fileName: fileName,
          caption: caption,
          isVideo: isVideo,
          thumbnailBytes: thumbnailBytes,
          thumbnailPath: thumbnailPath,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Failed to prepare media')));
    }
  }

  /// Upload media in background
  Future<void> uploadMediaInBackground({
    required File file,
    required String tempMessageId,
    required String mediaType,
    required String fileName,
    required String caption,
    required bool isVideo,
    Uint8List? thumbnailBytes,
    String? thumbnailPath,
  }) async {
    try {
      // Write thumbnail to disk if we have it
      if (isVideo && thumbnailBytes != null && thumbnailPath != null) {
        final thumbnailFile = File(thumbnailPath);
        await thumbnailFile.writeAsBytes(thumbnailBytes, flush: true);
        if (mounted) {
          uploadProvider.updateVideoThumbnailPath(tempMessageId, thumbnailPath);
        }
      }

      // Read the full file for upload
      final bytes = await file.readAsBytes();

      // Copy to permanent cache location
      if (attachmentCacheDirPath != null) {
        final safeName = ChatHelpers.sanitizedFileName(fileName);
        final cachePath = '$attachmentCacheDirPath/${tempMessageId}_$safeName';
        final cacheFile = File(cachePath);
        await cacheFile.writeAsBytes(bytes, flush: true);
        if (mounted) {
          uploadProvider.updateCachedAttachmentPath(tempMessageId, cachePath);
        }
      }

      // Upload
      final realMessage = await ChatService.sendMediaAttachment(
        fromId: currentUserId,
        toId: peerUserId,
        mediaType: mediaType,
        bytes: bytes,
        fileName: fileName,
        contentType: isVideo ? 'video/mp4' : 'image/jpeg',
        caption: caption.isEmpty ? null : caption,
      );

      // Load updated messages to replace temp with real message
      await loadMessages(scrollToBottom: false);

      // Rename thumbnail file to match real message ID
      if (videoThumbnailPaths.containsKey(tempMessageId)) {
        final oldThumbnailPath = videoThumbnailPaths[tempMessageId]!;
        final oldFile = File(oldThumbnailPath);
        if (await oldFile.exists()) {
          final newThumbnailPath = oldThumbnailPath.replaceFirst(
            '${tempMessageId}_thumbnail.jpg',
            '${realMessage.id}_thumbnail.jpg',
          );
          try {
            await oldFile.rename(newThumbnailPath);
            uploadProvider.updateVideoThumbnailPath(
              realMessage.id,
              newThumbnailPath,
            );
            uploadProvider.removeVideoThumbnailPath(tempMessageId);
          } catch (e) {
            uploadProvider.updateVideoThumbnailPath(
              realMessage.id,
              oldThumbnailPath,
            );
            uploadProvider.removeVideoThumbnailPath(tempMessageId);
          }
        }
      }

      if (mounted) {
        uploadProvider.removeUploadingMessageId(tempMessageId);
        if (uploadProvider.cachedAttachmentPaths.containsKey(tempMessageId)) {
          final tempPath =
              uploadProvider.cachedAttachmentPaths[tempMessageId]!;
          uploadProvider.updateCachedAttachmentPath(realMessage.id, tempPath);
          uploadProvider.removeCachedAttachmentPath(tempMessageId);
        }
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Failed to send media')));
      removeMessage(tempMessageId);
      uploadProvider.removeUploadingMessageId(tempMessageId);
    }
  }

  /// Cancel selected media
  void cancelSelectedMedia() {
    mediaProvider.clear();
  }

  /// Pick and send image attachment
  Future<void> pickAndSendImageAttachment() async {
    await pickAndSendMediaAttachment(isVideo: false);
  }

  /// Pick and send video attachment
  Future<void> pickAndSendVideoAttachment() async {
    await pickAndSendMediaAttachment(isVideo: true);
  }

  /// Pick and send media attachment
  Future<void> pickAndSendMediaAttachment({required bool isVideo}) async {
    try {
      print('🎬 Starting media picker for ${isVideo ? 'video' : 'image'}');
      final XFile? picked = isVideo
          ? await imagePicker.pickVideo(source: ImageSource.gallery)
          : await imagePicker.pickImage(
              source: ImageSource.gallery,
              imageQuality: 85,
            );

      if (picked == null) {
        print('❌ User cancelled media selection');
        return;
      }

      print('✅ File picked: ${picked.path}');

      final fileSize = await picked.length();
      if (fileSize > ChatService.maxAttachmentBytes) {
        if (!mounted) return;
        print('❌ File too large: $fileSize bytes');
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Attachment must be 10MB or smaller')),
        );
        return;
      }

      Uint8List? videoThumbnail;
      if (isVideo) {
        print('🎥 Generating video thumbnail...');
        videoThumbnail = await ChatHelpers.generateVideoThumbnail(picked.path);
      }

      if (!mounted) return;

      mediaProvider.setSelectedMediaFile(File(picked.path));
      mediaProvider.setSelectedMediaType(isVideo ? 'video' : 'image');
      mediaProvider.setSelectedVideoThumbnail(videoThumbnail);
      print('✅ Media selected and state updated');
    } catch (e) {
      if (!mounted) return;
      print('❌ Media selection error: $e');
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  /// Show attachment options
  Future<void> showAttachmentOptions() async {
    await showModalBottomSheet<void>(
      context: context,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.image_rounded),
                title: const Text('Photo'),
                onTap: () async {
                  Navigator.of(context).pop();
                  await pickAndSendImageAttachment();
                },
              ),
              ListTile(
                leading: const Icon(Icons.videocam_rounded),
                title: const Text('Video'),
                onTap: () async {
                  Navigator.of(context).pop();
                  await pickAndSendVideoAttachment();
                },
              ),
            ],
          ),
        );
      },
    );
  }

  /// Download attachment
  Future<String?> downloadAttachment({
    required MessageModel message,
    required Map<String, dynamic> attachment,
  }) async {
    if (downloadingMessageIds.contains(message.id)) return null;
    setState(() {
      (this as dynamic)._downloadingMessageIds.add(message.id);
    });

    try {
      final bytes = await ChatService.downloadAttachmentAndDeleteFromStorage(
        attachment,
        deleteAfterDownload: message.fromId != currentUserId,
      );
      final fileName = (attachment['name'] as String?) ?? 'attachment.bin';
      final mediaType = (attachment['type'] as String?) ?? 'file';
      if (attachmentCacheDirPath == null) {
        await initializeAttachmentCacheDir();
      }
      final safeName = ChatHelpers.sanitizedFileName(fileName);
      final baseDir = attachmentCacheDirPath;
      if (baseDir == null) {
        throw Exception('Attachment cache not available');
      }
      final savePath = '$baseDir/${message.id}_$safeName';
      final file = File(savePath);
      await file.writeAsBytes(bytes, flush: true);

      if (mediaType == 'video') {
        final thumbnailData = await ChatHelpers.generateVideoThumbnail(
          savePath,
        );
        if (thumbnailData != null) {
          final thumbnailPath = '$baseDir/${message.id}_thumbnail.jpg';
          final thumbnailFile = File(thumbnailPath);
          await thumbnailFile.writeAsBytes(thumbnailData, flush: true);
          if (mounted) {
            setState(() {
              (this as dynamic)._videoThumbnailPaths[message.id] =
                  thumbnailPath;
            });
          }
        }
      }

      if (!mounted) return null;
      setState(() {
        (this as dynamic)._cachedAttachmentPaths[message.id] = savePath;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Downloaded: $fileName')));
      return savePath;
    } catch (_) {
      if (!mounted) return null;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to download attachment')),
      );
      return null;
    } finally {
      if (mounted) {
        setState(() {
          (this as dynamic)._downloadingMessageIds.remove(message.id);
        });
      }
    }
  }

  /// Handle media message tap
  Future<void> onMediaMessageTap({
    required MessageModel message,
    required Map<String, dynamic> attachment,
  }) async {
    if (downloadingMessageIds.contains(message.id)) return;
    final isVideo = (attachment['type'] as String?) == 'video';
    final displayName =
        (attachment['name'] as String?) ?? (isVideo ? 'Video' : 'Photo');
    final cached = getCachedAttachmentPath(message, attachment);
    if (cached != null) {
      openMediaPreview(filePath: cached, isVideo: isVideo, title: displayName);
      return;
    }
    final downloadedPath = await downloadAttachment(
      message: message,
      attachment: attachment,
    );
    if (!mounted) return;
    if (downloadedPath != null) {
      openMediaPreview(
        filePath: downloadedPath,
        isVideo: isVideo,
        title: displayName,
      );
    }
  }

  /// Open media preview
  void openMediaPreview({
    required String filePath,
    required bool isVideo,
    required String title,
  }) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MediaPreviewScreen(
          filePath: filePath,
          isVideo: isVideo,
          title: title,
        ),
      ),
    );
  }

  /// Get cached attachment path
  String? getCachedAttachmentPath(
    MessageModel message,
    Map<String, dynamic> attachment,
  ) {
    final inMemory = cachedAttachmentPaths[message.id];
    if (inMemory != null && File(inMemory).existsSync()) {
      return inMemory;
    }

    if (attachmentCacheDirPath == null) return null;
    final fileName = ChatHelpers.sanitizedFileName(
      (attachment['name'] as String?) ?? 'attachment.bin',
    );
    final candidate = '$attachmentCacheDirPath/${message.id}_$fileName';
    if (File(candidate).existsSync()) {
      return candidate;
    }

    if (message.fromId == currentUserId) {
      try {
        final cacheDir = Directory(attachmentCacheDirPath!);
        if (cacheDir.existsSync()) {
          final files = cacheDir.listSync().whereType<File>();
          for (final file in files) {
            if (file.path.endsWith(fileName)) {
              return file.path;
            }
          }
        }
      } catch (_) {}
    }
    return null;
  }

  /// Get cached video thumbnail path
  String? getCachedVideoThumbnailPath(MessageModel message) {
    if (videoThumbnailPaths.containsKey(message.id)) {
      return videoThumbnailPaths[message.id];
    }

    if (attachmentCacheDirPath != null) {
      final predictedPath =
          '$attachmentCacheDirPath/${message.id}_thumbnail.jpg';
      if (File(predictedPath).existsSync()) {
        return predictedPath;
      }
    }

    return null;
  }
}
