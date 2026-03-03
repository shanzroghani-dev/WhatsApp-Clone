import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:whatsapp_clone/services/firebase_firestore_service.dart';

class FirebaseAuthService {
  static final _auth = FirebaseAuth.instance;
  static final _db = FirebaseDatabase.instance;

  // Register with email, password, and username
  static Future<UserCredential> registerUser({
    required String email,
    required String password,
    required String username,
    required String displayName,
  }) async {
    final userCredential = await _auth.createUserWithEmailAndPassword(
      email: email,
      password: password,
    );

    final uid = userCredential.user!.uid;

    // Save to Firestore (permanent)
    await FirebaseFirestoreService.createUserProfile(
      uid: uid,
      username: username,
      email: email,
      displayName: displayName.isEmpty ? username : displayName,
    );

    // Save to Realtime DB for quick username lookup
    await _db.ref('usernames/$username').set({
      'uid': uid,
      'displayName': displayName.isEmpty ? username : displayName,
    });

    return userCredential;
  }

  // Login with email and password
  static Future<UserCredential> loginUser({
    required String email,
    required String password,
  }) async {
    return await _auth.signInWithEmailAndPassword(
      email: email,
      password: password,
    );
  }

  // Get current user
  static User? getCurrentUser() {
    return _auth.currentUser;
  }

  // Lookup UID from username
  static Future<String?> getUidFromUsername(String username) async {
    final snapshot = await _db.ref('usernames/$username').get();
    if (!snapshot.exists) return null;
    return snapshot.child('uid').value as String?;
  }

  // Logout
  static Future<void> logout() async {
    await _auth.signOut();
  }
}
