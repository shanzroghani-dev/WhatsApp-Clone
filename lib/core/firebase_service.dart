import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:whatsapp_clone/core/constants.dart';
import 'package:whatsapp_clone/models/user_model.dart';

class FirebaseService {
  static final FirebaseAuth _auth = FirebaseAuth.instance;
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static final FirebaseDatabase _realtimeDb = FirebaseDatabase.instance;
  static final Random _random = Random();

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
            print('[REGISTER] Number $candidateNumber already exists, retrying...');
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
    final doc = await _firestore.collection(AppConstants.usersCollection).doc(uid).get();
    return doc.data();
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
    final query = await _firestore.collection(AppConstants.usersCollection).get();
    return query.docs.map((doc) => UserModel.fromJson(doc.data())).toList();
  }

  static Future<void> updateUserProfile({
    required String uid,
    String? displayName,
    String? profilePicUrl,
    String? status,
    String? publicKey,
  }) async {
    final data = <String, dynamic>{'lastUpdated': FieldValue.serverTimestamp()};
    if (displayName != null) data['displayName'] = displayName;
    if (profilePicUrl != null) data['profilePic'] = profilePicUrl;
    if (status != null) data['status'] = status;
    if (publicKey != null) data['publicKey'] = publicKey;

    await _firestore.collection(AppConstants.usersCollection).doc(uid).update(data);
  }

  static Future<void> updatePresence(String uid, bool isOnline) async {
    try {
      await _firestore.collection(AppConstants.usersCollection).doc(uid).update({
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
  }) async {
    final messageRef = _realtimeDb.ref('${AppConstants.messagesPath}/$receiverUID').push();
    final remoteId = messageRef.key ?? localMessageId;

    await messageRef.set({
      'messageId': remoteId,
      'localMessageId': localMessageId,
      'senderUID': senderUID,
      'text': encryptedText,
      'iv': iv,
      'timestamp': timestamp,
      'delivered': false,
      'notificationMeta': {
        'senderUID': senderUID,
        'messageId': remoteId,
      },
    });

    return remoteId;
  }

  static Stream<Map<String, dynamic>> listenForIncomingMessages(String receiverUID) {
    return _realtimeDb
        .ref('${AppConstants.messagesPath}/$receiverUID')
        .orderByChild('delivered')
        .equalTo(false)
        .onChildAdded
        .map((event) {
      final value = event.snapshot.value;
      if (value is! Map) {
        return <String, dynamic>{};
      }
      return {
        'id': event.snapshot.key,
        ...value.cast<String, dynamic>(),
      };
    }).where((event) => event.isNotEmpty);
  }

  static Future<void> markAsDelivered(String receiverUID, String messageId) async {
    await _realtimeDb
        .ref('${AppConstants.messagesPath}/$receiverUID/$messageId/delivered')
        .set(true);
  }

  static Future<void> deleteOldMessagesInCloud(String receiverUID, int cutoffTime) async {
    final snapshot = await _realtimeDb.ref('${AppConstants.messagesPath}/$receiverUID').get();
    if (!snapshot.exists || snapshot.value is! Map) return;

    final map = snapshot.value as Map;
    for (final entry in map.entries) {
      final msg = entry.value;
      if (msg is! Map) continue;
      final timestamp = msg['timestamp'];
      if (timestamp is int && timestamp < cutoffTime) {
        await _realtimeDb
            .ref('${AppConstants.messagesPath}/$receiverUID/${entry.key}')
            .remove();
      }
    }
  }
}

