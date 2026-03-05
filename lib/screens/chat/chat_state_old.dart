import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:whatsapp_clone/chat/chat_service.dart';
import 'package:whatsapp_clone/core/design_tokens.dart';
import 'package:whatsapp_clone/models/message_model.dart';
import 'package:whatsapp_clone/utils/date_time_utils.dart';
import 'package:whatsapp_clone/screens/chat/chat_screen.dart';
import 'package:whatsapp_clone/screens/chat/helpers/chat_helpers.dart';
import 'package:whatsapp_clone/screens/chat/widgets/chat_composer.dart';
import 'package:whatsapp_clone/screens/chat/widgets/media_preview_screen.dart';

class ChatScreenState extends State<ChatScreen> {
  final _messageController = TextEditingController();
  final _scrollController = ScrollController();
  final _imagePicker = ImagePicker();
  final AudioRecorder _audioRecorder = AudioRecorder();
  final AudioPlayer _audioPlayer = AudioPlayer();
  List<MessageModel> _messages = [];
  StreamSubscription<MessageModel>? _incomingSubscription;
  static const int _pageSize = 30;
  int _visibleCount = 0;
  bool _isLoadingMore = false;
  bool _hasMoreMessages = false;
  final Set<String> _uploadingMessageIds = <String>{};
  final Set<String> _downloadingMessageIds = <String>{};
  final Map<String, String> _cachedAttachmentPaths = <String, String>{};
  final Map<String, String> _videoThumbnailPaths = <String, String>{};
  String? _attachmentCacheDirPath;

  // Selected media before sending
  File? _selectedMediaFile;
  String? _selectedMediaType; // 'image' or 'video'
  Uint8List? _selectedVideoThumbnail;
  bool _isRecordingVoice = false;
  Duration _recordingDuration = Duration.zero;
  Timer? _recordingTimer;
  String? _playingAudioMessageId;
  double _recordingSlideOffset = 0;
  bool _recordingCancelTriggered = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _messageController.addListener(_onComposerChanged);
    _audioPlayer.onPlayerComplete.listen((_) {
      if (!mounted) return;
      setState(() {
        _playingAudioMessageId = null;
      });
    });
    _initializeAttachmentCacheDir();
    _loadMessages(scrollToBottom: true);
    _subscribeToIncomingMessages();
  }

  Future<void> _initializeAttachmentCacheDir() async {
    final docsDir = await getApplicationDocumentsDirectory();
    final cacheDir = Directory('${docsDir.path}/chat_media_cache');
    if (!await cacheDir.exists()) {
      await cacheDir.create(recursive: true);
    }
    if (!mounted) return;
    setState(() {
      _attachmentCacheDirPath = cacheDir.path;
    });
  }

  @override
  void dispose() {
    _recordingTimer?.cancel();
    unawaited(_audioRecorder.dispose());
    unawaited(_audioPlayer.dispose());
    _incomingSubscription?.cancel();
    _messageController.removeListener(_onComposerChanged);
    _messageController.dispose();
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onComposerChanged() {
    if (!mounted) return;
    setState(() {});
  }

  void _onScroll() {
    if (!_scrollController.hasClients || _isLoadingMore || !_hasMoreMessages) {
      return;
    }
    final position = _scrollController.position;
    const threshold = 160.0;
    if (position.pixels >= position.maxScrollExtent - threshold) {
      _loadMoreMessages();
    }
  }

  void _subscribeToIncomingMessages() {
    _incomingSubscription ??=
        ChatService.streamMessagesBetween(
          widget.peer.uid,
          widget.currentUser.uid,
        ).listen((_) {
          if (!mounted) return;
          _loadMessages();
        });
  }

  Future<void> _loadMessages({bool scrollToBottom = false}) async {
    final messages = await ChatService.getMessagesBetween(
      widget.currentUser.uid,
      widget.peer.uid,
    );
    if (!mounted) return;

    final previousVisibleCount = _visibleCount;
    setState(() {
      _messages = messages;
      if (previousVisibleCount == 0) {
        _visibleCount = messages.length < _pageSize
            ? messages.length
            : _pageSize;
      } else {
        _visibleCount = previousVisibleCount.clamp(0, messages.length);
      }
      _hasMoreMessages = _visibleCount < _messages.length;
    });

    if (scrollToBottom) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          _scrollController.jumpTo(0);
        }
      });
    }
  }

  void _loadMoreMessages() {
    if (_isLoadingMore || !_hasMoreMessages) return;

    final hasClients = _scrollController.hasClients;
    final previousPixels = hasClients ? _scrollController.position.pixels : 0.0;
    final previousMaxExtent = hasClients
        ? _scrollController.position.maxScrollExtent
        : 0.0;

    setState(() {
      _isLoadingMore = true;
    });

    final nextVisibleCount = (_visibleCount + _pageSize).clamp(
      0,
      _messages.length,
    );

    setState(() {
      _visibleCount = nextVisibleCount;
      _hasMoreMessages = _visibleCount < _messages.length;
      _isLoadingMore = false;
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      final newMaxExtent = _scrollController.position.maxScrollExtent;
      final extentDelta = newMaxExtent - previousMaxExtent;
      final targetOffset = (previousPixels + extentDelta).clamp(
        0.0,
        newMaxExtent,
      );
      _scrollController.jumpTo(targetOffset);
    });
  }

  List<MessageModel> _visibleMessages() {
    if (_messages.isEmpty || _visibleCount == 0) {
      return [];
    }
    final startIndex = _messages.length - _visibleCount;
    return _messages.sublist(startIndex);
  }

  void _sendMessage() {
    // Send media if selected
    if (_selectedMediaFile != null && _selectedMediaType != null) {
      // Fire and forget - don't await
      unawaited(_sendSelectedMedia());
      return;
    }

    // Send text message
    final text = _messageController.text.trim();
    if (text.isEmpty) return;

    final tempMessageId = 'temp_${DateTime.now().millisecondsSinceEpoch}';

    // Create optimistic message to show immediately
    final tempMessage = MessageModel(
      id: tempMessageId,
      fromId: widget.currentUser.uid,
      toId: widget.peer.uid,
      text: text,
      timestamp: DateTime.now().millisecondsSinceEpoch,
      delivered: false, // Will be marked delivered when confirmed
    );

    // Show message immediately
    setState(() {
      _messages.insert(0, tempMessage);
      _visibleCount = (_visibleCount + 1).clamp(0, _messages.length);
      _messageController.clear();
    });

    // Scroll to show new message
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(0);
      }
    });

    // Send in background (don't wait)
    unawaited(
      _sendTextMessageInBackground(text: text, tempMessageId: tempMessageId),
    );
  }

  Future<void> _sendTextMessageInBackground({
    required String text,
    required String tempMessageId,
  }) async {
    try {
      await ChatService.sendMessage(
        fromId: widget.currentUser.uid,
        toId: widget.peer.uid,
        text: text,
      );

      // Reload messages to replace temp with real message
      await _loadMessages(scrollToBottom: false);

      // Remove temp message from UI (real one will be in the loaded messages)
      if (mounted) {
        setState(() {
          _messages.removeWhere((m) => m.id == tempMessageId);
          _visibleCount = (_visibleCount - 1).clamp(0, _messages.length);
        });
      }
    } catch (e) {
      // On error, remove the temp message
      if (mounted) {
        setState(() {
          _messages.removeWhere((m) => m.id == tempMessageId);
          _visibleCount = (_visibleCount - 1).clamp(0, _messages.length);
        });
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Failed to send message')));
      }
    }
  }

  String _formatRecordingDuration(Duration duration) {
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  Future<void> _startVoiceRecording() async {
    if (_isRecordingVoice) return;

    try {
      final hasPermission = await _audioRecorder.hasPermission();
      if (!hasPermission) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Microphone permission is required')),
        );
        return;
      }

      if (_attachmentCacheDirPath == null) {
        await _initializeAttachmentCacheDir();
      }

      final baseDir = _attachmentCacheDirPath;
      if (baseDir == null) {
        throw Exception('Cache directory unavailable');
      }

      final filePath =
          '$baseDir/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
      await _audioRecorder.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          bitRate: 128000,
          sampleRate: 44100,
        ),
        path: filePath,
      );

      _recordingTimer?.cancel();
      _recordingTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted || !_isRecordingVoice) return;
        setState(() {
          _recordingDuration = Duration(
            seconds: _recordingDuration.inSeconds + 1,
          );
        });
      });

      if (!mounted) return;
      setState(() {
        _isRecordingVoice = true;
        _recordingDuration = Duration.zero;
      });
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not start recording')),
      );
    }
  }

  Future<void> _cancelVoiceRecording() async {
    if (!_isRecordingVoice) return;

    _recordingTimer?.cancel();
    final path = await _audioRecorder.stop();
    if (path != null) {
      final file = File(path);
      if (await file.exists()) {
        await file.delete();
      }
    }

    if (!mounted) return;
    setState(() {
      _isRecordingVoice = false;
      _recordingDuration = Duration.zero;
      _recordingSlideOffset = 0;
      _recordingCancelTriggered = false;
    });
  }

  Future<void> _stopAndSendVoiceRecording() async {
    if (!_isRecordingVoice) return;

    _recordingTimer?.cancel();
    final path = await _audioRecorder.stop();
    final duration = _recordingDuration;

    if (!mounted) return;
    setState(() {
      _isRecordingVoice = false;
      _recordingDuration = Duration.zero;
      _recordingSlideOffset = 0;
      _recordingCancelTriggered = false;
    });

    if (path == null || duration.inSeconds <= 0) {
      return;
    }

    unawaited(_sendVoiceMessage(filePath: path, duration: duration));
  }

  void _onVoiceLongPressStart(LongPressStartDetails _) {
    _recordingCancelTriggered = false;
    _recordingSlideOffset = 0;
    unawaited(_startVoiceRecording());
  }

  void _onVoiceLongPressMove(LongPressMoveUpdateDetails details) {
    if (!_isRecordingVoice || _recordingCancelTriggered) return;
    final dx = details.offsetFromOrigin.dx;
    final clamped = dx < 0 ? dx.clamp(-140.0, 0.0) : 0.0;
    if (mounted) {
      setState(() {
        _recordingSlideOffset = clamped;
      });
    }

    if (dx <= -100) {
      _recordingCancelTriggered = true;
      unawaited(_cancelVoiceRecording());
    }
  }

  void _onVoiceLongPressEnd(LongPressEndDetails _) {
    if (!_isRecordingVoice) return;
    if (_recordingCancelTriggered) return;
    unawaited(_stopAndSendVoiceRecording());
  }

  Future<void> _sendVoiceMessage({
    required String filePath,
    required Duration duration,
  }) async {
    final file = File(filePath);
    if (!await file.exists()) return;

    final fileName = file.path.split('/').last;
    final tempMessageId = 'uploading_${DateTime.now().millisecondsSinceEpoch}';

    try {
      final tempPayload = jsonEncode({
        'type': 'audio',
        'url': '',
        'name': fileName,
        'storagePath': '',
        'sizeBytes': await file.length(),
        'durationMs': duration.inMilliseconds,
      });

      final tempMessage = MessageModel(
        id: tempMessageId,
        fromId: widget.currentUser.uid,
        toId: widget.peer.uid,
        text: '${ChatService.attachmentPrefix}$tempPayload',
        timestamp: DateTime.now().millisecondsSinceEpoch,
        delivered: true,
      );

      setState(() {
        _uploadingMessageIds.add(tempMessageId);
        _messages.insert(0, tempMessage);
        _visibleCount = (_visibleCount + 1).clamp(0, _messages.length);
        _cachedAttachmentPaths[tempMessageId] = filePath;
      });

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          _scrollController.jumpTo(0);
        }
      });

      unawaited(
        _uploadVoiceInBackground(
          file: file,
          tempMessageId: tempMessageId,
          durationMs: duration.inMilliseconds,
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to prepare voice message')),
      );
    }
  }

  Future<void> _uploadVoiceInBackground({
    required File file,
    required String tempMessageId,
    required int durationMs,
  }) async {
    try {
      final bytes = await file.readAsBytes();
      final fileName = file.path.split('/').last;

      if (_attachmentCacheDirPath != null) {
        final safeName = ChatHelpers.sanitizedFileName(fileName);
        final cachePath = '$_attachmentCacheDirPath/${tempMessageId}_$safeName';
        final cacheFile = File(cachePath);
        await cacheFile.writeAsBytes(bytes, flush: true);
        if (mounted) {
          setState(() {
            _cachedAttachmentPaths[tempMessageId] = cachePath;
          });
        }
      }

      final realMessage = await ChatService.sendVoiceAttachment(
        fromId: widget.currentUser.uid,
        toId: widget.peer.uid,
        bytes: bytes,
        fileName: fileName,
        durationMs: durationMs,
      );

      await _loadMessages(scrollToBottom: false);

      if (mounted) {
        setState(() {
          _uploadingMessageIds.remove(tempMessageId);
          if (_cachedAttachmentPaths.containsKey(tempMessageId)) {
            final tempPath = _cachedAttachmentPaths[tempMessageId]!;
            _cachedAttachmentPaths[realMessage.id] = tempPath;
            _cachedAttachmentPaths.remove(tempMessageId);
          }
        });
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to send voice message')),
      );
      setState(() {
        _messages.removeWhere((m) => m.id == tempMessageId);
        _uploadingMessageIds.remove(tempMessageId);
        _visibleCount = (_visibleCount - 1).clamp(0, _messages.length);
      });
    }
  }

  Future<void> _toggleAudioPlayback({
    required MessageModel message,
    required Map<String, dynamic> attachment,
  }) async {
    try {
      if (_playingAudioMessageId == message.id) {
        await _audioPlayer.stop();
        if (!mounted) return;
        setState(() {
          _playingAudioMessageId = null;
        });
        return;
      }

      String? localPath = _getCachedAttachmentPath(message, attachment);
      localPath ??= await _downloadAttachment(
        message: message,
        attachment: attachment,
      );
      if (localPath == null) return;

      await _audioPlayer.stop();
      await _audioPlayer.play(DeviceFileSource(localPath));
      if (!mounted) return;
      setState(() {
        _playingAudioMessageId = message.id;
      });
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not play voice message')),
      );
    }
  }

  Future<void> _sendSelectedMedia() async {
    if (_selectedMediaFile == null || _selectedMediaType == null) return;

    final file = _selectedMediaFile!;
    final mediaType = _selectedMediaType!;
    final isVideo = mediaType == 'video';
    final caption = _messageController.text.trim();
    final fileName = file.path.split('/').last;
    final tempMessageId = 'uploading_${DateTime.now().millisecondsSinceEpoch}';

    // Capture thumbnail before clearing state
    final thumbnailBytes = _selectedVideoThumbnail;

    try {
      // Build temporary attachment payload (without bytes for now - we'll show placeholder size)
      final sanitizedFileName = fileName.replaceAll(
        RegExp(r'[^a-zA-Z0-9._-]'),
        '_',
      );
      final tempPayload = jsonEncode({
        'type': mediaType,
        'url': '',
        'name': sanitizedFileName,
        'storagePath': '',
        'sizeBytes': 0, // Will be updated after reading file
        if (caption.isNotEmpty) 'caption': caption,
      });

      // Create optimistic/temporary message to show immediately
      final tempMessage = MessageModel(
        id: tempMessageId,
        fromId: widget.currentUser.uid,
        toId: widget.peer.uid,
        text: '${ChatService.attachmentPrefix}$tempPayload',
        timestamp: DateTime.now().millisecondsSinceEpoch,
        delivered: true,
      );

      // Prepare paths - for immediate preview, use original file location
      String? previewPath = file.path; // Original file for immediate preview
      String? thumbnailPath;

      // Cache dir should already be initialized in initState, but if not, schedule async init (don't await)
      if (_attachmentCacheDirPath == null) {
        unawaited(_initializeAttachmentCacheDir());
      }

      // Calculate thumbnail path (but don't write it yet - do it in background)
      if (_attachmentCacheDirPath != null &&
          isVideo &&
          thumbnailBytes != null) {
        thumbnailPath =
            '$_attachmentCacheDirPath/${tempMessageId}_thumbnail.jpg';
      }

      // Update UI immediately - show message with preview (NO AWAITS BEFORE THIS!)
      setState(() {
        _uploadingMessageIds.add(tempMessageId);
        _messages.insert(0, tempMessage);
        _visibleCount = (_visibleCount + 1).clamp(0, _messages.length);

        // Store original file path for immediate preview (for both image and video)
        _cachedAttachmentPaths[tempMessageId] = previewPath;

        // Don't store thumbnail path yet - it will be set in background after file is written

        // Clear selected media
        _selectedMediaFile = null;
        _selectedMediaType = null;
        _selectedVideoThumbnail = null;
        _messageController.clear();
      });

      // Scroll to show new message
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          _scrollController.jumpTo(0);
        }
      });

      // Start upload in background (don't await - returns immediately)
      unawaited(
        _uploadMediaInBackground(
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

  Future<void> _uploadMediaInBackground({
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
      // Write thumbnail to disk if we have it (do this first while reading file)
      if (isVideo && thumbnailBytes != null && thumbnailPath != null) {
        final thumbnailFile = File(thumbnailPath);
        await thumbnailFile.writeAsBytes(thumbnailBytes, flush: true);
        // Update UI that thumbnail is now available
        if (mounted) {
          setState(() {
            _videoThumbnailPaths[tempMessageId] = thumbnailPath;
          });
        }
      }

      // Read the full file for upload
      final bytes = await file.readAsBytes();

      // Copy to permanent cache location
      if (_attachmentCacheDirPath != null) {
        final safeName = ChatHelpers.sanitizedFileName(fileName);
        final cachePath = '$_attachmentCacheDirPath/${tempMessageId}_$safeName';
        final cacheFile = File(cachePath);
        await cacheFile.writeAsBytes(bytes, flush: true);
        if (mounted) {
          setState(() {
            // Update to permanent cache location
            _cachedAttachmentPaths[tempMessageId] = cachePath;
          });
        }
      }

      // Upload
      final realMessage = await ChatService.sendMediaAttachment(
        fromId: widget.currentUser.uid,
        toId: widget.peer.uid,
        mediaType: mediaType,
        bytes: bytes,
        fileName: fileName,
        contentType: isVideo ? 'video/mp4' : 'image/jpeg',
        caption: caption.isEmpty ? null : caption,
      );

      // Load updated messages to replace temp with real message
      await _loadMessages(scrollToBottom: false);

      // Rename thumbnail file to match real message ID (so it persists after close/reopen)
      if (_videoThumbnailPaths.containsKey(tempMessageId)) {
        final oldThumbnailPath = _videoThumbnailPaths[tempMessageId]!;
        final oldFile = File(oldThumbnailPath);
        if (await oldFile.exists()) {
          // Create new path with real message ID
          final newThumbnailPath = oldThumbnailPath.replaceFirst(
            '${tempMessageId}_thumbnail.jpg',
            '${realMessage.id}_thumbnail.jpg',
          );
          try {
            // Rename file on disk
            await oldFile.rename(newThumbnailPath);
            // Update in-memory map
            _videoThumbnailPaths[realMessage.id] = newThumbnailPath;
            _videoThumbnailPaths.remove(tempMessageId);
          } catch (e) {
            // If rename fails, just update the map with the old path
            _videoThumbnailPaths[realMessage.id] = oldThumbnailPath;
            _videoThumbnailPaths.remove(tempMessageId);
          }
        }
      }

      // Transfer cached paths from temp message to real message using the returned message ID
      if (mounted) {
        setState(() {
          _uploadingMessageIds.remove(tempMessageId);

          // Transfer cached attachment path
          if (_cachedAttachmentPaths.containsKey(tempMessageId)) {
            final tempPath = _cachedAttachmentPaths[tempMessageId]!;
            _cachedAttachmentPaths[realMessage.id] = tempPath;
            _cachedAttachmentPaths.remove(tempMessageId);
          }

          // Video thumbnail path already transferred above (with file renamed)
        });
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Failed to send media')));
      // Remove temp message on error
      setState(() {
        _messages.removeWhere((m) => m.id == tempMessageId);
        _uploadingMessageIds.remove(tempMessageId);
        _visibleCount = (_visibleCount - 1).clamp(0, _messages.length);
      });
    }
  }

  void _cancelSelectedMedia() {
    setState(() {
      _selectedMediaFile = null;
      _selectedMediaType = null;
      _selectedVideoThumbnail = null;
    });
  }

  Future<void> _pickAndSendImageAttachment() async {
    await _pickAndSendMediaAttachment(isVideo: false);
  }

  Future<void> _pickAndSendVideoAttachment() async {
    await _pickAndSendMediaAttachment(isVideo: true);
  }

  Future<void> _pickAndSendMediaAttachment({required bool isVideo}) async {
    try {
      final XFile? picked = isVideo
          ? await _imagePicker.pickVideo(source: ImageSource.gallery)
          : await _imagePicker.pickImage(
              source: ImageSource.gallery,
              imageQuality: 85,
            );
      if (picked == null) return;

      final fileSize = await picked.length();
      if (fileSize > ChatService.maxAttachmentBytes) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Attachment must be 10MB or smaller')),
        );
        return;
      }

      // Generate video thumbnail if needed
      Uint8List? videoThumbnail;
      if (isVideo) {
        videoThumbnail = await ChatHelpers.generateVideoThumbnail(picked.path);
      }

      if (!mounted) return;

      // Store selected media without uploading
      setState(() {
        _selectedMediaFile = File(picked.path);
        _selectedMediaType = isVideo ? 'video' : 'image';
        _selectedVideoThumbnail = videoThumbnail;
      });
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Could not select media')));
    }
  }

  Future<void> _showAttachmentOptions() async {
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
                  await _pickAndSendImageAttachment();
                },
              ),
              ListTile(
                leading: const Icon(Icons.videocam_rounded),
                title: const Text('Video'),
                onTap: () async {
                  Navigator.of(context).pop();
                  await _pickAndSendVideoAttachment();
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<String?> _downloadAttachment({
    required MessageModel message,
    required Map<String, dynamic> attachment,
  }) async {
    if (_downloadingMessageIds.contains(message.id)) return null;
    setState(() {
      _downloadingMessageIds.add(message.id);
    });

    try {
      final bytes = await ChatService.downloadAttachmentAndDeleteFromStorage(
        attachment,
        deleteAfterDownload: message.fromId != widget.currentUser.uid,
      );
      final fileName = (attachment['name'] as String?) ?? 'attachment.bin';
      final mediaType = (attachment['type'] as String?) ?? 'file';
      if (_attachmentCacheDirPath == null) {
        await _initializeAttachmentCacheDir();
      }
      final safeName = ChatHelpers.sanitizedFileName(fileName);
      final baseDir = _attachmentCacheDirPath;
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
              _videoThumbnailPaths[message.id] = thumbnailPath;
            });
          }
        }
      }

      if (!mounted) return null;
      setState(() {
        _cachedAttachmentPaths[message.id] = savePath;
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
          _downloadingMessageIds.remove(message.id);
        });
      }
    }
  }

  Future<void> _onMediaMessageTap({
    required MessageModel message,
    required Map<String, dynamic> attachment,
  }) async {
    if (_downloadingMessageIds.contains(message.id)) return;
    final isVideo = (attachment['type'] as String?) == 'video';
    final displayName =
        (attachment['name'] as String?) ?? (isVideo ? 'Video' : 'Photo');
    final cached = _getCachedAttachmentPath(message, attachment);
    if (cached != null) {
      _openMediaPreview(filePath: cached, isVideo: isVideo, title: displayName);
      return;
    }
    final downloadedPath = await _downloadAttachment(
      message: message,
      attachment: attachment,
    );
    if (!mounted) return;
    if (downloadedPath != null) {
      _openMediaPreview(
        filePath: downloadedPath,
        isVideo: isVideo,
        title: displayName,
      );
    }
  }

  void _openMediaPreview({
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

  String? _getCachedAttachmentPath(
    MessageModel message,
    Map<String, dynamic> attachment,
  ) {
    final inMemory = _cachedAttachmentPaths[message.id];
    if (inMemory != null && File(inMemory).existsSync()) {
      return inMemory;
    }

    if (_attachmentCacheDirPath == null) return null;
    final fileName = ChatHelpers.sanitizedFileName(
      (attachment['name'] as String?) ?? 'attachment.bin',
    );
    final candidate = '$_attachmentCacheDirPath/${message.id}_$fileName';
    if (File(candidate).existsSync()) {
      _cachedAttachmentPaths[message.id] = candidate;
      return candidate;
    }

    if (message.fromId == widget.currentUser.uid) {
      try {
        final cacheDir = Directory(_attachmentCacheDirPath!);
        if (cacheDir.existsSync()) {
          final files = cacheDir.listSync().whereType<File>();
          for (final file in files) {
            if (file.path.endsWith(fileName)) {
              _cachedAttachmentPaths[message.id] = file.path;
              return file.path;
            }
          }
        }
      } catch (_) {}
    }
    return null;
  }

  String? _getCachedVideoThumbnailPath(MessageModel message) {
    // Check in-memory cache first
    if (_videoThumbnailPaths.containsKey(message.id)) {
      return _videoThumbnailPaths[message.id];
    }

    // If not in memory, check if thumbnail exists on disk
    // Thumbnails are saved with predictable names: ${cacheDir}/${messageId}_thumbnail.jpg
    if (_attachmentCacheDirPath != null) {
      final predictedPath =
          '$_attachmentCacheDirPath/${message.id}_thumbnail.jpg';
      if (File(predictedPath).existsSync()) {
        // Cache it for next time
        _videoThumbnailPaths[message.id] = predictedPath;
        return predictedPath;
      }
    }

    return null;
  }

  Widget _buildRecordingWaveform(bool isDark) {
    final tick = _recordingDuration.inMilliseconds ~/ 250;
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

  bool _shouldShowDateSeparator(int index) {
    final visibleMessages = _visibleMessages();
    if (visibleMessages.isEmpty) return false;
    if (index == visibleMessages.length - 1) return true;

    final currentMessage = visibleMessages[visibleMessages.length - 1 - index];
    final nextMessage = visibleMessages[visibleMessages.length - 2 - index];

    return ChatHelpers.shouldShowDateSeparator(
      currentMessage.timestamp,
      nextMessage.timestamp,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final visibleMessages = _visibleMessages();
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        elevation: 1,
        shadowColor: Colors.black.withValues(alpha: 0.1),
        title: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: const BoxDecoration(shape: BoxShape.circle),
              child: ClipOval(
                child: Image.network(
                  widget.peer.profilePic,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
                    color: Colors.grey[400],
                    child: Icon(Icons.person, color: Colors.grey[600]),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.peer.displayName,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    widget.peer.isOnline ? 'Online' : 'Offline',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w400,
                      color: isDark ? Colors.white70 : Colors.black54,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: visibleMessages.isEmpty
                ? Center(
                    child: Text(
                      'No messages yet',
                      style: TextStyle(
                        color: isDark ? Colors.white54 : Colors.black38,
                        fontSize: 16,
                      ),
                    ),
                  )
                : ListView.builder(
                    reverse: true,
                    controller: _scrollController,
                    itemCount: visibleMessages.length,
                    itemBuilder: (context, index) {
                      final message =
                          visibleMessages[visibleMessages.length - 1 - index];
                      final mine = message.fromId == widget.currentUser.uid;
                      final showSeparator = _shouldShowDateSeparator(index);

                      return Column(
                        children: [
                          if (showSeparator) ...[
                            const SizedBox(height: 12),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: isDark
                                    ? Colors.white.withValues(alpha: 0.08)
                                    : Colors.black.withValues(alpha: 0.05),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                ChatHelpers.formatDateSeparator(
                                  message.timestamp,
                                ),
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: isDark
                                      ? AppColors.darkTextSecondary
                                      : AppColors.lightTextSecondary,
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                          ],
                          Align(
                            alignment: mine
                                ? Alignment.centerRight
                                : Alignment.centerLeft,
                            child: Container(
                              constraints: BoxConstraints(
                                maxWidth:
                                    MediaQuery.of(context).size.width * 0.75,
                              ),
                              margin: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 10,
                              ),
                              decoration: BoxDecoration(
                                gradient: mine
                                    ? AppColors.primaryGradient
                                    : null,
                                color: mine
                                    ? null
                                    : (isDark
                                          ? AppColors.darkSurface
                                          : AppColors.lightSurface),
                                borderRadius: BorderRadius.only(
                                  topLeft: const Radius.circular(16),
                                  topRight: const Radius.circular(16),
                                  bottomLeft: Radius.circular(mine ? 16 : 4),
                                  bottomRight: Radius.circular(mine ? 4 : 16),
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.08),
                                    blurRadius: 4,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  _buildMessageContent(message, mine, isDark),
                                  const SizedBox(height: 6),
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        DateTimeUtils.formatTime(
                                          message.timestamp,
                                        ),
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: mine
                                              ? Colors.white70
                                              : (isDark
                                                    ? AppColors
                                                          .darkTextSecondary
                                                    : AppColors
                                                          .lightTextSecondary),
                                          fontWeight: FontWeight.w400,
                                        ),
                                      ),
                                      if (mine) ...[
                                        const SizedBox(width: 4),
                                        Icon(
                                          message.delivered
                                              ? Icons.done_all
                                              : Icons.done,
                                          size: 14,
                                          color: message.delivered
                                              ? (message.read ? Colors.blue : Colors.white)
                                              : Colors.white70,
                                        ),
                                      ],
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
          ),
          ChatComposer(
            isDark: isDark,
            isRecordingVoice: _isRecordingVoice,
            recordingDuration: _recordingDuration,
            recordingSlideOffset: _recordingSlideOffset,
            recordingWaveform: _buildRecordingWaveform(isDark),
            selectedMediaFile: _selectedMediaFile,
            selectedMediaType: _selectedMediaType,
            selectedVideoThumbnail: _selectedVideoThumbnail,
            messageController: _messageController,
            onAttachmentTap: _showAttachmentOptions,
            onSendTap: _sendMessage,
            onCancelSelectedMedia: _cancelSelectedMedia,
            onSubmitted: (_) => _sendMessage(),
            onVoiceLongPressStart: _onVoiceLongPressStart,
            onVoiceLongPressMoveUpdate: _onVoiceLongPressMove,
            onVoiceLongPressEnd: _onVoiceLongPressEnd,
          ),
        ],
      ),
    );
  }

  Widget _buildMessageContent(MessageModel message, bool mine, bool isDark) {
    final attachment = ChatService.parseAttachmentPayload(message.text);
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
      final isDownloading = _downloadingMessageIds.contains(message.id);
      final isUploading = _uploadingMessageIds.contains(message.id);
      final durationMs = (attachment['durationMs'] as num?)?.toInt() ?? 0;
      final durationLabel = _formatRecordingDuration(
        Duration(milliseconds: durationMs),
      );
      final isPlaying = _playingAudioMessageId == message.id;
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
                          : () => _toggleAudioPlayback(
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
                    _buildRecordingWaveform(isDark),
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

    if (type == 'image' || type == 'video') {
      final isVideo = type == 'video';
      final name =
          attachment['name'] as String? ?? (isVideo ? 'Video' : 'Photo');
      final isDownloading = _downloadingMessageIds.contains(message.id);
      final isUploading = _uploadingMessageIds.contains(message.id);
      final cachedPath = _getCachedAttachmentPath(message, attachment);
      final videoThumbnailPath = isVideo
          ? _getCachedVideoThumbnailPath(message)
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
                _onMediaMessageTap(message: message, attachment: attachment),
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
}
