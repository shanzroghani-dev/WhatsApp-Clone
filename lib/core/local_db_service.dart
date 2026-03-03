import 'dart:convert';
import 'package:encrypt/encrypt.dart' as encrypt;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import 'package:whatsapp_clone/core/constants.dart';
import 'package:whatsapp_clone/models/message_model.dart';
import 'package:whatsapp_clone/models/user_model.dart';

class LocalDBService {
  static const FlutterSecureStorage _secureStorage = FlutterSecureStorage();
  static const _secureKey = 'wc_aes_key';

  static Database? _db;
  static late encrypt.Key _aesKey;
  static late encrypt.Encrypter _encrypter;

  static Future<void> init() async {
    final existing = await _secureStorage.read(key: _secureKey);
    if (existing == null) {
      final key = encrypt.Key.fromSecureRandom(AppConstants.aesKeySize);
      await _secureStorage.write(key: _secureKey, value: base64Encode(key.bytes));
      _aesKey = key;
    } else {
      _aesKey = encrypt.Key(base64Decode(existing));
    }

    _encrypter = encrypt.Encrypter(encrypt.AES(_aesKey, mode: encrypt.AESMode.cbc));

    final databasesPath = await getDatabasesPath();
    final dbPath = join(databasesPath, 'whatsapp_clone.db');

    _db = await openDatabase(
      dbPath,
      version: 4,
      onCreate: (db, _) async {
        await _createTables(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute('ALTER TABLE ${AppConstants.localMessagesTable} ADD COLUMN delivered INTEGER DEFAULT 0');
          await db.execute('ALTER TABLE ${AppConstants.localMessagesTable} ADD COLUMN synced INTEGER DEFAULT 0');
          await db.execute('ALTER TABLE ${AppConstants.localMessagesTable} ADD COLUMN remoteId TEXT');
          await db.execute('ALTER TABLE ${AppConstants.localMessagesTable} ADD COLUMN iv TEXT');
          await _createProfileTable(db);
          await _createOutgoingQueueTable(db);
        }
        if (oldVersion < 3) {
          await _createChatListTable(db);
        }
        if (oldVersion < 4) {
          // Migrate username -> uniqueNumber in user_profiles table
          print('[LocalDB] Migrating user_profiles: username -> uniqueNumber');
          try {
            // Check if the old column exists
            final tableInfo = await db.rawQuery('PRAGMA table_info(${AppConstants.localProfilesTable})');
            final hasUsername = tableInfo.any((col) => col['name'] == 'username');
            final hasUniqueNumber = tableInfo.any((col) => col['name'] == 'uniqueNumber');
            
            if (hasUsername && !hasUniqueNumber) {
              // Rename column by recreating table
              await db.execute('ALTER TABLE ${AppConstants.localProfilesTable} RENAME TO _old_profiles');
              await _createProfileTable(db);
              await db.execute('''
                INSERT INTO ${AppConstants.localProfilesTable} 
                (uid, uniqueNumber, displayName, profilePic, status, publicKey, isOnline, lastSeen, updatedAt)
                SELECT uid, username, displayName, profilePic, status, publicKey, isOnline, lastSeen, updatedAt
                FROM _old_profiles
              ''');
              await db.execute('DROP TABLE _old_profiles');
              print('[LocalDB] ✓ Column renamed: username -> uniqueNumber');
            } else if (!hasUsername && hasUniqueNumber) {
              print('[LocalDB] ✓ Column already named uniqueNumber');
            } else {
              print('[LocalDB] Adding uniqueNumber column');
              await db.execute('ALTER TABLE ${AppConstants.localProfilesTable} ADD COLUMN uniqueNumber TEXT');
            }
          } catch (e) {
            print('[LocalDB] Migration error (non-fatal): $e');
          }
        }
      },
    );

    await deleteOldLocalMessages();
  }

  static Future<void> _createTables(Database db) async {
    await db.execute('''
      CREATE TABLE ${AppConstants.localMessagesTable} (
        id TEXT PRIMARY KEY,
        fromId TEXT,
        toId TEXT,
        cipher TEXT,
        iv TEXT,
        timestamp INTEGER,
        delivered INTEGER DEFAULT 0,
        synced INTEGER DEFAULT 0,
        remoteId TEXT
      )
    ''');

    await _createProfileTable(db);
    await _createOutgoingQueueTable(db);
    await _createChatListTable(db);
  }

  static Future<void> _createProfileTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS ${AppConstants.localProfilesTable} (
        uid TEXT PRIMARY KEY,
        uniqueNumber TEXT,
        displayName TEXT,
        profilePic TEXT,
        status TEXT,
        publicKey TEXT,
        isOnline INTEGER DEFAULT 0,
        lastSeen INTEGER DEFAULT 0,
        updatedAt INTEGER
      )
    ''');
  }

  static Future<void> _createOutgoingQueueTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS ${AppConstants.localOutgoingQueueTable} (
        localMessageId TEXT PRIMARY KEY,
        senderUID TEXT,
        receiverUID TEXT,
        cipher TEXT,
        iv TEXT,
        timestamp INTEGER,
        retries INTEGER DEFAULT 0,
        createdAt INTEGER
      )
    ''');
  }

  static Future<void> _createChatListTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS ${AppConstants.localChatListTable} (
        ownerUID TEXT,
        peerUID TEXT,
        lastMessage TEXT,
        lastTimestamp INTEGER,
        updatedAt INTEGER,
        PRIMARY KEY (ownerUID, peerUID)
      )
    ''');
  }

  static Future<Database> get _database async {
    if (_db == null) {
      await init();
    }
    return _db!;
  }

  static Future<List<MessageModel>> messagesBetween(String aId, String bId) async {
    final db = await _database;
    final rows = await db.query(
      AppConstants.localMessagesTable,
      where: '(fromId = ? AND toId = ?) OR (fromId = ? AND toId = ?)',
      whereArgs: [aId, bId, bId, aId],
      orderBy: 'timestamp ASC',
    );

    return rows.map((m) {
      final cipher = m['cipher'] as String? ?? '';
      final iv = m['iv'] as String? ?? '';
      String text = '';
      if (cipher.isNotEmpty && iv.isNotEmpty) {
        try {
          text = _encrypter.decrypt64(cipher, iv: encrypt.IV.fromBase64(iv));
        } catch (_) {
          text = '<decryption error>';
        }
      }

      return MessageModel(
        id: m['id'] as String,
        fromId: m['fromId'] as String,
        toId: m['toId'] as String,
        text: text,
        timestamp: m['timestamp'] as int,
        delivered: (m['delivered'] as int? ?? 0) == 1,
      );
    }).toList();
  }

  static Future<void> saveMessageLocal(
    MessageModel m, {
    bool synced = false,
    String? remoteId,
  }) async {
    final db = await _database;
    final iv = encrypt.IV.fromSecureRandom(AppConstants.ivSize);
    final encrypted = _encrypter.encrypt(m.text, iv: iv);

    await db.insert(
      AppConstants.localMessagesTable,
      {
        'id': m.id,
        'fromId': m.fromId,
        'toId': m.toId,
        'cipher': encrypted.base64,
        'iv': iv.base64,
        'timestamp': m.timestamp,
        'delivered': m.delivered ? 1 : 0,
        'synced': synced ? 1 : 0,
        'remoteId': remoteId,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  static Future<void> queueOutgoingMessage({
    required String localMessageId,
    required String senderUID,
    required String receiverUID,
    required String cipher,
    required String iv,
    required int timestamp,
  }) async {
    final db = await _database;
    await db.insert(
      AppConstants.localOutgoingQueueTable,
      {
        'localMessageId': localMessageId,
        'senderUID': senderUID,
        'receiverUID': receiverUID,
        'cipher': cipher,
        'iv': iv,
        'timestamp': timestamp,
        'retries': 0,
        'createdAt': DateTime.now().millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  static Future<List<Map<String, dynamic>>> getOutgoingQueue() async {
    final db = await _database;
    return db.query(AppConstants.localOutgoingQueueTable, orderBy: 'createdAt ASC');
  }

  static Future<void> markOutgoingSynced(String localMessageId, {String? remoteId}) async {
    final db = await _database;
    await db.delete(
      AppConstants.localOutgoingQueueTable,
      where: 'localMessageId = ?',
      whereArgs: [localMessageId],
    );

    await db.update(
      AppConstants.localMessagesTable,
      {
        'synced': 1,
        if (remoteId != null) 'remoteId': remoteId,
      },
      where: 'id = ?',
      whereArgs: [localMessageId],
    );
  }

  static Future<void> incrementOutgoingRetry(String localMessageId) async {
    final db = await _database;
    await db.rawUpdate(
      'UPDATE ${AppConstants.localOutgoingQueueTable} SET retries = retries + 1 WHERE localMessageId = ?',
      [localMessageId],
    );
  }

  static Future<void> updateDeliveryStatus(String localMessageId, bool delivered) async {
    final db = await _database;
    await db.update(
      AppConstants.localMessagesTable,
      {'delivered': delivered ? 1 : 0},
      where: 'id = ?',
      whereArgs: [localMessageId],
    );
  }

  static Future<void> cacheUserProfile(UserModel user) async {
    final db = await _database;
    await db.insert(
      AppConstants.localProfilesTable,
      {
        'uid': user.uid,
        'uniqueNumber': user.uniqueNumber,
        'displayName': user.displayName,
        'profilePic': user.profilePic,
        'status': user.status,
        'publicKey': user.publicKey,
        'isOnline': user.isOnline ? 1 : 0,
        'lastSeen': user.lastSeen.millisecondsSinceEpoch,
        'updatedAt': DateTime.now().millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  static Future<void> cacheUserProfiles(List<UserModel> users) async {
    for (final user in users) {
      await cacheUserProfile(user);
    }
  }

  static Future<UserModel?> getCachedProfile(String uid) async {
    final db = await _database;
    final rows = await db.query(
      AppConstants.localProfilesTable,
      where: 'uid = ?',
      whereArgs: [uid],
      limit: 1,
    );

    if (rows.isEmpty) return null;
    final row = rows.first;
    return UserModel(
      uid: uid,
      uniqueNumber: row['uniqueNumber'] as String? ?? '',
      email: '',
      displayName: row['displayName'] as String? ?? '',
      profilePic: row['profilePic'] as String? ?? '',
      status: row['status'] as String? ?? 'Available',
      publicKey: row['publicKey'] as String? ?? '',
      isOnline: (row['isOnline'] as int? ?? 0) == 1,
      lastSeen: DateTime.fromMillisecondsSinceEpoch((row['lastSeen'] as int? ?? 0)),
    );
  }

  static Future<void> deleteOldLocalMessages() async {
    final db = await _database;
    final cutoff = DateTime.now().subtract(AppConstants.messageTTL).millisecondsSinceEpoch;
    await db.delete(AppConstants.localMessagesTable, where: 'timestamp < ?', whereArgs: [cutoff]);
  }

  static Future<void> deleteMessage(String messageId) async {
    final db = await _database;
    await db.delete(AppConstants.localMessagesTable, where: 'id = ?', whereArgs: [messageId]);
  }

  static Future<void> deleteConversation(String userId1, String userId2) async {
    final db = await _database;
    await db.delete(
      AppConstants.localMessagesTable,
      where: '(fromId = ? AND toId = ?) OR (fromId = ? AND toId = ?)',
      whereArgs: [userId1, userId2, userId2, userId1],
    );
  }

  static Future<int> getMessageCount(String aId, String bId) async {
    final db = await _database;
    final result = await db.rawQuery(
      'SELECT COUNT(*) as count FROM ${AppConstants.localMessagesTable} WHERE (fromId = ? AND toId = ?) OR (fromId = ? AND toId = ?)',
      [aId, bId, bId, aId],
    );
    return Sqflite.firstIntValue(result) ?? 0;
  }

  static Future<void> upsertChatListEntry({
    required String ownerUID,
    required String peerUID,
    required String lastMessage,
    required int lastTimestamp,
  }) async {
    final db = await _database;
    await db.insert(
      AppConstants.localChatListTable,
      {
        'ownerUID': ownerUID,
        'peerUID': peerUID,
        'lastMessage': lastMessage,
        'lastTimestamp': lastTimestamp,
        'updatedAt': DateTime.now().millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  static Future<List<Map<String, dynamic>>> getChatListEntries(String ownerUID) async {
    final db = await _database;
    return db.query(
      AppConstants.localChatListTable,
      where: 'ownerUID = ?',
      whereArgs: [ownerUID],
      orderBy: 'lastTimestamp DESC',
    );
  }

  static Future<void> removeChatListEntry(String ownerUID, String peerUID) async {
    final db = await _database;
    await db.delete(
      AppConstants.localChatListTable,
      where: 'ownerUID = ? AND peerUID = ?',
      whereArgs: [ownerUID, peerUID],
    );
  }
}
