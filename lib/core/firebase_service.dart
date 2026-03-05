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
    final length = 8 + _random.nextInt(5);
    final firstDigit = 1 + _random.nextInt(9);
    final buffer = StringBuffer()..write(firstDigit);
    for (var i = 1; i < length; i++) {
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
    final messageRef = _realtimeDb
        .ref('messages/$receiverUID')
        .push();
    final remoteId = messageRef.key ?? localMessageId;

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
      'notificationMeta': {'senderUID': senderUID, 'messageId': remoteId},
    };

    // Include notification metadata to avoid Firestore reads in Cloud Function
    if (senderName != null) payload['senderName'] = senderName;
    if (receiverFcmToken != null) payload['receiverFcmToken'] = receiverFcmToken;
    if (messageType != null) payload['type'] = messageType;

    // Write message to receiver's incoming path
    await messageRef.set(payload);

    // Also store in sender's sent messages path for tracking delivery/read status
    // This allows the sender to listen for status updates on their sent messages
    await _realtimeDb
        .ref('sentMessages/$senderUID/$receiverUID/$remoteId')
        .set({
          ...payload,
          'remoteId': remoteId,
        });

    return remoteId;
  }

  static Stream<Map<String, dynamic>> listenForIncomingMessages(
    String receiverUID,
  ) {
    return _realtimeDb
        .ref('messages/$receiverUID')
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
    final snapshot = await _realtimeDb
        .ref('messages/$receiverUID')
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

  static Future<void> markAsDelivered(
    String messageId, {
    String? senderUID,
  }) async {
    final currentUser = _auth.currentUser;
    if (currentUser == null) return;
    
    // Update in receiver's incoming messages path
    await _realtimeDb
        .ref('messages/${currentUser.uid}/$messageId/delivered')
        .set(true);
    
    // If we have sender UID, also update in sender's sent messages path
    if (senderUID != null) {
      await _realtimeDb
          .ref('sentMessages/$senderUID/${currentUser.uid}/$messageId/delivered')
          .set(true)
          .catchError((_) {}); // Ignore errors if sender's path doesn't exist
    }
  }

  static Future<void> markAsDeliveredForReceiver({
    required String receiverUID,
    required String messageId,
    String? senderUID,
  }) async {
    await _realtimeDb
        .ref('messages/$receiverUID/$messageId/delivered')
        .set(true);

    if (senderUID != null && senderUID.isNotEmpty) {
      await _realtimeDb
          .ref('sentMessages/$senderUID/$receiverUID/$messageId/delivered')
          .set(true)
          .catchError((_) {});
    }
  }

  static Future<void> markAsRead(
    String messageId, {
    String? senderUID,
  }) async {
    final currentUser = _auth.currentUser;
    if (currentUser == null) return;
    
    // Update in receiver's incoming messages path
    await _realtimeDb
        .ref('messages/${currentUser.uid}/$messageId/read')
        .set(true);
    
    // If we have sender UID, also update in sender's sent messages path
    if (senderUID != null) {
      await _realtimeDb
          .ref('sentMessages/$senderUID/${currentUser.uid}/$messageId/read')
          .set(true)
          .catchError((_) {}); // Ignore errors if sender's path doesn't exist
    }
  }

  /// Listen for message status updates (delivered/read changes) on sent messages
  static Stream<Map<String, dynamic>> listenForStatusUpdates(
    String currentUserUID,
  ) {
    return _realtimeDb
        .ref('sentMessages/$currentUserUID')
        .onValue
        .asyncExpand((event) {
          final value = event.snapshot.value;
          if (value is! Map) {
            return Stream<Map<String, dynamic>>.empty();
          }

          final updates = <Map<String, dynamic>>[];
          final receiversMap = Map<dynamic, dynamic>.from(value);

          for (final receiverEntry in receiversMap.entries) {
            final receiverUid = receiverEntry.key?.toString();
            final receiverValue = receiverEntry.value;
            if (receiverUid == null || receiverValue is! Map) continue;

            final messagesMap = Map<dynamic, dynamic>.from(receiverValue);
            for (final messageEntry in messagesMap.entries) {
              final messageId = messageEntry.key?.toString();
              final messageValue = messageEntry.value;
              if (messageId == null || messageValue is! Map) continue;

              final data = Map<String, dynamic>.from(messageValue);
              data['messageId'] = messageId;
              data['receiverUID'] = receiverUid;
              updates.add(data);
            }
          }

          return Stream<Map<String, dynamic>>.fromIterable(updates);
        });
  }

  /// Get current message status directly from the message
  static Future<Map<String, dynamic>?> getMessageStatus(
    String messageId,
  ) async {
    try {
      final currentUser = _auth.currentUser;
      if (currentUser == null) return null;

      final snapshot = await _realtimeDb
          .ref('sentMessages/${currentUser.uid}')
          .get();
      
      if (!snapshot.exists || snapshot.value is! Map) {
        return null;
      }

      final receiversMap = Map<dynamic, dynamic>.from(snapshot.value as Map);
      for (final receiverEntry in receiversMap.entries) {
        final receiverUid = receiverEntry.key?.toString();
        final receiverValue = receiverEntry.value;
        if (receiverUid == null || receiverValue is! Map) continue;

        final messagesMap = Map<dynamic, dynamic>.from(receiverValue);
        final messageValue = messagesMap[messageId];
        if (messageValue is Map) {
          final data = Map<String, dynamic>.from(messageValue);
          data['messageId'] = messageId;
          data['receiverUID'] = receiverUid;
          return data;
        }

        // Fallback: messageId may be localMessageId; find matching entry.
        for (final entry in messagesMap.entries) {
          final remoteKey = entry.key?.toString();
          final value = entry.value;
          if (remoteKey == null || value is! Map) continue;

          final data = Map<String, dynamic>.from(value);
          final localMessageId = data['localMessageId']?.toString();
          if (localMessageId != messageId) continue;

          data['messageId'] = remoteKey;
          data['receiverUID'] = receiverUid;
          return data;
        }
      }

      return null;
    } catch (e) {
      print('[Firebase] Error fetching message status: $e');
      return null;
    }
  }

  static Future<void> deleteOldMessagesInCloud(
    int cutoffTime,
  ) async {
    final snapshot = await _realtimeDb
        .ref('${AppConstants.messagesPath}')
        .get();
    if (!snapshot.exists || snapshot.value is! Map) return;

    final receiversMap = Map<dynamic, dynamic>.from(snapshot.value as Map);
    for (final receiverEntry in receiversMap.entries) {
      final receiverUid = receiverEntry.key?.toString();
      final receiverValue = receiverEntry.value;
      if (receiverUid == null || receiverValue is! Map) continue;

      final messagesMap = Map<dynamic, dynamic>.from(receiverValue);
      for (final messageEntry in messagesMap.entries) {
        final messageId = messageEntry.key?.toString();
        final messageValue = messageEntry.value;
        if (messageId == null || messageValue is! Map) continue;

        final timestamp = messageValue['timestamp'];
        if (timestamp is int && timestamp < cutoffTime) {
          await _realtimeDb
              .ref('${AppConstants.messagesPath}/$receiverUid/$messageId')
              .remove();
        }
      }
    }
  }
}
