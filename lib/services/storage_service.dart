import 'dart:convert';

import 'package:encrypt/encrypt.dart' as encrypt;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import 'package:whatsapp_clone/models/user.dart';
import 'package:whatsapp_clone/models/message.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class StorageService {
  static late SharedPreferences _prefs;
  static const _usersKey = 'wc_users';
  static const _currentUserKey = 'wc_current_user';
  static const _secureKey = 'wc_aes_key';
  static final _uuid = const Uuid();
  static final _secureStorage = const FlutterSecureStorage();

  // AES key & encrypter
  static late encrypt.Key _aesKey;
  static late encrypt.Encrypter _encrypter;

  // Local DB
  static late Database _db;

  static Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    final existing = await _secureStorage.read(key: _secureKey);
    if (existing == null) {
      final key = encrypt.Key.fromSecureRandom(32); // 256-bit key
      await _secureStorage.write(key: _secureKey, value: base64Encode(key.bytes));
      _aesKey = key;
    } else {
      _aesKey = encrypt.Key(base64Decode(existing));
    }
    _encrypter = encrypt.Encrypter(encrypt.AES(_aesKey, mode: encrypt.AESMode.cbc));

    // Initialize local SQLite DB for messages
    final databasesPath = await getDatabasesPath();
    final path = join(databasesPath, 'whatsapp_clone.db');
    _db = await openDatabase(path, version: 1, onCreate: (db, version) async {
      await db.execute('''
        CREATE TABLE messages (
          id TEXT PRIMARY KEY,
          fromId TEXT,
          toId TEXT,
          cipher TEXT,
          iv TEXT,
          timestamp INTEGER
        )
      ''');
    });

    // Cleanup old messages on startup
    await deleteOldLocalMessages();
  }

  // Users
  static Future<List<AppUser>> users() async {
    final raw = _prefs.getString(_usersKey);
    if (raw == null) return [];
    final list = jsonDecode(raw) as List<dynamic>;
    return list.map((e) => AppUser.fromJson(e as Map<String, dynamic>)).toList();
  }

  static Future<void> saveUsers(List<AppUser> users) async {
    final raw = jsonEncode(users.map((u) => u.toJson()).toList());
    await _prefs.setString(_usersKey, raw);
  }

  static Future<AppUser?> findByUsername(String username) async {
    final all = await users();
    try {
      return all.firstWhere((u) => u.username.toLowerCase() == username.toLowerCase());
    } catch (_) {
      return null;
    }
  }

  static Future<AppUser> createUser(String username, String displayName) async {
    final id = _uuid.v4();
    final u = AppUser(id: id, username: username, displayName: displayName);
    final all = await users();
    all.add(u);
    await saveUsers(all);
    return u;
  }

  static Future<AppUser?> currentUser() async {
    final raw = _prefs.getString(_currentUserKey);
    if (raw == null) return null;
    return AppUser.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  static Future<void> setCurrentUser(AppUser user) async {
    await _prefs.setString(_currentUserKey, jsonEncode(user.toJson()));
  }

  static Future<void> clearCurrentUser() async {
    await _prefs.remove(_currentUserKey);
  }

  // Local DB message APIs (encrypted storage)
  static Future<List<Message>> messagesBetween(String aId, String bId) async {
    final rows = await _db.query('messages',
        where: '(fromId = ? AND toId = ?) OR (fromId = ? AND toId = ?)',
        whereArgs: [aId, bId, bId, aId],
        orderBy: 'timestamp ASC');

    final result = <Message>[];
    for (final m in rows) {
      final id = m['id'] as String;
      final fromId = m['fromId'] as String;
      final toId = m['toId'] as String;
      final cipher = m['cipher'] as String?;
      final iv = m['iv'] as String?;
      final timestamp = m['timestamp'] as int;
      String text = '';
      if (cipher != null && iv != null) {
        try {
          text = _encrypter.decrypt64(cipher, iv: encrypt.IV.fromBase64(iv));
        } catch (_) {
          text = '<decryption error>';
        }
      }
      result.add(Message(id: id, fromId: fromId, toId: toId, text: text, timestamp: timestamp));
    }
    return result;
  }

  static Future<void> sendMessage(Message m, {bool syncToCloud = false}) async {
    // encrypt message text
    final iv = encrypt.IV.fromSecureRandom(16);
    final encrypted = _encrypter.encrypt(m.text, iv: iv);

    await _db.insert('messages', {
      'id': m.id,
      'fromId': m.fromId,
      'toId': m.toId,
      'cipher': encrypted.base64,
      'iv': iv.base64,
      'timestamp': m.timestamp,
    });

    // Optional: sync to cloud if enabled (placeholder)
    if (syncToCloud) {
      // TODO: implement cloud sync (Firebase) hook
    }
  }

  static Future<void> deleteOldLocalMessages() async {
    final cutoff = DateTime.now().subtract(const Duration(hours: 24)).millisecondsSinceEpoch;
    await _db.delete('messages', where: 'timestamp < ?', whereArgs: [cutoff]);
  }
}
