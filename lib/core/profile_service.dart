import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:whatsapp_clone/core/constants.dart';
import 'package:whatsapp_clone/core/firebase_service.dart';
import 'package:whatsapp_clone/core/local_db_service.dart';
import 'package:whatsapp_clone/models/user_model.dart';

class ProfileService {
  static final _firestore = FirebaseFirestore.instance;
  static final _storage = FirebaseStorage.instance;

  static final Map<String, UserModel> _memoryCache = {};

  static Future<String> uploadProfilePic(String uid, File imageFile) async {
    final ref = _storage.ref().child('profilePics/$uid.jpg');
    await ref.putFile(imageFile, SettableMetadata(contentType: 'image/jpeg'));
    final url = await ref.getDownloadURL();

    await FirebaseService.updateUserProfile(uid: uid, profilePicUrl: url);
    final existing = _memoryCache[uid];
    if (existing != null) {
      final updated = existing.copyWith(profilePic: url, lastUpdated: DateTime.now());
      _memoryCache[uid] = updated;
      await LocalDBService.cacheUserProfile(updated);
    }

    return url;
  }

  static Future<void> updateProfile(
    String uid, {
    String? displayName,
    String? status,
    String? profilePicUrl,
    bool? isOnline,
  }) async {
    await FirebaseService.updateUserProfile(
      uid: uid,
      displayName: displayName,
      profilePicUrl: profilePicUrl,
      status: status,
    );

    if (isOnline != null) {
      await FirebaseService.updatePresence(uid, isOnline);
    }

    final profile = await getProfile(uid, forceRefresh: true);
    if (profile != null) {
      await LocalDBService.cacheUserProfile(profile);
      _memoryCache[uid] = profile;
    }
  }

  static Future<void> updateLastSeen(String uid) async {
    await _firestore.collection(AppConstants.usersCollection).doc(uid).update({
      'lastSeen': FieldValue.serverTimestamp(),
      'lastUpdated': FieldValue.serverTimestamp(),
    });
  }

  static Future<void> updateOnlineStatus(String uid, bool isOnline) async {
    await FirebaseService.updatePresence(uid, isOnline);

    final existing = _memoryCache[uid];
    if (existing != null) {
      final updated = existing.copyWith(
        isOnline: isOnline,
        lastSeen: DateTime.now(),
        lastUpdated: DateTime.now(),
      );
      _memoryCache[uid] = updated;
      await LocalDBService.cacheUserProfile(updated);
    }
  }

  static Future<UserModel?> getProfile(String uid, {bool forceRefresh = false}) async {
    if (!forceRefresh && _memoryCache.containsKey(uid)) {
      return _memoryCache[uid];
    }

    try {
      final data = await FirebaseService.getUserProfileMap(uid);
      if (data == null) {
        return await LocalDBService.getCachedProfile(uid);
      }

      final user = UserModel.fromJson(data);
      _memoryCache[uid] = user;
      await LocalDBService.cacheUserProfile(user);
      return user;
    } catch (_) {
      return await LocalDBService.getCachedProfile(uid);
    }
  }

  static Future<Map<String, UserModel>> getProfiles(List<String> uids) async {
    final result = <String, UserModel>{};

    for (final uid in uids.toSet()) {
      final profile = await getProfile(uid);
      if (profile != null) {
        result[uid] = profile;
      }
    }

    return result;
  }

  static Future<void> updatePublicKey(String uid, String publicKey) async {
    await FirebaseService.updateUserProfile(uid: uid, publicKey: publicKey);

    final existing = _memoryCache[uid];
    if (existing != null) {
      final updated = existing.copyWith(publicKey: publicKey, lastUpdated: DateTime.now());
      _memoryCache[uid] = updated;
      await LocalDBService.cacheUserProfile(updated);
    }
  }

  static void clearCache() {
    _memoryCache.clear();
  }
}
