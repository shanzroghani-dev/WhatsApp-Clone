import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import 'package:whatsapp_clone/core/firebase_service.dart';
import 'package:whatsapp_clone/core/key_management_service.dart';
import 'package:whatsapp_clone/core/notification_service.dart';
import 'package:whatsapp_clone/models/user_model.dart';

class AuthService {
  static const String _localUserPrefKey = 'local_user';
  static const String _localUserNumberPrefKey = 'local_user_number';

  static Future<UserModel> registerUser({
    required String email,
    required String password,
    String? displayName,
  }) async {
    if (email.isEmpty || password.isEmpty) {
      throw Exception('Email & password required');
    }

    print('[AuthService] Starting registration for: $email');
    try {
      print('[AuthService] Calling FirebaseService.registerUser...');
      final registered = await FirebaseService.registerUser(
        email: email,
        password: password,
        displayName: displayName,
      );
      print('[AuthService] ✓ FirebaseService registration successful');
      print('[AuthService] User UID: ${registered.uid}');
      print('[AuthService] Unique Number: ${registered.uniqueNumber}');

      print('[AuthService] Generating keypair...');
      final keyPair = await KeyManagementService.ensureKeyPair(registered.uid);
      print('[AuthService] ✓ Keypair generated');

      print('[AuthService] Updating user profile with public key...');
      await FirebaseService.updateUserProfile(
        uid: registered.uid,
        publicKey: keyPair.publicKey,
      );
      print('[AuthService] ✓ Public key updated in Firestore');

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_localUserPrefKey, registered.uid);
      await prefs.setString(_localUserNumberPrefKey, registered.uniqueNumber);
      print('[AuthService] ✓ Saved to SharedPreferences');
      print('[AuthService] ✓✓✓ REGISTRATION COMPLETE ✓✓✓');

      final result = registered.copyWith(publicKey: keyPair.publicKey);
      NotificationService.setCurrentUserUid(result.uid);

      // Save FCM token for push notifications
      try {
        final fcmToken = await NotificationService.getToken();
        if (fcmToken != null && fcmToken.isNotEmpty) {
          await FirebaseService.updateUserProfile(
            uid: registered.uid,
            fcmToken: fcmToken,
          );
          print('[AuthService] ✓ FCM token saved');
        }
      } catch (e) {
        print('[AuthService] ⚠ Failed to save FCM token: $e');
      }

      return result;
    } catch (e, stackTrace) {
      print('[AuthService] ⚠ Firebase registration failed: $e');
      print('[AuthService] Stack trace: $stackTrace');
      // Only create local fallback for network/availability errors
      // If it's an actual error (like validation), rethrow it
      if (e.toString().contains('email') ||
          e.toString().contains('password') ||
          e.toString().contains('weak-password') ||
          e.toString().contains('email-already-in-use')) {
        print('[AuthService] Auth validation error, rethrowing...');
        rethrow;
      }
      print('[AuthService] Creating local-only user as fallback...');
      final uid = const Uuid().v4();
      final localNumber = _generateLocalUserNumber();
      final keyPair = await KeyManagementService.ensureKeyPair(uid);
      final user = UserModel(
        uid: uid,
        uniqueNumber: localNumber,
        email: email,
        displayName: displayName?.trim().isNotEmpty == true
            ? displayName!.trim()
            : 'User ${localNumber.substring(localNumber.length - 4)}',
        profilePic: '',
        status: 'Available',
        publicKey: keyPair.publicKey,
        isOnline: false,
        lastSeen: DateTime.now(),
        createdAt: DateTime.now(),
        lastUpdated: DateTime.now(),
      );

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_localUserPrefKey, user.uid);
      await prefs.setString(_localUserNumberPrefKey, localNumber);
      print('[AuthService] ✓ Local user created with number: $localNumber');
      NotificationService.setCurrentUserUid(user.uid);
      return user;
    }
  }

  static Future<UserModel> loginUser({
    required String email,
    required String password,
  }) async {
    if (email.isEmpty || password.isEmpty) {
      throw Exception('Email & password required');
    }

    print('[AuthService] Starting login for: $email');
    var resolvedEmail = email;
    if (!email.contains('@')) {
      print('[AuthService] Input is a number, resolving to email...');
      final userByNumber = await FirebaseService.getUserByNumberAsModel(email);
      if (userByNumber == null || userByNumber.email.isEmpty) {
        throw Exception('User number not found');
      }
      resolvedEmail = userByNumber.email;
      print('[AuthService] Resolved to email: $resolvedEmail');
    }

    try {
      print('[AuthService] Calling FirebaseService.loginUser...');
      final user = await FirebaseService.loginUser(
        email: resolvedEmail,
        password: password,
      );
      print('[AuthService] ✓ Login successful!');
      print('[AuthService] User UID: ${user.uid}');
      final keyPair = await KeyManagementService.ensureKeyPair(user.uid);
      if (user.publicKey.isEmpty) {
        await FirebaseService.updateUserProfile(
          uid: user.uid,
          publicKey: keyPair.publicKey,
        );
      }

      // Save FCM token for push notifications
      try {
        final fcmToken = await NotificationService.getToken();
        if (fcmToken != null && fcmToken.isNotEmpty) {
          await FirebaseService.updateUserProfile(
            uid: user.uid,
            fcmToken: fcmToken,
          );
          print('[AuthService] ✓ FCM token saved on login');
        }
      } catch (e) {
        print('[AuthService] ⚠ Failed to save FCM token: $e');
      }

      NotificationService.setCurrentUserUid(user.uid);
      return user;
    } catch (_) {
      final prefs = await SharedPreferences.getInstance();
      final savedNumber = prefs.getString(_localUserNumberPrefKey);
      final savedUid = prefs.getString(_localUserPrefKey);

      if (savedNumber == null || savedUid == null) {
        throw Exception('User not found. Register first.');
      }

      final keyPair = await KeyManagementService.ensureKeyPair(savedUid);
      final user = UserModel(
        uid: savedUid,
        uniqueNumber: savedNumber,
        email: resolvedEmail,
        displayName: 'User ${savedNumber.substring(savedNumber.length - 4)}',
        profilePic: '',
        status: 'Available',
        publicKey: keyPair.publicKey,
        isOnline: false,
        lastSeen: DateTime.now(),
        createdAt: DateTime.now().subtract(const Duration(hours: 24)),
        lastUpdated: DateTime.now(),
      );
      NotificationService.setCurrentUserUid(user.uid);
      return user;
    }
  }

  static Future<UserModel?> getCurrentUser() async {
    try {
      final firebaseUser = await FirebaseService.getCurrentUser();
      if (firebaseUser != null) {
        final keyPair = await KeyManagementService.ensureKeyPair(
          firebaseUser.uid,
        );
        if (firebaseUser.publicKey.isEmpty) {
          await FirebaseService.updateUserProfile(
            uid: firebaseUser.uid,
            publicKey: keyPair.publicKey,
          );
          return firebaseUser.copyWith(publicKey: keyPair.publicKey);
        }
        return firebaseUser;
      }
    } catch (_) {}

    final prefs = await SharedPreferences.getInstance();
    final uid = prefs.getString(_localUserPrefKey);
    final userNumber = prefs.getString(_localUserNumberPrefKey);

    if (uid != null && userNumber != null) {
      final keyPair = await KeyManagementService.ensureKeyPair(uid);
      return UserModel(
        uid: uid,
        uniqueNumber: userNumber,
        email: 'local@example.com',
        displayName: 'User ${userNumber.substring(userNumber.length - 4)}',
        profilePic: '',
        status: 'Available',
        publicKey: keyPair.publicKey,
        isOnline: false,
        lastSeen: DateTime.now(),
        createdAt: DateTime.now().subtract(const Duration(hours: 24)),
        lastUpdated: DateTime.now(),
      );
    }

    return null;
  }

  static Future<void> logoutUser() async {
    try {
      await FirebaseService.logoutUser();
    } catch (_) {}

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_localUserPrefKey);
    await prefs.remove(_localUserNumberPrefKey);
    NotificationService.setCurrentUserUid(null);
    NotificationService.clearActiveChat();
  }

  static Future<UserModel?> getUserByNumber(String number) async {
    try {
      return await FirebaseService.getUserByNumberAsModel(number);
    } catch (_) {
      return null;
    }
  }

  static Future<List<UserModel>> getAllUsers() async {
    try {
      return await FirebaseService.getAllUsersAsModels();
    } catch (_) {
      return [];
    }
  }

  static String _generateLocalUserNumber() {
    final now = DateTime.now().millisecondsSinceEpoch.toString();
    return now.substring(now.length - 10);
  }
}
