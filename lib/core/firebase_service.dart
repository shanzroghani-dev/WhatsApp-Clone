import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:whatsapp_clone/core/constants.dart';
import 'package:whatsapp_clone/models/user_model.dart';

class _CachedUserProfile {
  final Map<String, dynamic> data;
  final DateTime cachedAt;

  _CachedUserProfile(this.data, this.cachedAt);

  bool isExpired() {
    return DateTime.now().difference(cachedAt).inHours >= 6;
  }
}

class FirebaseService {
  static final FirebaseAuth _auth = FirebaseAuth.instance;
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static final FirebaseDatabase _realtimeDb = FirebaseDatabase.instance;
  static final Random _random = Random();
  static final Map<String, _CachedUserProfile> _userProfileCache = {};

  static Future<UserModel> registerUser({
    required String email,
    required String password,
    String? displayName,
    String? publicKey,
  }) async {
    print('[REGISTER] Starting registration for email: $email');

    // Create Firebase Auth user
    String uid;
    try {
      final userCred = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
      uid = userCred.user!.uid;
      print('[REGISTER] Firebase Auth user created with UID: $uid');
    } catch (e) {
      // Firebase Auth plugin sometimes has type casting errors even when backend succeeds
      // Fall back to currentUser which should be populated if backend succeeded
      print('[REGISTER] createUserWithEmailAndPassword error: $e');
      print('[REGISTER] Checking currentUser as fallback...');
      final currentUser = _auth.currentUser;
      if (currentUser != null) {
        uid = currentUser.uid;
        print('[REGISTER] ✓ Using currentUser UID: $uid');
      } else {
        print('[REGISTER] ✗ currentUser is null, registration failed');
        rethrow;
      }
    }

    String? assignedNumber;

    try {
      // Try up to 25 times to find a unique number
      for (var attempt = 0; attempt < 25; attempt++) {
        final candidateNumber = _generateCandidateUserNumber();
        print('[REGISTER] Attempt $attempt: Trying number $candidateNumber');

        try {
          // Check if this number already exists (outside transaction)
          final existingDocs = await _firestore
              .collection(AppConstants.usersCollection)
              .where('uniqueNumber', isEqualTo: candidateNumber)
              .limit(1)
              .get();

          if (existingDocs.docs.isNotEmpty) {
            print(
              '[REGISTER] Number $candidateNumber already exists, retrying...',
            );
            continue;
          }

          // Number is unique, write the user document
          final resolvedDisplayName = displayName?.trim().isNotEmpty == true
              ? displayName!.trim()
              : 'User ${candidateNumber.substring(candidateNumber.length - 4)}';

          final userData = {
            'uid': uid,
            'uniqueNumber': candidateNumber,
            'email': email,
            'displayName': resolvedDisplayName,
            'profilePic': '',
            'status': 'Available',
            'publicKey': publicKey ?? '',
            'isOnline': false,
            'lastSeen': FieldValue.serverTimestamp(),
            'createdAt': FieldValue.serverTimestamp(),
            'lastUpdated': FieldValue.serverTimestamp(),
          };

          print('[REGISTER] Writing user doc to Firestore...');
          await _firestore
              .collection(AppConstants.usersCollection)
              .doc(uid)
              .set(userData);

          print('[REGISTER] ✓ User document created successfully!');
          print('[REGISTER] ✓ Assigned unique number: $candidateNumber');
          assignedNumber = candidateNumber;
          break;
        } catch (e) {
          print('[REGISTER] Error on attempt $attempt: $e');
          if (attempt == 24) {
            print('[REGISTER] All 25 attempts failed!');
            rethrow;
          }
        }
      }

      if (assignedNumber == null) {
        throw Exception('Could not assign unique number after 25 attempts');
      }
    } catch (e) {
      print('[REGISTER] Fatal error during registration: $e');
      print('[REGISTER] Deleting Firebase Auth user...');
      try {
        final currentUser = _auth.currentUser;
        if (currentUser != null) {
          await currentUser.delete();
          print('[REGISTER] ✓ Firebase Auth user deleted');
        }
      } catch (deleteError) {
        print('[REGISTER] Could not delete user: $deleteError');
      }
      rethrow;
    }

    final user = UserModel(
      uid: uid,
      uniqueNumber: assignedNumber,
      email: email,
      displayName: displayName?.trim().isNotEmpty == true
          ? displayName!.trim()
          : 'User ${assignedNumber.substring(assignedNumber.length - 4)}',
      profilePic: '',
      status: 'Available',
      publicKey: publicKey ?? '',
      isOnline: false,
      lastSeen: DateTime.now(),
      createdAt: DateTime.now(),
      lastUpdated: DateTime.now(),
    );

    print('[REGISTER] Registration complete! Returning user model.');
    return user;
  }

  static Future<UserModel> loginUser({
    required String email,
    required String password,
  }) async {
    final userCred = await _auth.signInWithEmailAndPassword(
      email: email,
      password: password,
    );

    final uid = userCred.user!.uid;
    final userData = await getUserProfileMap(uid);
    if (userData == null) {
      throw Exception('User profile not found');
    }

    await updatePresence(uid, true);
    return UserModel.fromJson(userData);
  }

  static Future<UserModel?> getCurrentUser() async {
    final user = _auth.currentUser;
    if (user == null) return null;

    final userData = await getUserProfileMap(user.uid);
    if (userData == null) return null;

    return UserModel.fromJson(userData);
  }

  static Future<void> logoutUser() async {
    final current = _auth.currentUser;
    if (current != null) {
      await updatePresence(current.uid, false);
    }
    await _auth.signOut();
  }

  static Future<Map<String, dynamic>?> getUserProfileMap(String uid) async {
    // Check cache first
    if (_userProfileCache.containsKey(uid)) {
      final cached = _userProfileCache[uid]!;
      if (!cached.isExpired()) {
        return cached.data;
      } else {
        _userProfileCache.remove(uid);
      }
    }

    // Fetch from Firestore
    final doc = await _firestore
        .collection(AppConstants.usersCollection)
        .doc(uid)
        .get();

    if (!doc.exists) return null;

    final data = doc.data()!;
    // Cache the result for 6 hours
    _userProfileCache[uid] = _CachedUserProfile(data, DateTime.now());

    return data;
  }

  static Future<UserModel?> getUserByUid(String uid) async {
    final data = await getUserProfileMap(uid);
    if (data == null) return null;
    return UserModel.fromJson(data);
  }

  static Future<UserModel?> getUserByNumberAsModel(String number) async {
    try {
      final query = await _firestore
          .collection(AppConstants.usersCollection)
          .where('uniqueNumber', isEqualTo: number.trim())
          .limit(1)
          .get();

      if (query.docs.isEmpty) return null;
      return UserModel.fromJson(query.docs.first.data());
    } catch (e) {
      print('[SEARCH] Error searching by unique number: $e');
      return null;
    }
  }

  static String _generateCandidateUserNumber() {
    // Generate unique number with format: 0380 + 7 random digits
    // Example: 03809050650
    final buffer = StringBuffer('0380');
    for (var i = 0; i < 7; i++) {
      buffer.write(_random.nextInt(10));
    }
    return buffer.toString();
  }

  static Future<UserModel?> searchUserByEmailOrNumber(String input) async {
    final queryText = input.trim();
    if (queryText.isEmpty) return null;

    try {
      // If input doesn't contain @, treat as unique number
      if (!queryText.contains('@')) {
        return await getUserByNumberAsModel(queryText);
      }

      // Search by email
      final query = await _firestore
          .collection(AppConstants.usersCollection)
          .where('email', isEqualTo: queryText)
          .limit(1)
          .get();

      if (query.docs.isEmpty) return null;
      return UserModel.fromJson(query.docs.first.data());
    } catch (e) {
      print('[SEARCH] Error searching user: $e');
      return null;
    }
  }

  static Future<List<UserModel>> getAllUsersAsModels() async {
    final query = await _firestore
        .collection(AppConstants.usersCollection)
        .get();
    return query.docs.map((doc) => UserModel.fromJson(doc.data())).toList();
  }

  static Future<void> updateUserProfile({
    required String uid,
    String? displayName,
    String? profilePicUrl,
    String? status,
    String? publicKey,
    String? fcmToken,
  }) async {
    final data = <String, dynamic>{'lastUpdated': FieldValue.serverTimestamp()};
    if (displayName != null) data['displayName'] = displayName;
    if (profilePicUrl != null) data['profilePic'] = profilePicUrl;
    if (status != null) data['status'] = status;
    if (publicKey != null) data['publicKey'] = publicKey;
    if (fcmToken != null) data['fcmToken'] = fcmToken;

    await _firestore
        .collection(AppConstants.usersCollection)
        .doc(uid)
        .update(data);
  }

  static Future<void> updatePresence(String uid, bool isOnline) async {
    try {
      await _firestore
          .collection(AppConstants.usersCollection)
          .doc(uid)
          .update({
            'isOnline': isOnline,
            'lastSeen': FieldValue.serverTimestamp(),
            'lastUpdated': FieldValue.serverTimestamp(),
          });
    } catch (e) {
      // Silently fail if permission denied or network error
      print('updatePresence error (silently ignored): $e');
    }
  }

  static Future<String?> getUserPublicKey(String uid) async {
    final data = await getUserProfileMap(uid);
    return data?['publicKey'] as String?;
  }

  static Future<String> sendMessage({
    required String senderUID,
    required String receiverUID,
    required String encryptedText,
    required String iv,
    required int timestamp,
    required String localMessageId,
    String? senderName,
    String? receiverFcmToken,
    String? messageType,
  }) async {
    // Use flat structure: messages/{messageId}
    // Always create NEW message with Firebase auto-generated key
    final messageRef = _realtimeDb.ref('messages').push();
    final remoteId =
        messageRef.key!; // Force auto-generated key, never use localMessageId

    final payload = {
      'messageId': remoteId,
      'localMessageId': localMessageId,
      'fromId': senderUID,
      'toId': receiverUID,
      'text': encryptedText,
      'iv': iv,
      'timestamp': timestamp,
      'delivered': false,
      'read': false,
    };

    // Include notification metadata to avoid Firestore reads in Cloud Function
    if (senderName != null) payload['senderName'] = senderName;
    if (receiverFcmToken != null)
      payload['receiverFcmToken'] = receiverFcmToken;
    if (messageType != null) payload['type'] = messageType;

    // Write to flat messages structure - ONLY with messageId key
    await messageRef.set(payload);

    return remoteId;
  }

  static Stream<Map<String, dynamic>> listenForIncomingMessages(
    String receiverUID,
  ) {
    // Query flat structure by toId
    return _realtimeDb
        .ref('messages')
        .orderByChild('toId')
        .equalTo(receiverUID)
        .onChildAdded
        .map((event) {
          final value = event.snapshot.value;
          if (value is! Map) {
            return <String, dynamic>{};
          }
          final msg = value.cast<String, dynamic>();
          // Only include undelivered messages
          if (msg['delivered'] != true) {
            return {'id': event.snapshot.key, ...msg};
          }
          return <String, dynamic>{};
        })
        .where((event) => event.isNotEmpty);
  }

  /// Fetch all undelivered messages (for syncing on startup)
  static Future<List<Map<String, dynamic>>> getUndeliveredMessages(
    String receiverUID,
  ) async {
    // Query flat structure by toId
    final snapshot = await _realtimeDb
        .ref('messages')
        .orderByChild('toId')
        .equalTo(receiverUID)
        .get();

    if (!snapshot.exists || snapshot.value is! Map) {
      return [];
    }

    final messages = <Map<String, dynamic>>[];
    final data = snapshot.value as Map;

    for (final entry in data.entries) {
      if (entry.value is Map) {
        final msg = Map<String, dynamic>.from(entry.value as Map);
        // Only include undelivered messages
        if (msg['delivered'] != true) {
          msg['id'] = entry.key;
          messages.add(msg);
        }
      }
    }

    return messages;
  }

  static Future<void> markAsDelivered(String messageId) async {
    // Update flat structure with timestamp
    final now = DateTime.now().millisecondsSinceEpoch;
    await _realtimeDb.ref('messages/$messageId').update({
      'delivered': true,
      'deliveredAt': now,
    });
  }

  static Future<void> markAsRead(String messageId) async {
    // Update flat structure with timestamp
    final now = DateTime.now().millisecondsSinceEpoch;
    await _realtimeDb.ref('messages/$messageId').update({
      'read': true,
      'readAt': now,
    });
  }

  /// Listen for message status updates (delivered/read changes) on sent messages
  static Stream<Map<String, dynamic>> listenForStatusUpdates(
    String currentUserUID,
  ) {
    // Query flat structure by fromId
    return _realtimeDb
        .ref('messages')
        .orderByChild('fromId')
        .equalTo(currentUserUID)
        .onChildChanged
        .map((event) {
          final value = event.snapshot.value;
          if (value is! Map) {
            return <String, dynamic>{};
          }
          final msg = value.cast<String, dynamic>();
          msg['messageId'] = event.snapshot.key;
          return msg;
        })
        .where((event) => event.isNotEmpty);
  }

  /// Get current message status directly from the message
  static Future<Map<String, dynamic>?> getMessageStatus(
    String messageId,
  ) async {
    try {
      // Query flat structure by messageId only
      final snapshot = await _realtimeDb.ref('messages/$messageId').get();

      if (!snapshot.exists || snapshot.value is! Map) {
        return null;
      }

      final msg = Map<String, dynamic>.from(snapshot.value as Map);
      msg['messageId'] = messageId;
      return msg;
    } catch (e) {
      print('[Firebase] Error fetching message status: $e');
      return null;
    }
  }

  static Future<void> deleteOldMessagesInCloud(int cutoffTime) async {
    // Query flat structure
    final snapshot = await _realtimeDb
        .ref('messages')
        .orderByChild('timestamp')
        .endBefore(cutoffTime)
        .get();

    if (!snapshot.exists || snapshot.value is! Map) return;

    final messagesMap = Map<dynamic, dynamic>.from(snapshot.value as Map);
    for (final messageEntry in messagesMap.entries) {
      final messageId = messageEntry.key?.toString();
      if (messageId == null) continue;

      try {
        await _realtimeDb.ref('messages/$messageId').remove();
      } catch (e) {
        print('[Firebase] Error deleting message $messageId: $e');
      }
    }
  }

  /// Delete a single message from Firebase (for everyone)
  static Future<void> deleteMessageFromCloud(String messageId) async {
    try {
      await _realtimeDb.ref('messages/$messageId').remove();
      print('[Firebase] ✓ Deleted message $messageId');
    } catch (e) {
      print('[Firebase] Error deleting message $messageId: $e');
      rethrow;
    }
  }

  /// Delete multiple messages from Firebase by their IDs
  static Future<void> deleteMessagesByIds(List<String> messageIds) async {
    for (final messageId in messageIds) {
      try {
        await _realtimeDb.ref('messages/$messageId').remove();
      } catch (e) {
        print('[Firebase] Error deleting message $messageId: $e');
      }
    }
  }

  /// Delete all messages in a conversation from Firebase (for everyone)
  static Future<void> deleteConversationFromCloud(
    String userId1,
    String userId2,
  ) async {
    try {
      // Get all messages between the two users
      final snapshot1 = await _realtimeDb
          .ref('messages')
          .orderByChild('fromId')
          .equalTo(userId1)
          .get();

      final snapshot2 = await _realtimeDb
          .ref('messages')
          .orderByChild('fromId')
          .equalTo(userId2)
          .get();

      final messageIds = <String>[];

      // Filter messages from user1 to user2
      if (snapshot1.exists && snapshot1.value is Map) {
        final messages = Map<dynamic, dynamic>.from(snapshot1.value as Map);
        for (final entry in messages.entries) {
          final msg = entry.value;
          if (msg is Map && msg['toId'] == userId2) {
            messageIds.add(entry.key.toString());
          }
        }
      }

      // Filter messages from user2 to user1
      if (snapshot2.exists && snapshot2.value is Map) {
        final messages = Map<dynamic, dynamic>.from(snapshot2.value as Map);
        for (final entry in messages.entries) {
          final msg = entry.value;
          if (msg is Map && msg['toId'] == userId1) {
            messageIds.add(entry.key.toString());
          }
        }
      }

      // Delete all found messages
      await deleteMessagesByIds(messageIds);
      print(
        '[Firebase] ✓ Deleted ${messageIds.length} messages from conversation',
      );
    } catch (e) {
      print('[Firebase] Error deleting conversation: $e');
      rethrow;
    }
  }
}
