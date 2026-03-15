import 'dart:convert';
import 'dart:typed_data';

import 'package:firebase_storage/firebase_storage.dart';
import 'package:uuid/uuid.dart';
import 'package:whatsapp_clone/core/encryption_service.dart';
import 'package:whatsapp_clone/core/firebase_service.dart';
import 'package:whatsapp_clone/core/local_db_service.dart';
import 'package:whatsapp_clone/models/message_model.dart';
import 'package:whatsapp_clone/models/user_model.dart';

class ChatService {
  static const String attachmentPrefix = '[ATTACHMENT]';
  static const int maxAttachmentBytes = 10 * 1024 * 1024;

  static Future<void> initialize() async {
    final key = EncryptionService.generateKey();
    await EncryptionService.initialize(key);
  }

  static bool isAttachmentMessage(String text) {
    return text.startsWith(attachmentPrefix);
  }

  static Map<String, dynamic>? parseAttachmentPayload(String text) {
    if (!isAttachmentMessage(text)) return null;
    try {
      final payload = text.substring(attachmentPrefix.length);
      final decoded = jsonDecode(payload);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  static String _chatListPreviewText(String text) {
    final attachment = parseAttachmentPayload(text);
    if (attachment == null) return text;
    final type = (attachment['type'] as String?) ?? 'file';
    switch (type) {
      case 'image':
        return '📷 Photo';
      case 'video':
        return '🎥 Video';
      case 'audio':
        return '🎤 Voice message';
      default:
        return '📎 Attachment';
    }
  }

  static Future<MessageModel> sendMessage({
    required String fromId,
    required String toId,
    required String text,
    String? chatListPreview,
  }) async {
    if (text.trim().isEmpty) {
      throw Exception('Message cannot be empty');
    }

    final message = MessageModel(
      id: const Uuid().v4(),
      fromId: fromId,
      toId: toId,
      text: text,
      timestamp: DateTime.now().millisecondsSinceEpoch,
      delivered: false,
      read: false,
    );

    await LocalDBService.saveMessageLocal(message, synced: false);
    await LocalDBService.upsertChatListEntry(
      ownerUID: fromId,
      peerUID: toId,
      lastMessage: chatListPreview ?? _chatListPreviewText(text),
      lastTimestamp: message.timestamp,
    );

    final encrypted = EncryptionService.encryptForUsers(text, fromId, toId);

    // Fetch sender name and receiver FCM token for notification
    String? senderName;
    String? receiverFcmToken;
    String? messageType;
    try {
      final senderProfile = await FirebaseService.getUserByUid(fromId);
      senderName = senderProfile?.displayName;

      final receiverProfile = await FirebaseService.getUserByUid(toId);
      receiverFcmToken = receiverProfile?.fcmToken;

      // Detect message type from attachment prefix
      if (isAttachmentMessage(text)) {
        final attachment = parseAttachmentPayload(text);
        messageType = attachment?['type'] as String?;
      }
    } catch (_) {
      // Continue even if profile fetch fails
    }

    try {
      final remoteId = await FirebaseService.sendMessage(
        senderUID: fromId,
        receiverUID: toId,
        encryptedText: encrypted['cipher']!,
        iv: encrypted['iv']!,
        timestamp: message.timestamp,
        localMessageId: message.id,
        senderName: senderName,
        receiverFcmToken: receiverFcmToken,
        messageType: messageType,
      );
      await LocalDBService.markOutgoingSynced(message.id, remoteId: remoteId);
    } catch (_) {
      await LocalDBService.queueOutgoingMessage(
        localMessageId: message.id,
        senderUID: fromId,
        receiverUID: toId,
        cipher: encrypted['cipher']!,
        iv: encrypted['iv']!,
        timestamp: message.timestamp,
      );
    }

    return message;
  }

  static Future<MessageModel> sendMediaAttachment({
    required String fromId,
    required String toId,
    required String mediaType,
    required Uint8List bytes,
    required String fileName,
    required String contentType,
    String? caption,
  }) async {
    if (mediaType != 'image' && mediaType != 'video') {
      throw Exception('Unsupported attachment type');
    }
    if (bytes.length > maxAttachmentBytes) {
      throw Exception('Attachment exceeds 10MB limit');
    }

    final sanitizedFileName = fileName.replaceAll(
      RegExp(r'[^a-zA-Z0-9._-]'),
      '_',
    );
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final path =
        'chat_attachments/$mediaType/$fromId/$toId/${timestamp}_$sanitizedFileName';

    final ref = FirebaseStorage.instance.ref(path);
    await ref.putData(
      bytes,
      SettableMetadata(
        contentType: contentType,
        customMetadata: {
          'fromId': fromId,
          'toId': toId,
          'mediaType': mediaType,
        },
      ),
    );
    final downloadUrl = await ref.getDownloadURL();

    final payload = jsonEncode({
      'type': mediaType,
      'url': downloadUrl,
      'name': sanitizedFileName,
      'storagePath': path,
      'sizeBytes': bytes.length,
      if (caption != null && caption.isNotEmpty) 'caption': caption,
    });

    return sendMessage(
      fromId: fromId,
      toId: toId,
      text: '$attachmentPrefix$payload',
      chatListPreview: caption != null && caption.isNotEmpty
          ? caption
          : (mediaType == 'image' ? '📷 Photo' : '🎥 Video'),
    );
  }

  static Future<MessageModel> sendVoiceAttachment({
    required String fromId,
    required String toId,
    required Uint8List bytes,
    required String fileName,
    required int durationMs,
    String? caption,
  }) async {
    if (bytes.length > maxAttachmentBytes) {
      throw Exception('Attachment exceeds 10MB limit');
    }

    final sanitizedFileName = fileName.replaceAll(
      RegExp(r'[^a-zA-Z0-9._-]'),
      '_',
    );
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final path =
        'chat_attachments/audio/$fromId/$toId/${timestamp}_$sanitizedFileName';

    final ref = FirebaseStorage.instance.ref(path);
    await ref.putData(
      bytes,
      SettableMetadata(
        contentType: 'audio/mp4',
        customMetadata: {
          'fromId': fromId,
          'toId': toId,
          'mediaType': 'audio',
          'durationMs': durationMs.toString(),
        },
      ),
    );
    final downloadUrl = await ref.getDownloadURL();

    final payload = jsonEncode({
      'type': 'audio',
      'url': downloadUrl,
      'name': sanitizedFileName,
      'storagePath': path,
      'sizeBytes': bytes.length,
      'durationMs': durationMs,
      if (caption != null && caption.isNotEmpty) 'caption': caption,
    });

    return sendMessage(
      fromId: fromId,
      toId: toId,
      text: '$attachmentPrefix$payload',
      chatListPreview: '🎤 Voice message',
    );
  }

  static Future<Uint8List> downloadAttachmentAndDeleteFromStorage(
    Map<String, dynamic> attachment, {
    bool deleteAfterDownload = false,
  }) async {
    final url = attachment['url'] as String?;
    final storagePath = attachment['storagePath'] as String?;

    if ((url == null || url.isEmpty) &&
        (storagePath == null || storagePath.isEmpty)) {
      throw Exception('Attachment URL/path missing');
    }

    final ref = (storagePath != null && storagePath.isNotEmpty)
        ? FirebaseStorage.instance.ref(storagePath)
        : FirebaseStorage.instance.refFromURL(url!);

    final bytes = await ref.getData(maxAttachmentBytes);
    if (bytes == null) {
      throw Exception('Could not download attachment');
    }

    if (deleteAfterDownload) {
      try {
        await ref.delete();
      } catch (_) {}
    }

    return bytes;
  }

  static Future<List<MessageModel>> getMessagesBetween(
    String userId1,
    String userId2,
  ) async {
    return LocalDBService.messagesBetween(userId1, userId2);
  }

  static Stream<MessageModel> streamMessagesBetween(
    String senderUid,
    String receiverUid,
  ) async* {
    await for (final msg in FirebaseService.listenForIncomingMessages(
      receiverUid,
    )) {
      final incomingSenderUid =
          (msg['fromId'] as String?) ?? (msg['senderUID'] as String?);
      if (incomingSenderUid == null || incomingSenderUid != senderUid) continue;

      final remoteId = msg['id'] as String?;
      if (remoteId != null &&
          await LocalDBService.messageExistsByRemoteId(remoteId)) {
        continue;
      }

      final model = _parseMessageFromFirebase(
        msg: msg,
        senderUid: senderUid,
        receiverUid: receiverUid,
      );

      await LocalDBService.saveMessageLocal(
        model,
        synced: true,
        remoteId: remoteId,
      );

      if (remoteId != null) {
        await FirebaseService.markAsDelivered(remoteId);
      }
      yield model;
    }
  }

  static Future<void> markAsDelivered(String messageId) async {
    await FirebaseService.markAsDelivered(messageId);
    try {
      await LocalDBService.updateDeliveryStatus(messageId, true);
    } catch (_) {}
  }

  static Future<void> markAsRead(String messageId) async {
    await FirebaseService.markAsRead(messageId);
    try {
      await LocalDBService.updateReadStatus(messageId, true);
    } catch (_) {}
  }

  /// Mark message as both delivered and read, and sync status back to sender
  static Future<void> markAsDeliveredAndRead(String messageId) async {
    await FirebaseService.markAsDelivered(messageId);
    await FirebaseService.markAsRead(messageId);
    try {
      await LocalDBService.updateDeliveryStatus(messageId, true);
      await LocalDBService.updateReadStatus(messageId, true);
    } catch (_) {}
  }

  /// Helper: Decrypt message text from Firebase data
  static String _decryptMessageText({
    required String? cipher,
    required String? iv,
    required String senderUid,
    required String receiverUid,
  }) {
    if (cipher == null || iv == null) {
      return '[Message could not be decrypted]';
    }
    return EncryptionService.decryptForUsers(
          cipher,
          iv,
          senderUid,
          receiverUid,
        ) ??
        '[Message could not be decrypted]';
  }

  /// Helper: Parse message model from Firebase data
  static MessageModel _parseMessageFromFirebase({
    required Map<String, dynamic> msg,
    required String senderUid,
    required String receiverUid,
  }) {
    final remoteId = msg['id'] as String?;
    final cipher = msg['text'] as String?;
    final iv = msg['iv'] as String?;
    final text = _decryptMessageText(
      cipher: cipher,
      iv: iv,
      senderUid: senderUid,
      receiverUid: receiverUid,
    );
    final timestamp =
        (msg['timestamp'] as int?) ?? DateTime.now().millisecondsSinceEpoch;

    return MessageModel(
      id: (msg['localMessageId'] as String?) ?? const Uuid().v4(),
      remoteId: remoteId,
      fromId: senderUid,
      toId: receiverUid,
      text: text,
      timestamp: timestamp,
      delivered: true,
      read: (msg['read'] as bool?) ?? false,
    );
  }

  /// Update message status in local database
  static Future<void> updateMessageStatus(
    String messageId,
    bool delivered,
    bool read,
  ) async {
    try {
      if (delivered) {
        await LocalDBService.updateDeliveryStatus(messageId, true);
        await LocalDBService.updateDeliveryStatusByRemoteId(messageId, true);
      }
      if (read) {
        await LocalDBService.updateReadStatus(messageId, true);
        await LocalDBService.updateReadStatusByRemoteId(messageId, true);
      }
    } catch (_) {
      // Ignore if message doesn't exist locally
    }
  }

  /// Delete message from local database only (Delete for me)
  static Future<void> deleteMessageForMe(String messageId) async {
    await LocalDBService.deleteMessage(messageId);
  }

  /// Delete message from Firebase and local database (Delete for everyone)
  /// Only the sender can delete for everyone
  static Future<void> deleteMessageForEveryone(
    String messageId, {
    String? remoteId,
    required String currentUserId,
    required String messageFromId,
    int? messageTimestamp,
  }) async {
    // Permission check: Only sender can delete for everyone
    if (currentUserId != messageFromId) {
      throw Exception('Only the sender can delete this message for everyone');
    }

    // Time check: Message must be within 5 minutes to delete for everyone
    if (messageTimestamp != null) {
      final currentTimeMs = DateTime.now().millisecondsSinceEpoch;
      final diffMs = currentTimeMs - messageTimestamp;
      final fiveMinutesMs = 5 * 60 * 1000;

      if (diffMs > fiveMinutesMs) {
        throw Exception(
          'Messages can only be deleted for everyone within 5 minutes of sending',
        );
      }
    }

    // Must have remoteId to delete from Firebase
    if (remoteId == null || remoteId.isEmpty) {
      throw Exception(
        'Cannot delete: message does not have a Firebase ID (remoteId is null)',
      );
    }

    print(
      '[ChatService] Deleting for everyone: messageId=$messageId, remoteId=$remoteId',
    );

    // Delete from Firebase using remoteId
    try {
      await FirebaseService.deleteMessageFromCloud(remoteId);
      print('[ChatService] ✓ Deleted from Firebase: $remoteId');
    } catch (e) {
      print('[ChatService] ✗ Error deleting from Firebase: $e');
      rethrow;
    }

    // Delete from local database
    try {
      await LocalDBService.deleteMessage(messageId);
      print('[ChatService] ✓ Deleted from local DB: $messageId');

      // Also delete by remoteId if different
      if (remoteId != messageId) {
        await LocalDBService.deleteMessageByRemoteId(remoteId);
        print('[ChatService] ✓ Deleted by remoteId: $remoteId');
      }
    } catch (e) {
      print('[ChatService] ✗ Error deleting locally: $e');
      rethrow;
    }
  }

  /// Legacy method - defaults to "Delete for me"
  @Deprecated('Use deleteMessageForMe or deleteMessageForEveryone instead')
  static Future<void> deleteMessage(String messageId) async {
    await deleteMessageForMe(messageId);
  }

  /// Delete entire conversation from local database only (Delete for me)
  static Future<void> deleteConversationForMe(
    String userId1,
    String userId2,
  ) async {
    await LocalDBService.deleteConversation(userId1, userId2);
    await LocalDBService.removeChatListEntry(userId1, userId2);
  }

  /// Delete entire conversation from Firebase and local database (Delete for everyone)
  static Future<void> deleteConversationForEveryone(
    String userId1,
    String userId2,
  ) async {
    try {
      await FirebaseService.deleteConversationFromCloud(userId1, userId2);
      print('[ChatService] Deleted conversation from cloud');
    } catch (e) {
      print('[ChatService] Error deleting conversation from cloud: $e');
      rethrow;
    }

    await LocalDBService.deleteConversation(userId1, userId2);
    await LocalDBService.removeChatListEntry(userId1, userId2);
  }

  /// Legacy method - defaults to "Delete for me"
  @Deprecated(
    'Use deleteConversationForMe or deleteConversationForEveryone instead',
  )
  static Future<void> deleteConversation(String userId1, String userId2) async {
    await deleteConversationForMe(userId1, userId2);
  }

  static Future<void> upsertLocalChatPreview({
    required String ownerUID,
    required String peerUID,
    required String text,
    int? timestamp,
  }) async {
    final resolvedTimestamp =
        timestamp ?? DateTime.now().millisecondsSinceEpoch;
    await LocalDBService.upsertChatListEntry(
      ownerUID: ownerUID,
      peerUID: peerUID,
      lastMessage: _chatListPreviewText(text),
      lastTimestamp: resolvedTimestamp,
    );
  }

  static Future<void> cleanupOldMessages(String receiverUID) async {
    await LocalDBService.deleteOldLocalMessages();
    final cutoff = DateTime.now()
        .subtract(const Duration(hours: 24))
        .millisecondsSinceEpoch;
    await FirebaseService.deleteOldMessagesInCloud(cutoff);
  }

  static Future<void> syncPendingOutgoing() async {
    final queue = await LocalDBService.getOutgoingQueue();
    for (final item in queue) {
      try {
        // Fetch notification metadata for retry
        String? senderName;
        String? receiverFcmToken;
        try {
          final senderProfile = await FirebaseService.getUserByUid(
            item['senderUID'] as String,
          );
          senderName = senderProfile?.displayName;

          final receiverProfile = await FirebaseService.getUserByUid(
            item['receiverUID'] as String,
          );
          receiverFcmToken = receiverProfile?.fcmToken;
        } catch (_) {
          // Continue even if profile fetch fails
        }

        final remoteId = await FirebaseService.sendMessage(
          senderUID: item['senderUID'] as String,
          receiverUID: item['receiverUID'] as String,
          encryptedText: item['cipher'] as String,
          iv: item['iv'] as String,
          timestamp: item['timestamp'] as int,
          localMessageId: item['localMessageId'] as String,
          senderName: senderName,
          receiverFcmToken: receiverFcmToken,
        );
        await LocalDBService.markOutgoingSynced(
          item['localMessageId'] as String,
          remoteId: remoteId,
        );
      } catch (_) {
        await LocalDBService.incrementOutgoingRetry(
          item['localMessageId'] as String,
        );
      }
    }
  }

  /// Sync undelivered incoming messages (fetch missed messages)
  static Future<void> syncIncomingMessages(String receiverUid) async {
    try {
      final undelivered = await FirebaseService.getUndeliveredMessages(
        receiverUid,
      );

      for (final msg in undelivered) {
        final senderUid =
            (msg['fromId'] as String?) ?? (msg['senderUID'] as String?);
        if (senderUid == null || senderUid.isEmpty) continue;

        final remoteId = msg['id'] as String?;
        if (remoteId != null &&
            await LocalDBService.messageExistsByRemoteId(remoteId)) {
          await FirebaseService.markAsDelivered(remoteId);
          continue;
        }

        final model = _parseMessageFromFirebase(
          msg: msg,
          senderUid: senderUid,
          receiverUid: receiverUid,
        );
        final timestamp = model.timestamp;

        await LocalDBService.saveMessageLocal(
          model,
          synced: true,
          remoteId: remoteId,
        );
        await LocalDBService.upsertChatListEntry(
          ownerUID: receiverUid,
          peerUID: senderUid,
          lastMessage: _chatListPreviewText(model.text),
          lastTimestamp: timestamp,
        );

        if (remoteId != null) {
          await FirebaseService.markAsDelivered(remoteId);
        }
      }
    } catch (e) {
      print('Error syncing incoming messages: $e');
    }
  }

  static Future<int> getMessageCount(String userId1, String userId2) async {
    return LocalDBService.getMessageCount(userId1, userId2);
  }

  static Stream<MessageModel> streamIncomingForUser(String receiverUid) async* {
    await for (final msg in FirebaseService.listenForIncomingMessages(
      receiverUid,
    )) {
      final senderUid =
          (msg['fromId'] as String?) ?? (msg['senderUID'] as String?);
      if (senderUid == null || senderUid.isEmpty) continue;

      final remoteId = msg['id'] as String?;
      if (remoteId != null &&
          await LocalDBService.messageExistsByRemoteId(remoteId)) {
        continue;
      }

      final model = _parseMessageFromFirebase(
        msg: msg,
        senderUid: senderUid,
        receiverUid: receiverUid,
      );
      final timestamp = model.timestamp;

      await LocalDBService.saveMessageLocal(
        model,
        synced: true,
        remoteId: remoteId,
      );
      await LocalDBService.upsertChatListEntry(
        ownerUID: receiverUid,
        peerUID: senderUid,
        lastMessage: _chatListPreviewText(model.text),
        lastTimestamp: timestamp,
      );

      try {
        final senderProfile = await FirebaseService.getUserProfileMap(
          senderUid,
        );
        if (senderProfile != null) {
          await LocalDBService.cacheUserProfile(
            UserModel.fromJson(senderProfile),
          );
        }
      } catch (_) {}

      if (remoteId != null) {
        await FirebaseService.markAsDelivered(remoteId);
      }

      yield model;
    }
  }

  static Future<List<Map<String, dynamic>>> getLocalChatList(
    String ownerUid,
  ) async {
    return LocalDBService.getChatListEntries(ownerUid);
  }

  static Future<bool> isMessagingAvailable() async {
    try {
      await LocalDBService.init();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Sync deletion: Remove message from local DB if it no longer exists in Firebase
  static Future<void> syncMessageDeletion(String remoteId) async {
    try {
      await LocalDBService.deleteMessageByRemoteId(remoteId);
      print('[ChatService] Synced deletion of message: $remoteId');
    } catch (e) {
      print('[ChatService] Error syncing deletion: $e');
    }
  }
}
