import 'package:firebase_database/firebase_database.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:uuid/uuid.dart';
import 'package:whatsapp_clone/models/call_model.dart';

class CallService {
  static final FirebaseDatabase _rtdb = FirebaseDatabase.instance;
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static final FirebaseFunctions _functions = FirebaseFunctions.instance;
  static const String _callsCollection = 'calls';
  static const String _callHistoryCollection = 'call_history';

  /// Get Agora token from Cloud Function
  static Future<String> getAgoraToken({
    required String channelName,
    required int uid,
    String role = 'publisher',
  }) async {
    try {
      final callable = _functions.httpsCallable('generateCallToken');
      final result = await callable.call({'callId': channelName, 'uid': uid});

      print('[CallService] Agora token obtained for channel: $channelName');
      return result.data['token'] as String;
    } catch (e) {
      print('[CallService] Error getting Agora token: $e');
      throw Exception('Failed to get Agora token: $e');
    }
  }

  /// Initiate a call to a user
  static Future<CallModel> initiateCall({
    required String initiatorId,
    required String initiatorName,
    required String initiatorProfilePic,
    required String receiverId,
    required String receiverName,
    required String receiverProfilePic,
    required String callType, // 'voice' or 'video'
    String? agoraToken, // Optional - will be generated if not provided
  }) async {
    try {
      final callId = const Uuid().v4();
      final now = DateTime.now();

      // Generate token if not provided
      final token =
          agoraToken ??
          await getAgoraToken(
            channelName: callId,
            uid: initiatorId.hashCode % 100000,
          );

      final callData = {
        'callId': callId,
        'initiatorId': initiatorId,
        'initiatorName': initiatorName,
        'initiatorProfilePic': initiatorProfilePic,
        'receiverId': receiverId,
        'receiverName': receiverName,
        'receiverProfilePic': receiverProfilePic,
        'callType': callType,
        'status': 'ringing',
        'initiatedAt': now.millisecondsSinceEpoch,
        'agoraToken': token,
        'agoraChannel': callId,
        'initiatorUid': initiatorId.hashCode % 100000,
        'receiverUid': receiverId.hashCode % 100000,
      };

      // Save to Firestore
      await _firestore.collection(_callsCollection).doc(callId).set(callData);

      // Also save to RTDB for real-time updates
      await _rtdb.ref('active_calls/$callId').set(callData);

      print('[CallService] Call initiated: $callId');

      return CallModel(
        callId: callId,
        initiatorId: initiatorId,
        initiatorName: initiatorName,
        initiatorProfilePic: initiatorProfilePic,
        receiverId: receiverId,
        receiverName: receiverName,
        receiverProfilePic: receiverProfilePic,
        initiatedAt: now,
        callType: callType,
        status: 'ringing',
      );
    } catch (e) {
      print('[CallService] Error initiating call: $e');
      rethrow;
    }
  }

  /// Accept a call
  static Future<void> acceptCall({
    required String callId,
    required String receiverId,
  }) async {
    try {
      final now = DateTime.now();

      // Update in Firestore
      await _firestore.collection(_callsCollection).doc(callId).update({
        'status': 'active',
        'answeredAt': now.millisecondsSinceEpoch,
      });

      // Update in RTDB
      await _rtdb.ref('active_calls/$callId').update({
        'status': 'active',
        'answeredAt': now.millisecondsSinceEpoch,
      });

      print('[CallService] Call accepted: $callId');
    } catch (e) {
      print('[CallService] Error accepting call: $e');
      rethrow;
    }
  }

  /// Reject/Decline a call
  static Future<void> rejectCall({
    required String callId,
    required String initiatorId,
  }) async {
    try {
      await endCall(callId: callId, endReason: 'rejected');
      print('[CallService] Call rejected: $callId');
    } catch (e) {
      print('[CallService] Error rejecting call: $e');
      rethrow;
    }
  }

  /// End a call
  static Future<CallModel> endCall({
    required String callId,
    required String endReason,
  }) async {
    try {
      final now = DateTime.now();

      // Get call data for calculation
      final callSnap = await _firestore
          .collection(_callsCollection)
          .doc(callId)
          .get();

      if (!callSnap.exists) {
        throw Exception('Call not found');
      }

      final callData = callSnap.data()!;
      final initiatedAt = DateTime.fromMillisecondsSinceEpoch(
        callData['initiatedAt'] as int,
      );
      final answeredAt = callData['answeredAt'] != null
          ? DateTime.fromMillisecondsSinceEpoch(callData['answeredAt'] as int)
          : null;

      // Calculate duration in seconds
      final durationSeconds = answeredAt != null
          ? now.difference(answeredAt).inSeconds
          : 0;

      // Update call status
      await _firestore.collection(_callsCollection).doc(callId).update({
        'status': 'ended',
        'endedAt': now.millisecondsSinceEpoch,
        'endReason': endReason,
        'durationSeconds': durationSeconds,
      });

      // Save to call history
      await _firestore.collection(_callHistoryCollection).add({
        ...callData,
        'status': 'ended',
        'endedAt': now.millisecondsSinceEpoch,
        'endReason': endReason,
        'durationSeconds': durationSeconds,
      });

      // Remove from active calls
      await _rtdb.ref('active_calls/$callId').remove();

      print('[CallService] Call ended: $callId, duration: $durationSeconds s');

      return CallModel(
        callId: callId,
        initiatorId: callData['initiatorId'] as String,
        initiatorName: callData['initiatorName'] as String,
        initiatorProfilePic: callData['initiatorProfilePic'] as String? ?? '',
        receiverId: callData['receiverId'] as String,
        receiverName: callData['receiverName'] as String,
        receiverProfilePic: callData['receiverProfilePic'] as String? ?? '',
        initiatedAt: initiatedAt,
        answeredAt: answeredAt,
        endedAt: now,
        callType: callData['callType'] as String,
        status: 'ended',
        durationSeconds: durationSeconds,
        endReason: endReason,
      );
    } catch (e) {
      print('[CallService] Error ending call: $e');
      rethrow;
    }
  }

  /// Listen for incoming calls
  static Stream<CallModel> listenForIncomingCalls(String userId) {
    return _firestore
        .collection(_callsCollection)
        .where('receiverId', isEqualTo: userId)
        .where('status', isEqualTo: 'ringing')
        .snapshots()
        .map((snapshot) {
          if (snapshot.docs.isEmpty) {
            throw Exception('No incoming call');
          }
          final doc = snapshot.docs.first;
          return CallModel.fromJson({...doc.data(), 'docId': doc.id});
        })
        .distinct();
  }

  /// Get call history for a user
  static Future<List<CallModel>> getCallHistory({
    required String userId,
    required int limit,
  }) async {
    try {
      final snapshot = await _firestore
          .collection(_callHistoryCollection)
          .where('initiatorId', isEqualTo: userId)
          .orderBy('initiatedAt', descending: true)
          .limit(limit)
          .get();

      final calls = snapshot.docs
          .map((doc) => CallModel.fromJson(doc.data()))
          .toList();

      print('[CallService] Retrieved ${calls.length} call history records');
      return calls;
    } catch (e) {
      print('[CallService] Error getting call history: $e');
      return [];
    }
  }

  /// Get call by ID
  static Future<CallModel?> getCall(String callId) async {
    try {
      final snapshot = await _firestore
          .collection(_callsCollection)
          .doc(callId)
          .get();

      if (!snapshot.exists) {
        return null;
      }

      return CallModel.fromJson(snapshot.data()!);
    } catch (e) {
      print('[CallService] Error getting call: $e');
      return null;
    }
  }

  /// Check if there's an active call
  static Future<bool> isCallActive(String callId) async {
    try {
      final snapshot = await _rtdb.ref('active_calls/$callId').get();
      return snapshot.exists;
    } catch (e) {
      print('[CallService] Error checking call status: $e');
      return false;
    }
  }
}
