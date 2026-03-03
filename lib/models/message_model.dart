/// Message model (temporary, stored in Realtime DB & local SQLite)
class MessageModel {
  final String id;
  final String fromId;
  final String toId;
  final String text;
  final int timestamp;
  final bool delivered;

  MessageModel({
    required this.id,
    required this.fromId,
    required this.toId,
    required this.text,
    required this.timestamp,
    this.delivered = false,
  });

  /// Convert to JSON for Realtime DB
  Map<String, dynamic> toJson() => {
        'id': id,
        'fromId': fromId,
        'toId': toId,
        'text': text,
        'timestamp': timestamp,
        'delivered': delivered,
      };

  /// Create from Realtime DB JSON
  factory MessageModel.fromJson(Map<String, dynamic> json) => MessageModel(
        id: json['id'] as String,
        fromId: json['fromId'] as String,
        toId: json['toId'] as String,
        text: json['text'] as String? ?? '',
        timestamp: json['timestamp'] as int,
        delivered: json['delivered'] as bool? ?? false,
      );

  /// Copy with modifications
  MessageModel copyWith({
    String? id,
    String? fromId,
    String? toId,
    String? text,
    int? timestamp,
    bool? delivered,
  }) =>
      MessageModel(
        id: id ?? this.id,
        fromId: fromId ?? this.fromId,
        toId: toId ?? this.toId,
        text: text ?? this.text,
        timestamp: timestamp ?? this.timestamp,
        delivered: delivered ?? this.delivered,
      );

  /// Check if message is older than 24 hours
  bool isOlderThan24Hours() {
    final now = DateTime.now().millisecondsSinceEpoch;
    final age = now - timestamp;
    return age > (24 * 60 * 60 * 1000); // 24 hours in milliseconds
  }

  @override
  String toString() =>
      'MessageModel(id: $id, from: $fromId, to: $toId, text: ${text.substring(0, min(20, text.length))}...)';

  static int min(int a, int b) => a < b ? a : b;
}
