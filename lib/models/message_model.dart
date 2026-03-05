/// Message model (temporary, stored in Realtime DB & local SQLite)
class MessageModel {
  final String id;  // Local UUID
  final String? remoteId;  // Firebase auto-generated messageId
  final String fromId;
  final String toId;
  final String text;
  final int timestamp;
  final bool delivered;
  final int? deliveredAt;  // Timestamp when marked as delivered
  final bool read;
  final int? readAt;  // Timestamp when marked as read

  MessageModel({
    required this.id,
    this.remoteId,
    required this.fromId,
    required this.toId,
    required this.text,
    required this.timestamp,
    this.delivered = false,
    this.deliveredAt,
    this.read = false,
    this.readAt,
  });

  /// Convert to JSON for Realtime DB
  Map<String, dynamic> toJson() => {
        'id': id,
        'fromId': fromId,
        'toId': toId,
        'text': text,
        'timestamp': timestamp,
        'delivered': delivered,
        'deliveredAt': deliveredAt,
        'read': read,
        'readAt': readAt,
      };

  /// Create from Realtime DB JSON
  factory MessageModel.fromJson(Map<String, dynamic> json) => MessageModel(
        id: json['id'] as String,
        remoteId: json['remoteId'] as String?,
        fromId: json['fromId'] as String,
        toId: json['toId'] as String,
        text: json['text'] as String? ?? '',
        timestamp: json['timestamp'] as int,
        delivered: json['delivered'] as bool? ?? false,
        deliveredAt: json['deliveredAt'] as int?,
        read: json['read'] as bool? ?? false,
        readAt: json['readAt'] as int?,
      );

  /// Copy with modifications
  MessageModel copyWith({
    String? id,
    String? remoteId,
    String? fromId,
    String? toId,
    String? text,
    int? timestamp,
    bool? delivered,
    int? deliveredAt,
    bool? read,
    int? readAt,
  }) =>
      MessageModel(
        id: id ?? this.id,
        remoteId: remoteId ?? this.remoteId,
        fromId: fromId ?? this.fromId,
        toId: toId ?? this.toId,
        text: text ?? this.text,
        timestamp: timestamp ?? this.timestamp,
        delivered: delivered ?? this.delivered,
        deliveredAt: deliveredAt ?? this.deliveredAt,
        read: read ?? this.read,
        readAt: readAt ?? this.readAt,
      );

  @override
  String toString() =>
      'MessageModel(id: $id, from: $fromId, to: $toId, text: ${text.substring(0, min(20, text.length))}...)';

  static int min(int a, int b) => a < b ? a : b;
}
