class CallModel {
  final String callId;
  final String initiatorId;
  final String initiatorName;
  final String initiatorProfilePic;
  final String receiverId;
  final String receiverName;
  final String receiverProfilePic;
  final DateTime initiatedAt;
  DateTime? answeredAt;
  DateTime? endedAt;
  final String callType; // 'voice' or 'video'
  final String status; // 'ringing', 'active', 'ended', 'missed', 'rejected'
  final int durationSeconds;
  final String?
  endReason; // 'user_ended', 'no_answer', 'rejected', 'network_error'

  CallModel({
    required this.callId,
    required this.initiatorId,
    required this.initiatorName,
    required this.initiatorProfilePic,
    required this.receiverId,
    required this.receiverName,
    required this.receiverProfilePic,
    required this.initiatedAt,
    this.answeredAt,
    this.endedAt,
    required this.callType,
    required this.status,
    this.durationSeconds = 0,
    this.endReason,
  });

  CallModel copyWith({
    String? callId,
    String? initiatorId,
    String? initiatorName,
    String? initiatorProfilePic,
    String? receiverId,
    String? receiverName,
    String? receiverProfilePic,
    DateTime? initiatedAt,
    DateTime? answeredAt,
    DateTime? endedAt,
    String? callType,
    String? status,
    int? durationSeconds,
    String? endReason,
  }) {
    return CallModel(
      callId: callId ?? this.callId,
      initiatorId: initiatorId ?? this.initiatorId,
      initiatorName: initiatorName ?? this.initiatorName,
      initiatorProfilePic: initiatorProfilePic ?? this.initiatorProfilePic,
      receiverId: receiverId ?? this.receiverId,
      receiverName: receiverName ?? this.receiverName,
      receiverProfilePic: receiverProfilePic ?? this.receiverProfilePic,
      initiatedAt: initiatedAt ?? this.initiatedAt,
      answeredAt: answeredAt ?? this.answeredAt,
      endedAt: endedAt ?? this.endedAt,
      callType: callType ?? this.callType,
      status: status ?? this.status,
      durationSeconds: durationSeconds ?? this.durationSeconds,
      endReason: endReason ?? this.endReason,
    );
  }

  Map<String, dynamic> toJson() => {
    'callId': callId,
    'initiatorId': initiatorId,
    'initiatorName': initiatorName,
    'initiatorProfilePic': initiatorProfilePic,
    'receiverId': receiverId,
    'receiverName': receiverName,
    'receiverProfilePic': receiverProfilePic,
    'initiatedAt': initiatedAt.millisecondsSinceEpoch,
    'answeredAt': answeredAt?.millisecondsSinceEpoch,
    'endedAt': endedAt?.millisecondsSinceEpoch,
    'callType': callType,
    'status': status,
    'durationSeconds': durationSeconds,
    'endReason': endReason,
  };

  factory CallModel.fromJson(Map<String, dynamic> json) => CallModel(
    callId: json['callId'] as String,
    initiatorId: json['initiatorId'] as String,
    initiatorName: json['initiatorName'] as String,
    initiatorProfilePic: json['initiatorProfilePic'] as String? ?? '',
    receiverId: json['receiverId'] as String,
    receiverName: json['receiverName'] as String,
    receiverProfilePic: json['receiverProfilePic'] as String? ?? '',
    initiatedAt: DateTime.fromMillisecondsSinceEpoch(
      json['initiatedAt'] as int,
    ),
    answeredAt: json['answeredAt'] != null
        ? DateTime.fromMillisecondsSinceEpoch(json['answeredAt'] as int)
        : null,
    endedAt: json['endedAt'] != null
        ? DateTime.fromMillisecondsSinceEpoch(json['endedAt'] as int)
        : null,
    callType: json['callType'] as String,
    status: json['status'] as String,
    durationSeconds: json['durationSeconds'] as int? ?? 0,
    endReason: json['endReason'] as String?,
  );
}
