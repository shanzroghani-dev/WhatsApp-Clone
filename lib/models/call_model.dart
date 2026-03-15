import 'package:whatsapp_clone/chat/call_service_utils.dart';

const Object _unset = Object();

class CallModel {
  final String callId;
  final String initiatorId;
  final String initiatorName;
  final String initiatorProfilePic;
  final String receiverId;
  final String receiverName;
  final String receiverProfilePic;
  final DateTime initiatedAt;
  final DateTime? answeredAt;
  final DateTime? endedAt;
  final String callType; // 'voice' or 'video'
  final String status; // 'ringing', 'active', 'ended', 'missed', 'rejected'
  final int durationSeconds;
  final String?
  endReason; // 'user_ended', 'no_answer', 'rejected', 'network_error'
  final int?
  avgNetworkQuality; // 0-6 scale (0=Unknown, 1=Excellent, 6=Disconnected)
  final double? avgBitrate; // Average bitrate in kbps
  final bool? _wasAnswered;

  const CallModel({
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
    this.avgNetworkQuality,
    this.avgBitrate,
    bool? wasAnswered,
  }) : _wasAnswered = wasAnswered;

  /// Derived property: true if call was answered
  bool get wasAnswered => _wasAnswered ?? answeredAt != null;

  /// Check if this is an outgoing call for the given user
  bool isOutgoing(String currentUserId) => initiatorId == currentUserId;

  /// Check if this is an incoming call for the given user
  bool isIncoming(String currentUserId) => receiverId == currentUserId;

  /// Get the other party's user ID (not the current user)
  String getOtherUserId(String currentUserId) =>
      currentUserId == initiatorId ? receiverId : initiatorId;

  /// Get the other party's name (not the current user)
  String getOtherUserName(String currentUserId) =>
      currentUserId == initiatorId ? receiverName : initiatorName;

  /// Get the other party's profile picture (not the current user)
  String getOtherUserProfilePic(String currentUserId) =>
      currentUserId == initiatorId ? receiverProfilePic : initiatorProfilePic;

  /// Get call direction as a string
  String getDirection(String currentUserId) =>
      isOutgoing(currentUserId) ? 'outgoing' : 'incoming';

  /// Check if call is currently active (ringing or in progress)
  bool get isActive =>
      status == CallStatus.ringing || status == CallStatus.active;

  /// Check if call is a video call
  bool get isVideoCall => callType == CallType.video;

  /// Check if call is a voice call
  bool get isVoiceCall => callType == CallType.voice;

  /// Check if call has ended
  bool get hasEnded =>
      status == CallStatus.ended ||
      status == CallStatus.missed ||
      status == CallStatus.rejected;

  /// Check if the call has a non-zero tracked duration.
  bool get hasDuration => durationSeconds > 0;

  /// Check if call is missed
  bool get isMissed => status == CallStatus.missed;

  /// Check if call was rejected
  bool get wasRejected => status == CallStatus.rejected;

  /// Check if this call ended normally (user ended it)
  bool get endedByUser => endReason == CallEndReason.userEnded;

  /// Check if this call ended due to no answer (timeout)
  bool get endedWithNoAnswer => endReason == CallEndReason.noAnswer;

  /// Check if this call ended with rejection
  bool get endedWithRejection => endReason == CallEndReason.rejected;

  /// Check if this call ended with network error
  bool get endedWithNetworkError => endReason == CallEndReason.networkError;

  CallModel copyWith({
    String? callId,
    String? initiatorId,
    String? initiatorName,
    String? initiatorProfilePic,
    String? receiverId,
    String? receiverName,
    String? receiverProfilePic,
    DateTime? initiatedAt,
    Object? answeredAt = _unset,
    Object? endedAt = _unset,
    String? callType,
    String? status,
    int? durationSeconds,
    Object? endReason = _unset,
    Object? avgNetworkQuality = _unset,
    Object? avgBitrate = _unset,
    Object? wasAnswered = _unset,
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
      answeredAt: identical(answeredAt, _unset)
          ? this.answeredAt
          : answeredAt as DateTime?,
      endedAt: identical(endedAt, _unset) ? this.endedAt : endedAt as DateTime?,
      callType: callType ?? this.callType,
      status: status ?? this.status,
      durationSeconds: durationSeconds ?? this.durationSeconds,
      endReason: identical(endReason, _unset)
          ? this.endReason
          : endReason as String?,
      avgNetworkQuality: identical(avgNetworkQuality, _unset)
          ? this.avgNetworkQuality
          : avgNetworkQuality as int?,
      avgBitrate: identical(avgBitrate, _unset)
          ? this.avgBitrate
          : (avgBitrate as num?)?.toDouble(),
      wasAnswered: identical(wasAnswered, _unset)
          ? _wasAnswered
          : wasAnswered as bool?,
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
    'avgNetworkQuality': avgNetworkQuality,
    'avgBitrate': avgBitrate,
    'wasAnswered': wasAnswered,
  };

  factory CallModel.fromJson(Map<String, dynamic> json) => CallModel(
    callId: json['callId'] as String,
    initiatorId: json['initiatorId'] as String,
    initiatorName: json['initiatorName'] as String,
    initiatorProfilePic: json['initiatorProfilePic'] as String? ?? '',
    receiverId: json['receiverId'] as String,
    receiverName: json['receiverName'] as String,
    receiverProfilePic: json['receiverProfilePic'] as String? ?? '',
    initiatedAt: _dateTimeFromJson(json['initiatedAt'])!,
    answeredAt: _dateTimeFromJson(json['answeredAt']),
    endedAt: _dateTimeFromJson(json['endedAt']),
    callType: json['callType'] as String,
    status: json['status'] as String,
    durationSeconds: _intFromJson(json['durationSeconds']) ?? 0,
    endReason: json['endReason'] as String?,
    avgNetworkQuality: _intFromJson(json['avgNetworkQuality']),
    avgBitrate: _doubleFromJson(json['avgBitrate']),
    wasAnswered: json['wasAnswered'] as bool?,
  );

  static DateTime? _dateTimeFromJson(dynamic value) {
    if (value == null) {
      return null;
    }
    if (value is DateTime) {
      return value;
    }
    if (value is num) {
      return DateTime.fromMillisecondsSinceEpoch(value.toInt());
    }
    if (value is String) {
      final millis = int.tryParse(value);
      if (millis != null) {
        return DateTime.fromMillisecondsSinceEpoch(millis);
      }
      return DateTime.tryParse(value);
    }
    return null;
  }

  static int? _intFromJson(dynamic value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    if (value is String) {
      return int.tryParse(value);
    }
    return null;
  }

  static double? _doubleFromJson(dynamic value) {
    if (value is double) {
      return value;
    }
    if (value is num) {
      return value.toDouble();
    }
    if (value is String) {
      return double.tryParse(value);
    }
    return null;
  }

  @override
  String toString() {
    return 'CallModel(callId: $callId, status: $status, callType: $callType, durationSeconds: $durationSeconds)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    return other is CallModel &&
        other.callId == callId &&
        other.initiatorId == initiatorId &&
        other.receiverId == receiverId &&
        other.status == status &&
        other.callType == callType &&
        other.durationSeconds == durationSeconds &&
        other.initiatedAt == initiatedAt &&
        other.answeredAt == answeredAt &&
        other.endedAt == endedAt &&
        other.endReason == endReason &&
        other.avgNetworkQuality == avgNetworkQuality &&
        other.avgBitrate == avgBitrate &&
        other.wasAnswered == wasAnswered;
  }

  @override
  int get hashCode => Object.hash(
    callId,
    initiatorId,
    receiverId,
    status,
    callType,
    durationSeconds,
    initiatedAt,
    answeredAt,
    endedAt,
    endReason,
    avgNetworkQuality,
    avgBitrate,
    wasAnswered,
  );
}
