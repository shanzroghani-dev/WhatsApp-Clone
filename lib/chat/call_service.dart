import 'dart:async';
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
  static const int _callTimeoutSeconds = 60; // 1 minute before call times out

  // Track active call timeout timers to cancel them when call is answered/rejected
  static final Map<String, Timer> _callTimeoutTimers = {};
  static final Set<String> _cancelledCalls = {}; // Track calls already cancelled

  /// Get Agora token from Cloud Function
  static Future<String> getAgoraToken({
    required String channelName,
    required int uid,
    String role = 'publisher',
  }) async {
    try {
      final callable = _functions.httpsCallable('generateCallToken');
      final result = await callable
          .call({'callId': channelName, 'uid': uid})
          .timeout(
            const Duration(seconds: 15),
            onTimeout: () {
              throw TimeoutException(
                'Agora token generation timed out after 15 seconds',
                const Duration(seconds: 15),
              );
            },
          );

      print('[CallService] Agora token obtained for channel: $channelName');
      return result.data['token'] as String;
    } on TimeoutException catch (e) {
      print('[CallService] Timeout getting Agora token: $e');
      throw Exception('Agora token request timed out. Please check your connection.');
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

      // Set timeout for unanswered call (60 seconds)
      _setCallTimeout(callId, initiatorId);

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

  /// Set timeout for unanswered call
  static void _setCallTimeout(String callId, String initiatorId) {
    // Cancel any existing timer for this call
    _callTimeoutTimers[callId]?.cancel();

    // Set new timeout timer
    _callTimeoutTimers[callId] = Timer(
      const Duration(seconds: _callTimeoutSeconds),
      () async {
        if (_cancelledCalls.contains(callId)) {
          print('[CallService] Call $callId already cancelled, skipping timeout');
          return;
        }

        print('[CallService] ⏱️ Call timeout triggered for $callId');
        _cancelledCalls.add(callId);

        try {
          // Auto-end the call with 'no_answer' reason
          await endCall(callId: callId, endReason: 'no_answer');
          print('[CallService] ✅ Call auto-ended due to timeout: $callId');
        } catch (e) {
          print('[CallService] ❌ Error auto-ending call on timeout: $e');
        }

        // Cleanup
        _callTimeoutTimers.remove(callId);
      },
    );

    print('[CallService] ⏲️ Call timeout set for $callId (${_callTimeoutSeconds}s)');
  }

  /// Cancel timeout for a call (when it's answered or rejected)
  static void _cancelCallTimeout(String callId) {
    _callTimeoutTimers[callId]?.cancel();
    _callTimeoutTimers.remove(callId);
    _cancelledCalls.remove(callId);
    print('[CallService] 🛑 Call timeout cancelled for $callId');
  }

  /// Accept a call
  static Future<void> acceptCall({
    required String callId,
    required String receiverId,
  }) async {
    try {
      final now = DateTime.now();

      // Cancel the timeout timer since call is being accepted
      _cancelCallTimeout(callId);

      // Update in Firestore with timeout
      await _firestore
          .collection(_callsCollection)
          .doc(callId)
          .update({
            'status': 'active',
            'answeredAt': now.millisecondsSinceEpoch,
          })
          .timeout(
            const Duration(seconds: 10),
            onTimeout: () {
              throw TimeoutException(
                'Firestore update timed out',
                const Duration(seconds: 10),
              );
            },
          );

      // Update in RTDB with timeout
      await _rtdb
          .ref('active_calls/$callId')
          .update({
            'status': 'active',
            'answeredAt': now.millisecondsSinceEpoch,
          })
          .timeout(
            const Duration(seconds: 10),
            onTimeout: () {
              throw TimeoutException(
                'RTDB update timed out',
                const Duration(seconds: 10),
              );
            },
          );

      print('[CallService] Call accepted: $callId');
    } on TimeoutException catch (e) {
      print('[CallService] Timeout accepting call: $e');
      throw Exception('Failed to accept call (timeout). Please try again.');
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
      // Cancel the timeout timer since call is being rejected
      _cancelCallTimeout(callId);
      
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

      // Cancel the timeout timer if it exists
      _cancelCallTimeout(callId);

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

      // Save to call history (using callId as document ID to prevent duplicates)
      await _firestore.collection(_callHistoryCollection).doc(callId).set({
        ...callData,
        'status': 'ended',
        'endedAt': now.millisecondsSinceEpoch,
        'endReason': endReason,
        'durationSeconds': durationSeconds,
        'wasAnswered': answeredAt != null,
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
        .where((snapshot) => snapshot.docs.isNotEmpty)
        .map((snapshot) {
          final doc = snapshot.docs.first;
          return CallModel.fromJson({...doc.data(), 'docId': doc.id});
        })
        .distinct();
  }

  /// Listen to a specific call's status changes
  static Stream<CallModel?> listenToCall(String callId) {
    return _firestore
        .collection(_callsCollection)
        .doc(callId)
        .snapshots()
        .map((snapshot) {
          if (!snapshot.exists) return null;
          return CallModel.fromJson({...snapshot.data()!, 'docId': snapshot.id});
        });
  }

  /// Get call history for a user
  static Future<List<CallModel>> getCallHistory({
    required String userId,
    required int limit,
  }) async {
    try {
      // Query for calls where user is the initiator
      final initiatorSnapshot = await _firestore
          .collection(_callHistoryCollection)
          .where('initiatorId', isEqualTo: userId)
          .orderBy('initiatedAt', descending: true)
          .limit(limit)
          .get();

      // Query for calls where user is the receiver
      final receiverSnapshot = await _firestore
          .collection(_callHistoryCollection)
          .where('receiverId', isEqualTo: userId)
          .orderBy('initiatedAt', descending: true)
          .limit(limit)
          .get();

      // Combine both lists
      final allCalls = <CallModel>[];
      
      allCalls.addAll(
          initiatorSnapshot.docs.map((doc) => CallModel.fromJson(doc.data())));
      allCalls.addAll(
          receiverSnapshot.docs.map((doc) => CallModel.fromJson(doc.data())));

      // Remove duplicates (if any) and sort by date
      final uniqueCalls = <String, CallModel>{};
      for (final call in allCalls) {
        uniqueCalls[call.callId] = call;
      }

      final sortedCalls = uniqueCalls.values.toList()
        ..sort((a, b) => b.initiatedAt.compareTo(a.initiatedAt));

      // Apply limit after merging
      final result = sortedCalls.take(limit).toList();

      print('[CallService] Retrieved ${result.length} call history records');
      return result;
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
          .get()
          .timeout(
            const Duration(seconds: 10),
            onTimeout: () {
              throw TimeoutException(
                'Firestore query timed out',
                const Duration(seconds: 10),
              );
            },
          );

      if (!snapshot.exists) {
        return null;
      }

      return CallModel.fromJson(snapshot.data()!);
    } on TimeoutException catch (e) {
      print('[CallService] Timeout getting call: $e');
      return null;
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
