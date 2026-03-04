import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:whatsapp_clone/chat/chat_service.dart';
import 'package:whatsapp_clone/core/design_tokens.dart';
import 'package:whatsapp_clone/models/message_model.dart';
import 'package:whatsapp_clone/providers/messages_provider.dart';
import 'package:whatsapp_clone/utils/date_time_utils.dart';
import 'package:whatsapp_clone/screens/chat/chat_screen.dart';
import 'package:whatsapp_clone/screens/chat/helpers/chat_helpers.dart';
import 'package:whatsapp_clone/screens/chat/widgets/chat_composer.dart';
import 'package:whatsapp_clone/screens/chat/voice_message_handler.dart';
import 'package:whatsapp_clone/screens/chat/media_handler.dart';
import 'package:whatsapp_clone/screens/chat/message_builder.dart';

class ChatScreenState extends State<ChatScreen>
    with VoiceMessageHandler, MediaHandler, MessageBuilder {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final ImagePicker _imagePicker = ImagePicker();
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

  File? _selectedMediaFile;
  String? _selectedMediaType;
  Uint8List? _selectedVideoThumbnail;
  bool _isRecordingVoice = false;
  Duration _recordingDuration = Duration.zero;
  Timer? _recordingTimer;
  String? _playingAudioMessageId;
  double _recordingSlideOffset = 0;
  bool _recordingCancelTriggered = false;

  // Getters for mixins
  @override
  AudioRecorder get audioRecorder => _audioRecorder;

  @override
  AudioPlayer get audioPlayer => _audioPlayer;

  @override
  String? get attachmentCacheDirPath => _attachmentCacheDirPath;

  @override
  Set<String> get downloadingMessageIds => _downloadingMessageIds;

  @override
  String get currentUserId => widget.currentUser.uid;

  @override
  String get peerUserId => widget.peer.uid;

  @override
  File? get selectedMediaFile => _selectedMediaFile;

  @override
  String? get selectedMediaType => _selectedMediaType;

  @override
  Uint8List? get selectedVideoThumbnail => _selectedVideoThumbnail;

  @override
  Set<String> get uploadingMessageIds => _uploadingMessageIds;

  @override
  ImagePicker get imagePicker => _imagePicker;

  @override
  bool get isRecordingVoice => _isRecordingVoice;

  @override
  Duration get recordingDuration => _recordingDuration;

  @override
  Timer? get recordingTimer => _recordingTimer;

  @override
  String? get playingAudioMessageId => _playingAudioMessageId;

  @override
  double get recordingSlideOffset => _recordingSlideOffset;

  @override
  bool get recordingCancelTriggered => _recordingCancelTriggered;

  @override
  Map<String, String> get cachedAttachmentPaths => _cachedAttachmentPaths;

  @override
  Map<String, String> get videoThumbnailPaths => _videoThumbnailPaths;

  @override
  TextEditingController get messageController => _messageController;

  @override
  ScrollController get scrollController => _scrollController;

  /// Provider accessor for messages
  MessagesStateNotifier get messagesProvider =>
      Provider.of<MessagesStateNotifier>(context, listen: false);

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
    initializeAttachmentCacheDir();
    _loadMessages(scrollToBottom: true);
    _subscribeToIncomingMessages();
  }

  @override
  Future<void> initializeAttachmentCacheDir() async {
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
    _incomingSubscription =
        ChatService.streamIncomingForUser(widget.currentUser.uid).listen((
          newMessage,
        ) {
          if (newMessage.fromId == widget.peer.uid ||
              newMessage.toId == widget.peer.uid) {
            if (mounted) {
              final existingIndex =
                  messagesProvider.messages.indexWhere(
                (m) => m.id == newMessage.id,
              );
              if (existingIndex != -1) {
                messagesProvider.updateMessage(newMessage);
              } else {
                messagesProvider.insertMessage(newMessage);
              }
            }
          }
        });
  }

  void _loadMoreMessages() {
    if (_isLoadingMore || !_hasMoreMessages) return;
    if (!mounted) return;
    setState(() => _isLoadingMore = true);

    Future.delayed(const Duration(milliseconds: 500), () async {
      await _loadMessages(scrollToBottom: false);
      if (mounted) {
        setState(() => _isLoadingMore = false);
      }
    });
  }

  @override
  Future<void> loadMessages({bool scrollToBottom = false}) async {
    return _loadMessages(scrollToBottom: scrollToBottom);
  }

  Future<void> _loadMessages({bool scrollToBottom = false}) async {
    try {
      final messages = await ChatService.getMessagesBetween(
        widget.currentUser.uid,
        widget.peer.uid,
      );

      if (mounted) {
        messagesProvider.setMessages(messages);
        setState(() {
          _hasMoreMessages = messages.length >= _pageSize;
        });

        if (scrollToBottom && _scrollController.hasClients) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            _scrollController.jumpTo(0);
          });
        }
      }
    } catch (_) {
      // Handle error silently or show snackbar
    }
  }

  void _sendMessage() {
    if (_selectedMediaFile != null) {
      unawaited(sendSelectedMedia());
      return;
    }

    final text = _messageController.text.trim();
    if (text.isEmpty) return;

    final tempMessageId = 'temp_${DateTime.now().millisecondsSinceEpoch}';
    final tempMessage = MessageModel(
      id: tempMessageId,
      fromId: widget.currentUser.uid,
      toId: widget.peer.uid,
      text: text,
      timestamp: DateTime.now().millisecondsSinceEpoch,
      delivered: false,
    );

    messagesProvider.insertMessage(tempMessage);
    _messageController.clear();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(0);
      }
    });

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

      await _loadMessages(scrollToBottom: false);

      if (mounted) {
        messagesProvider.removeMessage(tempMessageId);
      }
    } catch (e) {
      if (mounted) {
        messagesProvider.removeMessage(tempMessageId);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Failed to send message')));
      }
    }
  }

  List<MessageModel> _visibleMessages() {
    return messagesProvider.visibleMessages;
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

  /// Setter methods for mixin state updates
  @override
  void setSelectedMediaFile(File? file) {
    if (!mounted) return;
    setState(() {
      _selectedMediaFile = file;
    });
  }

  @override
  void setSelectedMediaType(String? type) {
    if (!mounted) return;
    setState(() {
      _selectedMediaType = type;
    });
  }

  @override
  void setSelectedVideoThumbnail(Uint8List? thumbnail) {
    if (!mounted) return;
    setState(() {
      _selectedVideoThumbnail = thumbnail;
    });
  }

  @override
  void clearSelectedMedia() {
    if (!mounted) return;
    setState(() {
      _selectedMediaFile = null;
      _selectedMediaType = null;
      _selectedVideoThumbnail = null;
    });
  }

  @override
  void addUploadingMessageId(String id) {
    if (!mounted) return;
    setState(() {
      _uploadingMessageIds.add(id);
    });
  }

  @override
  void removeUploadingMessageId(String id) {
    if (!mounted) return;
    setState(() {
      _uploadingMessageIds.remove(id);
    });
  }

  @override
  void insertMessage(MessageModel message) {
    if (!mounted) return;
    setState(() {
      _messages.insert(0, message);
      _visibleCount = (_visibleCount + 1).clamp(0, _messages.length);
    });
  }

  @override
  void updateCachedAttachmentPath(String key, String path) {
    if (!mounted) return;
    setState(() {
      _cachedAttachmentPaths[key] = path;
    });
  }

  @override
  void updateVideoThumbnailPath(String key, String path) {
    if (!mounted) return;
    setState(() {
      _videoThumbnailPaths[key] = path;
    });
  }

  @override
  void removeVideoThumbnailPath(String key) {
    if (!mounted) return;
    setState(() {
      _videoThumbnailPaths.remove(key);
    });
  }

  @override
  void removeCachedAttachmentPath(String key) {
    if (!mounted) return;
    setState(() {
      _cachedAttachmentPaths.remove(key);
    });
  }

  @override
  void removeMessage(String id) {
    if (!mounted) return;
    setState(() {
      _messages.removeWhere((m) => m.id == id);
      _visibleCount = (_visibleCount - 1).clamp(0, _messages.length);
    });
  }

  @override
  void incrementVisibleCount() {
    if (!mounted) return;
    setState(() {
      _visibleCount = (_visibleCount + 1).clamp(0, _messages.length);
    });
  }

  @override
  void decrementVisibleCount() {
    if (!mounted) return;
    setState(() {
      _visibleCount = (_visibleCount - 1).clamp(0, _messages.length);
    });
  }

  /// Voice recording state setters
  @override
  void setIsRecordingVoice(bool value) {
    if (!mounted) return;
    setState(() {
      _isRecordingVoice = value;
    });
  }

  @override
  void setRecordingDuration(Duration duration) {
    if (!mounted) return;
    setState(() {
      _recordingDuration = duration;
    });
  }

  @override
  void setRecordingTimer(Timer? timer) {
    if (!mounted) return;
    setState(() {
      _recordingTimer = timer;
    });
  }

  @override
  void setRecordingSlideOffset(double offset) {
    if (!mounted) return;
    setState(() {
      _recordingSlideOffset = offset;
    });
  }

  @override
  void setRecordingCancelTriggered(bool value) {
    if (!mounted) return;
    setState(() {
      _recordingCancelTriggered = value;
    });
  }

  @override
  void setPlayingAudioMessageId(String? id) {
    if (!mounted) return;
    setState(() {
      _playingAudioMessageId = id;
    });
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
                                  buildMessageContent(message, mine, isDark),
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
                                              ? Colors.white
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
            recordingWaveform: buildRecordingWaveform(isDark),
            selectedMediaFile: _selectedMediaFile,
            selectedMediaType: _selectedMediaType,
            selectedVideoThumbnail: _selectedVideoThumbnail,
            messageController: _messageController,
            onAttachmentTap: showAttachmentOptions,
            onSendTap: _sendMessage,
            onCancelSelectedMedia: cancelSelectedMedia,
            onSubmitted: (_) => _sendMessage(),
            onVoiceLongPressStart: onVoiceLongPressStart,
            onVoiceLongPressMoveUpdate: onVoiceLongPressMove,
            onVoiceLongPressEnd: onVoiceLongPressEnd,
          ),
        ],
      ),
    );
  }
}
