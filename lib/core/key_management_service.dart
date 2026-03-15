import 'dart:convert';
import 'package:encrypt/encrypt.dart' as encrypt;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class KeyPairModel {
  final String publicKey;
  final String privateKey;

  KeyPairModel({required this.publicKey, required this.privateKey});
}

class KeyManagementService {
  static const FlutterSecureStorage _secureStorage = FlutterSecureStorage();

  static String _privateKeyStorageKey(String uid) => 'wc_private_key_$uid';
  static String _publicKeyStorageKey(String uid) => 'wc_public_key_$uid';

  static Future<KeyPairModel> ensureKeyPair(String uid) async {
    final existingPrivate = await _secureStorage.read(
      key: _privateKeyStorageKey(uid),
    );
    final existingPublic = await _secureStorage.read(
      key: _publicKeyStorageKey(uid),
    );

    if (existingPrivate != null && existingPublic != null) {
      return KeyPairModel(
        publicKey: existingPublic,
        privateKey: existingPrivate,
      );
    }

    final privateKey = base64Encode(encrypt.Key.fromSecureRandom(32).bytes);
    final publicKey = base64Encode(encrypt.Key.fromSecureRandom(32).bytes);

    await _secureStorage.write(
      key: _privateKeyStorageKey(uid),
      value: privateKey,
    );
    await _secureStorage.write(
      key: _publicKeyStorageKey(uid),
      value: publicKey,
    );

    return KeyPairModel(publicKey: publicKey, privateKey: privateKey);
  }

  static Future<String?> getPrivateKey(String uid) {
    return _secureStorage.read(key: _privateKeyStorageKey(uid));
  }

  static Future<String?> getPublicKey(String uid) {
    return _secureStorage.read(key: _publicKeyStorageKey(uid));
  }

  static Future<void> clearKeys(String uid) async {
    await _secureStorage.delete(key: _privateKeyStorageKey(uid));
    await _secureStorage.delete(key: _publicKeyStorageKey(uid));
  }
}
