class Message {
  final String id;
  final String fromId;
  final String toId;
  final String text;
  final int timestamp;

  Message({required this.id, required this.fromId, required this.toId, required this.text, required this.timestamp});

  Map<String, dynamic> toJson() => {
        'id': id,
        'fromId': fromId,
        'toId': toId,
        'text': text,
        'timestamp': timestamp,
      };

  factory Message.fromJson(Map<String, dynamic> json) => Message(
        id: json['id'] as String,
        fromId: json['fromId'] as String,
        toId: json['toId'] as String,
        text: json['text'] as String,
        timestamp: json['timestamp'] as int,
      );
}
