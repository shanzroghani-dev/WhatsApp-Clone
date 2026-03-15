/// Call status constants
class CallStatus {
  static const String ringing = 'ringing';
  static const String active = 'active';
  static const String ended = 'ended';
  static const String missed = 'missed';
  static const String rejected = 'rejected';
}

/// Call end reason constants
class CallEndReason {
  static const String userEnded = 'user_ended';
  static const String noAnswer = 'no_answer';
  static const String rejected = 'rejected';
  static const String networkError = 'network_error';
}

/// Call type constants
class CallType {
  static const String voice = 'voice';
  static const String video = 'video';
}

// Backwards compatibility
const String timeoutEndReason = CallEndReason.noAnswer;

/// Returns true only when a call is still unanswered and should be auto-ended.
bool shouldAutoEndAsNoAnswer({
  required String status,
  required DateTime? answeredAt,
}) {
  return status == CallStatus.ringing && answeredAt == null;
}

/// Returns true if call should be shown in call history
bool isCallEnded(String status) {
  return status == CallStatus.ended;
}

/// Returns true if call is currently ringing or active
bool isCallActive(String status) {
  return status == CallStatus.ringing || status == CallStatus.active;
}

/// Returns true if call was missed or rejected
bool isCallMissedOrRejected(String status) {
  return status == CallStatus.missed || status == CallStatus.rejected;
}

/// Duration is measured from answer time; unanswered calls are zero-length.
int calculateDurationSeconds({
  required DateTime now,
  required DateTime? answeredAt,
}) {
  if (answeredAt == null) {
    return 0;
  }

  final seconds = now.difference(answeredAt).inSeconds;
  return seconds < 0 ? 0 : seconds;
}
