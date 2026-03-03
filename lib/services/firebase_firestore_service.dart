import 'package:cloud_firestore/cloud_firestore.dart';

class FirebaseFirestoreService {
  static final _firestore = FirebaseFirestore.instance;

  // Create or update user profile (permanent)
  static Future<void> createUserProfile({
    required String uid,
    required String username,
    required String email,
    required String displayName,
  }) async {
    await _firestore.collection('users').doc(uid).set({
      'uid': uid,
      'username': username,
      'email': email,
      'displayName': displayName,
      'profilePic': '',
      'createdAt': FieldValue.serverTimestamp(),
      'lastUpdated': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  // Get user profile by UID
  static Future<Map<String, dynamic>?> getUserProfile(String uid) async {
    final doc = await _firestore.collection('users').doc(uid).get();
    return doc.data();
  }

  // Get user by username
  static Future<Map<String, dynamic>?> getUserByUsername(String username) async {
    final query = await _firestore
        .collection('users')
        .where('username', isEqualTo: username)
        .limit(1)
        .get();
    if (query.docs.isEmpty) return null;
    return query.docs.first.data();
  }

  // Get all users (for chat list)
  static Future<List<Map<String, dynamic>>> getAllUsers(String currentUID) async {
    final query = await _firestore
        .collection('users')
        .where('uid', isNotEqualTo: currentUID)
        .get();
    return query.docs.map((doc) => doc.data()).toList();
  }

  // Update user profile
  static Future<void> updateUserProfile({
    required String uid,
    required String displayName,
    String? profilePicUrl,
  }) async {
    await _firestore.collection('users').doc(uid).update({
      'displayName': displayName,
      if (profilePicUrl != null) 'profilePic': profilePicUrl,
      'lastUpdated': FieldValue.serverTimestamp(),
    });
  }
}
