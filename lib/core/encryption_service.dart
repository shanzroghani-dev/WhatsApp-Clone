import 'dart:convert';
import 'dart:typed_data';

import 'package:encrypt/encrypt.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class EncryptionService {
	static const _secureStorage = FlutterSecureStorage();
	static const _masterKeyStorageKey = 'encryption_master_key_v1';

	static String generateKey() {
		final key = Key.fromSecureRandom(32);
		return key.base64;
	}

	static Future<void> initialize(String generatedKey) async {
		final existing = await _secureStorage.read(key: _masterKeyStorageKey);
		if (existing != null && existing.isNotEmpty) {
			return;
		}

		await _secureStorage.write(key: _masterKeyStorageKey, value: generatedKey);
	}

	static Map<String, String> encryptForUsers(
		String plainText,
		String userA,
		String userB,
	) {
		final key = _derivePairKey(userA, userB);
		final iv = IV.fromSecureRandom(16);
		final encrypter = Encrypter(AES(key, mode: AESMode.cbc));
		final encrypted = encrypter.encrypt(plainText, iv: iv);

		return {
			'cipher': encrypted.base64,
			'iv': iv.base64,
		};
	}

	static String? decryptForUsers(
		String cipherBase64,
		String ivBase64,
		String userA,
		String userB,
	) {
		try {
			final key = _derivePairKey(userA, userB);
			final iv = IV.fromBase64(ivBase64);
			final encrypted = Encrypted.fromBase64(cipherBase64);
			final encrypter = Encrypter(AES(key, mode: AESMode.cbc));
			return encrypter.decrypt(encrypted, iv: iv);
		} catch (_) {
			return null;
		}
	}

	static Key _derivePairKey(String userA, String userB) {
		final sorted = [userA.trim(), userB.trim()]..sort();
		final seed = '${sorted[0]}|${sorted[1]}|whatsapp_clone_pair_v1';
		final bytes = utf8.encode(seed);
		final folded = List<int>.filled(32, 0);

		for (var index = 0; index < bytes.length; index++) {
			final slot = index % 32;
			final mixed = (bytes[index] + index * 31) & 0xFF;
			folded[slot] = (folded[slot] ^ mixed) & 0xFF;
		}

		for (var index = 0; index < 32; index++) {
			folded[index] = (folded[index] + index * 17 + 29) & 0xFF;
		}

		return Key(Uint8List.fromList(folded));
	}
}
