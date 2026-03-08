import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:whatsapp_clone/chat/call_service.dart';
import 'package:whatsapp_clone/chat/chat_service.dart';
import 'package:whatsapp_clone/core/agora_service.dart';
import 'package:whatsapp_clone/core/design_tokens.dart';
import 'package:whatsapp_clone/core/firebase_service.dart';
import 'package:whatsapp_clone/core/local_db_service.dart';
import 'package:whatsapp_clone/core/notification_service.dart';
import 'package:whatsapp_clone/models/message_model.dart';
import 'package:whatsapp_clone/providers/media_provider.dart';
import 'package:whatsapp_clone/providers/messages_provider.dart';
import 'package:whatsapp_clone/providers/recording_provider.dart';
import 'package:whatsapp_clone/providers/upload_provider.dart';
import 'package:whatsapp_clone/utils/date_time_utils.dart';
import 'package:whatsapp_clone/screens/chat/chat_screen.dart';
import 'package:whatsapp_clone/screens/chat/helpers/chat_helpers.dart';
import 'package:whatsapp_clone/screens/chat/widgets/chat_composer.dart';
import 'package:whatsapp_clone/screens/chat/voice_message_handler.dart';
import 'package:whatsapp_clone/screens/chat/media_handler.dart';
import 'package:whatsapp_clone/screens/chat/message_builder.dart';
import 'package:whatsapp_clone/screens/user_profile_screen.dart';
import 'package:whatsapp_clone/screens/call/enhanced_in_call_screen.dart';

class ChatScreenState extends State<ChatScreen>
    with VoiceMessageHandler, MediaHandler, MessageBuilder {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final ImagePicker _imagePicker = ImagePicker();
  final AudioRecorder _audioRecorder = AudioRecorder();
  final AudioPlayer _audioPlayer = AudioPlayer();

  StreamSubscription<MessageModel>? _incomingSubscription;
  StreamSubscription<Map<String, dynamic>>? _statusSubscription;
  Timer? _statusRefreshTimer;
  static const int _pageSize = 30;
  bool _isLoadingMore = false;
  bool _hasMoreMessages = false;
  final Set<String> _downloadingMessageIds = <String>{};
  String? _attachmentCacheDirPath;
  bool _isInitialized = false; // Track if didChangeDependencies has run

  // Cached provider references (set in didChangeDependencies)
  late RecordingStateNotifier _recordingProvider;
  late MediaStateNotifier _mediaProvider;
  late UploadStateNotifier _uploadProvider;
  late MessagesStateNotifier _messagesProvider;

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
  File? get selectedMediaFile => mediaProvider.selectedMediaFile;

  @override
  String? get selectedMediaType => mediaProvider.selectedMediaType;

  @override
  Uint8List? get selectedVideoThumbnail => mediaProvider.selectedVideoThumbnail;

  @override
  Set<String> get uploadingMessageIds => uploadProvider.uploadingMessageIds;

  @override
  ImagePicker get imagePicker => _imagePicker;

  @override
  bool get isRecordingVoice => recordingProvider.isRecording;

  @override
  Duration get recordingDuration => recordingProvider.recordingDuration;

  @override
  Timer? get recordingTimer => recordingProvider.recordingTimer;

  @override
  String? get playingAudioMessageId => recordingProvider.playingAudioMessageId;

  @override
  double get recordingSlideOffset => recordingProvider.recordingSlideOffset;

  @override
  bool get recordingCancelTriggered =>
      recordingProvider.recordingCancelTriggered;

  @override
  Map<String, String> get cachedAttachmentPaths =>
      uploadProvider.cachedAttachmentPaths;

  @override
  Map<String, String> get videoThumbnailPaths =>
      uploadProvider.videoThumbnailPaths;

  @override
  TextEditingController get messageController => _messageController;

  @override
  ScrollController get scrollController => _scrollController;

  /// Provider accessors (return cached instances)
  @override
  RecordingStateNotifier get recordingProvider => _recordingProvider;

  @override
  MediaStateNotifier get mediaProvider => _mediaProvider;

  @override
  UploadStateNotifier get uploadProvider => _uploadProvider;

  /// Scoped provider accessor for messages (per-chat instance)
  MessagesStateNotifier get messagesProvider => _messagesProvider;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Cache provider references for safe access in dispose()
    _recordingProvider = Provider.of<RecordingStateNotifier>(
      context,
      listen: false,
    );
    _mediaProvider = Provider.of<MediaStateNotifier>(context, listen: false);
    _uploadProvider = Provider.of<UploadStateNotifier>(context, listen: false);
    _messagesProvider = Provider.of<MessagesStateNotifier>(
      context,
      listen: false,
    );

    // Only run initialization once
    if (!_isInitialized) {
      _isInitialized = true;

      // Set up callback for temp message insertion (only once)
      _messagesProvider.setOnTempMessageInserted(() {
        if (mounted) {
          setState(() {
            // Force immediate rebuild when temp message is inserted
          });
        }
      });

      // Load messages only if provider hasn't loaded from local DB yet
      if (!messagesProvider.initialLoadComplete) {
        _loadMessages(scrollToBottom: true);
      }
    }
  }

  @override
  void initState() {
    super.initState();
    NotificationService.setActiveChat(
      currentUserUid: widget.currentUser.uid,
      peerUid: widget.peer.uid,
    );
    _scrollController.addListener(_onScroll);
    _messageController.addListener(_onComposerChanged);
    _audioPlayer.onPlayerComplete.listen((_) {
      if (!mounted) return;
      // Access provider safely - will be set before this callback fires
      if (_isInitialized) {
        recordingProvider.setPlayingAudioMessageId(null);
      }
    }); // Sync any missed messages before displaying chat
    _syncMissedMessages();
    initializeAttachmentCacheDir();
    _subscribeToIncomingMessages();
    _subscribeToStatusUpdates();
    _listenForMessageDeletions();
    _startStatusRefreshTimer();
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
    NotificationService.clearActiveChat(peerUid: widget.peer.uid);
    recordingProvider.recordingTimer?.cancel();
    _statusRefreshTimer?.cancel();
    unawaited(_audioRecorder.dispose());
    unawaited(_audioPlayer.dispose());
    _incomingSubscription?.cancel();
    _statusSubscription?.cancel();
    _messageController.removeListener(_onComposerChanged);
    _messageController.dispose();
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();

    // Clear temp message callback
    _messagesProvider.setOnTempMessageInserted(null);

    super.dispose();
  }

  Future<void> _initiateCall(String callType) async {
    try {
      // Initiate call in Firebase
      final call = await CallService.initiateCall(
        initiatorId: widget.currentUser.uid,
        initiatorName: widget.currentUser.displayName,
        initiatorProfilePic: widget.currentUser.profilePic,
        receiverId: widget.peer.uid,
        receiverName: widget.peer.displayName,
        receiverProfilePic: widget.peer.profilePic,
        callType: callType,
      );

      if (!mounted) return;

      // Convert user IDs to integers for Agora (using hashCode)
      final localUid = widget.currentUser.uid.hashCode.abs() % 2147483647;
      final remoteUid = widget.peer.uid.hashCode.abs() % 2147483647;

      // Get Agora token from Cloud Function
      final token = await CallService.getAgoraToken(
        channelName: call.callId,
        uid: localUid,
      );

      // Initialize and setup Agora service
      final agoraService = AgoraService();
      await agoraService.initialize();
      await agoraService.joinChannel(
        channelName: call.callId,
        uid: localUid,
        token: token,
        isVideoCall: callType == 'video',
      );

      if (!mounted) return;

      // Navigate to in-call screen
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => EnhancedInCallScreen(
            callModel: call,
            agoraService: agoraService,
            remoteUid: remoteUid,
            onEndCall: () async {
              try {
                await CallService.endCall(
                  callId: call.callId,
                  endReason: 'user_ended',
                );
                await agoraService.dispose();
              } catch (e) {
                print('[ChatScreen] Error in onEndCall: $e');
              }
              
              // Safely pop after current frame
              if (context.mounted) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (context.mounted && Navigator.of(context).canPop()) {
                    Navigator.of(context).pop();
                  }
                });
              }
            },
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      print('[ChatScreen] Error initiating call: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to initiate call: $e')),
      );
    }
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
              final existingIndex = messagesProvider.messages.indexWhere(
                (m) => m.id == newMessage.id,
              );
              if (existingIndex != -1) {
                messagesProvider.updateMessage(newMessage);
                setState(() {}); // Force rebuild for incoming updates
              } else {
                insertMessage(
                  newMessage,
                ); // Use override that includes setState()
              }

              // Mark incoming messages as delivered and read
              if (newMessage.fromId == widget.peer.uid) {
                _markMessageAsDeliveredAndRead(messageId: newMessage.id);
              }
            }
          }
        });
  }

  /// Subscribe to status updates for messages sent by current user
  void _subscribeToStatusUpdates() {
    _statusSubscription =
        FirebaseService.listenForStatusUpdates(widget.currentUser.uid).listen((
          statusUpdate,
        ) {
          if (!mounted) return;

          final messageId = statusUpdate['messageId'] as String?;
          final localMessageId = statusUpdate['localMessageId'] as String?;
          final delivered = statusUpdate['delivered'] as bool? ?? false;
          final read = statusUpdate['read'] as bool? ?? false;

          if (messageId == null && localMessageId == null) return;

          final targetId = messageId ?? localMessageId!;

          // Find and update the message in the provider
          final messageIndex = messagesProvider.messages.indexWhere(
            (m) =>
                m.id == targetId ||
                (localMessageId != null && m.id == localMessageId),
          );

          if (messageIndex != -1) {
            final message = messagesProvider.messages[messageIndex];
            final updatedMessage = message.copyWith(
              delivered: delivered,
              read: read,
            );
            messagesProvider.updateMessage(updatedMessage);

            // Also update local DB
            ChatService.updateMessageStatus(targetId, delivered, read);

            setState(() {}); // Force UI rebuild to show new status
          } else {
            // Message might not be loaded in current provider, still persist status locally.
            ChatService.updateMessageStatus(targetId, delivered, read);
          }
        });
  }

  /// Start periodic refresh of message status for sent messages
  /// This catches delivery updates from offline users who come online later
  void _startStatusRefreshTimer() {
    _statusRefreshTimer = Timer.periodic(const Duration(seconds: 15), (
      _,
    ) async {
      if (!mounted) return;
      await _refreshSentMessagesStatus();
    });
  }

  /// Refresh status of all sent messages in current chat from Firebase
  /// Only checks messages that are unread or undelivered
  Future<void> _refreshSentMessagesStatus() async {
    try {
      final sentMessages = messagesProvider.messages
          .where(
            (m) =>
                m.fromId == widget.currentUser.uid &&
                (!m.delivered || !m.read), // Only undelivered or unread
          )
          .toList();

      for (final message in sentMessages) {
        final statusMap = await FirebaseService.getMessageStatus(message.id);
        if (statusMap != null && mounted) {
          final delivered = statusMap['delivered'] as bool? ?? false;
          final read = statusMap['read'] as bool? ?? false;

          // If status changed, update the message
          if (message.delivered != delivered || message.read != read) {
            final updatedMessage = message.copyWith(
              delivered: delivered,
              read: read,
            );
            messagesProvider.updateMessage(updatedMessage);
            ChatService.updateMessageStatus(message.id, delivered, read);
            setState(() {});
          }
        }
      }
    } catch (e) {
      // Silently handle refresh errors
    }
  }

  /// Listen for message deletions (when messages are removed from Firebase)
  void _listenForMessageDeletions() {
    // Set up a periodic check to sync deletions
    Timer.periodic(const Duration(seconds: 30), (timer) async {
      if (!mounted) {
        timer.cancel();
        return;
      }

      try {
        // Get all messages with remoteId from local DB for this chat
        final localMessages = messagesProvider.messages
            .where(
              (m) =>
                  m.remoteId != null &&
                  (m.fromId == widget.peer.uid || m.toId == widget.peer.uid),
            )
            .toList();

        // Check if they still exist in Firebase
        for (final message in localMessages) {
          if (message.remoteId == null) continue;

          try {
            final status = await FirebaseService.getMessageStatus(
              message.remoteId!,
            );

            // If message doesn't exist in Firebase (null), delete it locally
            if (status == null) {
              await ChatService.syncMessageDeletion(message.remoteId!);

              // Remove from UI
              if (mounted) {
                messagesProvider.removeMessage(message.id);
              }
            }
          } catch (_) {
            // Skip on error
          }
        }
      } catch (_) {
        // Handle silently
      }
    });
  }

  /// Sync any missed messages before displaying chat
  Future<void> _syncMissedMessages() async {
    try {
      // First sync all undelivered messages for current user
      await ChatService.syncIncomingMessages(widget.currentUser.uid);

      // Then reload messages for this chat
      await _loadMessages(scrollToBottom: true);

      // Mark all messages from peer as delivered and read
      await _markAllPeerMessagesAsDeliveredAndRead();
    } catch (e) {
      // Handle silently
    }
  }

  /// Mark all incoming messages from peer as delivered and read
  Future<void> _markAllPeerMessagesAsDeliveredAndRead() async {
    try {
      final messages = messagesProvider.messages
          .where(
            (m) => m.fromId == widget.peer.uid && (!m.delivered || !m.read),
          )
          .toList();

      for (final message in messages) {
        await _markMessageAsDeliveredAndRead(messageId: message.id);
      }
    } catch (e) {
      // Handle silently
    }
  }

  /// Mark a single message as delivered and read
  Future<void> _markMessageAsDeliveredAndRead({
    required String messageId,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final readReceiptsEnabled =
          prefs.getBool('privacy_read_receipts') ?? true;

      // Get the message to find the sender UID and remoteId
      final message = messagesProvider.messages.firstWhere(
        (m) => m.id == messageId,
        orElse: () => messagesProvider.messages.first,
      );

      // Respect privacy setting: when read receipts are disabled, only mark delivered.
      final idToUse = message.remoteId ?? messageId;
      if (readReceiptsEnabled) {
        await ChatService.markAsDeliveredAndRead(idToUse);
      } else {
        await ChatService.markAsDelivered(idToUse);
      }

      // Update the message in the provider to reflect the changes
      if (message.id == messageId) {
        final updatedMessage = message.copyWith(
          delivered: true,
          read: readReceiptsEnabled,
        );
        messagesProvider.updateMessage(updatedMessage);
        if (mounted) setState(() {}); // Force UI rebuild
      }
    } catch (e) {
      // Handle silently
    }
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

        // Sync status from Firebase for sent messages
        await _loadMessageStatusFromFirebase(messages);

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

  /// Load message delivery/read status from Firebase for sent messages
  Future<void> _loadMessageStatusFromFirebase(
    List<MessageModel> messages,
  ) async {
    try {
      // Only check status for messages sent by current user
      final sentMessages = messages
          .where((m) => m.fromId == widget.currentUser.uid)
          .toList();

      for (final message in sentMessages) {
        try {
          final status = await FirebaseService.getMessageStatus(message.id);

          if (status != null) {
            final delivered = status['delivered'] as bool? ?? false;
            final read = status['read'] as bool? ?? false;

            if (delivered || read) {
              final updatedMessage = message.copyWith(
                delivered: delivered,
                read: read,
              );
              messagesProvider.updateMessage(updatedMessage);

              // Also update local DB
              if (delivered) {
                await LocalDBService.updateDeliveryStatus(message.id, true);
              }
              if (read) {
                await LocalDBService.updateReadStatus(message.id, true);
              }
            }
          }
        } catch (_) {
          // Silently continue if status fetch fails
        }
      }

      if (mounted) {
        setState(() {});
      }
    } catch (_) {
      // Handle silently
    }
  }

  void _sendMessage() {
    if (mediaProvider.selectedMediaFile != null) {
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
      read: false,
    );

    insertMessage(tempMessage); // Use override that includes setState()
    _messageController.clear();

    unawaited(
      ChatService.upsertLocalChatPreview(
        ownerUID: widget.currentUser.uid,
        peerUID: widget.peer.uid,
        text: text,
        timestamp: tempMessage.timestamp,
      ),
    );

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
      // Use the real message returned by ChatService instead of text matching from DB.
      final realMessage = await ChatService.sendMessage(
        fromId: widget.currentUser.uid,
        toId: widget.peer.uid,
        text: text,
      );

      if (!mounted) return;

      // Replace temp message with real message deterministically.
      messagesProvider.removeMessage(tempMessageId);
      messagesProvider.insertMessage(realMessage);
      setState(() {});
    } catch (e) {
      if (mounted) {
        removeMessage(tempMessageId); // Remove on error
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
    mediaProvider.setSelectedMediaFile(file);
  }

  @override
  void setSelectedMediaType(String? type) {
    if (!mounted) return;
    mediaProvider.setSelectedMediaType(type);
  }

  @override
  void setSelectedVideoThumbnail(Uint8List? thumbnail) {
    if (!mounted) return;
    mediaProvider.setSelectedVideoThumbnail(thumbnail);
  }

  @override
  void clearSelectedMedia() {
    if (!mounted) return;
    mediaProvider.clear();
  }

  @override
  void addUploadingMessageId(String id) {
    if (!mounted) return;
    uploadProvider.addUploadingMessageId(id);
    setState(() {});
  }

  @override
  void removeUploadingMessageId(String id) {
    if (!mounted) return;
    uploadProvider.removeUploadingMessageId(id);
    setState(() {});
  }

  @override
  void insertMessage(MessageModel message) {
    if (!mounted) return;
    messagesProvider.insertMessage(message);
    // Force immediate rebuild for instant UI update
    setState(() {});
  }

  @override
  void updateCachedAttachmentPath(String key, String path) {
    if (!mounted) return;
    uploadProvider.updateCachedAttachmentPath(key, path);
    setState(() {});
  }

  @override
  void updateVideoThumbnailPath(String key, String path) {
    if (!mounted) return;
    uploadProvider.updateVideoThumbnailPath(key, path);
    setState(() {});
  }

  @override
  void removeVideoThumbnailPath(String key) {
    if (!mounted) return;
    uploadProvider.removeVideoThumbnailPath(key);
    setState(() {});
  }

  @override
  void removeCachedAttachmentPath(String key) {
    if (!mounted) return;
    uploadProvider.removeCachedAttachmentPath(key);
    setState(() {});
  }

  @override
  void removeMessage(String id) {
    if (!mounted) return;
    messagesProvider.removeMessage(id);
    setState(() {}); // Force rebuild when message removed
  }

  @override
  void incrementVisibleCount() {
    if (!mounted) return;
    messagesProvider.incrementVisibleCount();
  }

  @override
  void decrementVisibleCount() {
    if (!mounted) return;
    messagesProvider.decrementVisibleCount();
  }

  /// Voice recording state setters
  @override
  void setIsRecordingVoice(bool value) {
    if (!mounted) return;
    recordingProvider.setIsRecording(value);
  }

  @override
  void setRecordingDuration(Duration duration) {
    if (!mounted) return;
    recordingProvider.setRecordingDuration(duration);
  }

  @override
  void setRecordingTimer(Timer? timer) {
    if (!mounted) return;
    recordingProvider.setRecordingTimer(timer);
  }

  @override
  void setRecordingSlideOffset(double offset) {
    if (!mounted) return;
    recordingProvider.setRecordingSlideOffset(offset);
  }

  @override
  void setRecordingCancelTriggered(bool value) {
    if (!mounted) return;
    recordingProvider.setRecordingCancelTriggered(value);
  }

  @override
  void setPlayingAudioMessageId(String? id) {
    if (!mounted) return;
    recordingProvider.setPlayingAudioMessageId(id);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Watch providers to rebuild when state changes
    final messagesState = context.watch<MessagesStateNotifier>();
    final recordingState = context.watch<RecordingStateNotifier>();
    final mediaState = context.watch<MediaStateNotifier>();

    final visibleMessages = messagesState.visibleMessages;

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        elevation: 1,
        shadowColor: Colors.black.withValues(alpha: 0.1),
        title: InkWell(
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => UserProfileScreen(user: widget.peer),
              ),
            );
          },
          child: Row(
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
        actions: [
          IconButton(
            icon: const Icon(Icons.call),
            onPressed: () => _initiateCall('voice'),
            tooltip: 'Voice call',
          ),
          IconButton(
            icon: const Icon(Icons.videocam),
            onPressed: () => _initiateCall('video'),
            tooltip: 'Video call',
          ),
          const SizedBox(width: 8),
        ],
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
                            child: GestureDetector(
                              onLongPress: () =>
                                  _showDeleteMessageDialog(message, mine),
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
                                      color: Colors.black.withValues(
                                        alpha: 0.08,
                                      ),
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
                                          _buildMessageStatusIcon(message),
                                        ],
                                      ],
                                    ),
                                  ],
                                ),
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
            isRecordingVoice: recordingState.isRecording,
            recordingDuration: recordingState.recordingDuration,
            recordingSlideOffset: recordingState.recordingSlideOffset,
            recordingWaveform: buildRecordingWaveform(isDark),
            selectedMediaFile: mediaState.selectedMediaFile,
            selectedMediaType: mediaState.selectedMediaType,
            selectedVideoThumbnail: mediaState.selectedVideoThumbnail,
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

  /// Build message status icon (ticks)
  /// - No icon: Message is pending/uploading (not sent yet)
  /// - Single tick: Message sent but not delivered
  /// - Double tick: Message delivered
  Widget _buildMessageStatusIcon(MessageModel message) {
    // Check if message is still pending/uploading
    final isPending =
        uploadProvider.uploadingMessageIds.contains(message.id) ||
        message.id.startsWith('temp_') ||
        message.id.startsWith('uploading_');

    if (isPending) {
      // Don't show any tick for pending messages
      return const SizedBox.shrink();
    }

    // Determine tick style based on message status:
    // - No tick: pending (handled above)
    // - Single tick: sent but not delivered
    // - Double tick (white/gray): delivered but not read
    // - Double tick (blue): delivered AND read

    if (!message.delivered) {
      // Single tick - sent but not delivered yet
      return const Icon(Icons.done, size: 14, color: Colors.white70);
    }

    // Double tick - delivered
    return Icon(
      Icons.done_all,
      size: 14,
      color: message.read
          ? Colors
                .blue // Blue when read
          : Colors.white70, // White/gray when just delivered
    );
  }

  /// Show delete options dialog
  void _showDeleteMessageDialog(MessageModel message, bool isMine) {
    // Check if message is within 5 minutes (300 seconds)
    final currentTimeMs = DateTime.now().millisecondsSinceEpoch;
    final messageTimeMs = message.timestamp;
    final diffMs = currentTimeMs - messageTimeMs;
    final isWithinFiveMinutes =
        diffMs < (5 * 60 * 1000); // 5 minutes in milliseconds

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Message'),
        content: isMine
            ? Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Delete this message for everyone or just for you?',
                  ),
                  if (!isWithinFiveMinutes)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(
                        '(Can only delete for everyone within 5 minutes)',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[600],
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ),
                ],
              )
            : const Text('Delete this message for you?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          if (isMine && isWithinFiveMinutes)
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                _deleteMessageForEveryone(message);
              },
              child: const Text(
                'Delete for Everyone',
                style: TextStyle(color: Colors.red),
              ),
            ),
          if (isMine && !isWithinFiveMinutes)
            TextButton(
              onPressed: null,
              child: Text(
                'Delete for Everyone',
                style: TextStyle(color: Colors.grey[400]),
              ),
            ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _deleteMessageForMe(message);
            },
            child: Text(
              'Delete for Me',
              style: TextStyle(color: isMine ? null : Colors.red),
            ),
          ),
        ],
      ),
    );
  }

  /// Delete message for me only
  Future<void> _deleteMessageForMe(MessageModel message) async {
    try {
      await ChatService.deleteMessageForMe(message.id);

      // Remove from provider/state
      if (mounted) {
        final messagesProvider = context.read<MessagesStateNotifier>();
        messagesProvider.removeMessage(message.id);
      }

      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Message deleted')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error deleting message: $e')));
      }
    }
  }

  /// Delete message for everyone (only if sender)
  Future<void> _deleteMessageForEveryone(MessageModel message) async {
    try {
      // Log what we're deleting
      print(
        '[ChatScreen] Deleting for everyone: id=${message.id}, remoteId=${message.remoteId}, fromId=${message.fromId}',
      );

      // Must have remoteId to delete from Firebase
      if (message.remoteId == null) {
        throw Exception('Cannot delete: message does not have a Firebase ID');
      }

      await ChatService.deleteMessageForEveryone(
        message.id,
        remoteId: message.remoteId,
        currentUserId: widget.currentUser.uid,
        messageFromId: message.fromId,
        messageTimestamp: message.timestamp,
      );

      print('[ChatScreen] Successfully deleted message for everyone');

      // Remove from provider/state
      if (mounted) {
        final messagesProvider = context.read<MessagesStateNotifier>();
        messagesProvider.removeMessage(message.id);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Message deleted for everyone')),
        );
      }
    } catch (e) {
      print('[ChatScreen] Error deleting for everyone: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }
}
