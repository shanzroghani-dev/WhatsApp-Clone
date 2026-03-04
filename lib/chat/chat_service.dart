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
    );

    await LocalDBService.saveMessageLocal(message, synced: false);
    await LocalDBService.upsertChatListEntry(
      ownerUID: fromId,
      peerUID: toId,
      lastMessage: chatListPreview ?? _chatListPreviewText(text),
      lastTimestamp: message.timestamp,
    );

    final encrypted = EncryptionService.encryptForUsers(text, fromId, toId);

    try {
      final remoteId = await FirebaseService.sendMessage(
        senderUID: fromId,
        receiverUID: toId,
        encryptedText: encrypted['cipher']!,
        iv: encrypted['iv']!,
        timestamp: message.timestamp,
        localMessageId: message.id,
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
      if (msg['senderUID'] != senderUid) continue;

      final remoteId = msg['id'] as String?;
      if (remoteId != null &&
          await LocalDBService.messageExistsByRemoteId(remoteId)) {
        continue;
      }

      final cipher = msg['text'] as String?;
      final iv = msg['iv'] as String?;
      final text = (cipher != null && iv != null)
          ? (EncryptionService.decryptForUsers(
                  cipher,
                  iv,
                  senderUid,
                  receiverUid,
                ) ??
                '[Message could not be decrypted]')
          : '[Message could not be decrypted]';

      final model = MessageModel(
        id:
            (msg['localMessageId'] as String?) ??
            (msg['id'] as String?) ??
            const Uuid().v4(),
        fromId: senderUid,
        toId: receiverUid,
        text: text,
        timestamp:
            (msg['timestamp'] as int?) ?? DateTime.now().millisecondsSinceEpoch,
        delivered: true,
      );

      await LocalDBService.saveMessageLocal(
        model,
        synced: true,
        remoteId: remoteId,
      );

      if (remoteId != null) {
        await FirebaseService.markAsDelivered(receiverUid, remoteId);
      }
      yield model;
    }
  }

  static Future<void> markAsDelivered(
    String receiverUID,
    String messageId,
  ) async {
    await FirebaseService.markAsDelivered(receiverUID, messageId);
  }

  static Future<void> deleteMessage(String messageId) async {
    await LocalDBService.deleteMessage(messageId);
  }

  static Future<void> deleteConversation(String userId1, String userId2) async {
    await LocalDBService.deleteConversation(userId1, userId2);
    await LocalDBService.removeChatListEntry(userId1, userId2);
  }

  static Future<void> cleanupOldMessages(String receiverUID) async {
    await LocalDBService.deleteOldLocalMessages();
    final cutoff = DateTime.now()
        .subtract(const Duration(hours: 24))
        .millisecondsSinceEpoch;
    await FirebaseService.deleteOldMessagesInCloud(receiverUID, cutoff);
  }

  static Future<void> syncPendingOutgoing() async {
    final queue = await LocalDBService.getOutgoingQueue();
    for (final item in queue) {
      try {
        final remoteId = await FirebaseService.sendMessage(
          senderUID: item['senderUID'] as String,
          receiverUID: item['receiverUID'] as String,
          encryptedText: item['cipher'] as String,
          iv: item['iv'] as String,
          timestamp: item['timestamp'] as int,
          localMessageId: item['localMessageId'] as String,
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

  static Future<int> getMessageCount(String userId1, String userId2) async {
    return LocalDBService.getMessageCount(userId1, userId2);
  }

  static Stream<MessageModel> streamIncomingForUser(String receiverUid) async* {
    await for (final msg in FirebaseService.listenForIncomingMessages(
      receiverUid,
    )) {
      final senderUid = msg['senderUID'] as String?;
      if (senderUid == null || senderUid.isEmpty) continue;

      final remoteId = msg['id'] as String?;
      if (remoteId != null &&
          await LocalDBService.messageExistsByRemoteId(remoteId)) {
        continue;
      }

      final cipher = msg['text'] as String?;
      final iv = msg['iv'] as String?;
      final text = (cipher != null && iv != null)
          ? (EncryptionService.decryptForUsers(
                  cipher,
                  iv,
                  senderUid,
                  receiverUid,
                ) ??
                '[Message could not be decrypted]')
          : '[Message could not be decrypted]';

      final timestamp =
          (msg['timestamp'] as int?) ?? DateTime.now().millisecondsSinceEpoch;
      final model = MessageModel(
        id:
            (msg['localMessageId'] as String?) ??
            (msg['id'] as String?) ??
            const Uuid().v4(),
        fromId: senderUid,
        toId: receiverUid,
        text: text,
        timestamp: timestamp,
        delivered: true,
      );

      await LocalDBService.saveMessageLocal(
        model,
        synced: true,
        remoteId: remoteId,
      );
      await LocalDBService.upsertChatListEntry(
        ownerUID: receiverUid,
        peerUID: senderUid,
        lastMessage: _chatListPreviewText(text),
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
        await FirebaseService.markAsDelivered(receiverUid, remoteId);
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
}
