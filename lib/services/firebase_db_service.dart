import 'package:firebase_database/firebase_database.dart';

class FirebaseDBService {
  static final _db = FirebaseDatabase.instance;

  // Send message to cloud
  static Future<void> sendMessageToCloud({
    required String senderUID,
    required String receiverUID,
    required String encryptedText,
    required String iv,
    required int timestamp,
  }) async {
    final messageRef = _db.ref('messages/$receiverUID').push();

    await messageRef.set({
      'senderUID': senderUID,
      'text': encryptedText,
      'iv': iv,
      'timestamp': timestamp,
      'delivered': false,
    });
  }

  // Listen for incoming messages
  static Stream<Map<String, dynamic>> listenForMessages(String receiverUID) {
    return _db
        .ref('messages/$receiverUID')
        .onValue
        .map((event) {
          final result = <String, dynamic>{};
          if (event.snapshot.value is Map) {
            final map = event.snapshot.value as Map;
            map.forEach((key, value) {
              if (value is Map) {
                result[key] = {
                  'id': key,
                  ...value.cast<String, dynamic>(),
                };
              }
            });
          }
          return result;
        });
  }

  // Mark message as delivered
  static Future<void> markAsDelivered(String receiverUID, String messageId) async {
    await _db.ref('messages/$receiverUID/$messageId/delivered').set(true);
  }

  // Delete old messages (cleanup)
  static Future<void> deleteOldMessagesInCloud(String receiverUID, int cutoffTime) async {
    final snapshot = await _db.ref('messages/$receiverUID').get();
    if (!snapshot.exists) return;

    final map = snapshot.value as Map;
    for (final entry in map.entries) {
      final msg = entry.value as Map;
      final timestamp = msg['timestamp'] as int?;
      if (timestamp != null && timestamp < cutoffTime) {
        await _db.ref('messages/$receiverUID/${entry.key}').remove();
      }
    }
  }
}
