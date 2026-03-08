import 'package:flutter/material.dart';
import 'package:whatsapp_clone/models/call_model.dart';
import 'package:whatsapp_clone/chat/call_service.dart';

class CallStateNotifier extends ChangeNotifier {
  CallModel? _activeCall;
  List<CallModel> _callHistory = [];
  bool _isLoading = false;

  CallModel? get activeCall => _activeCall;
  List<CallModel> get callHistory => _callHistory;
  bool get isLoading => _isLoading;

  void setActiveCall(CallModel call) {
    _activeCall = call;
    notifyListeners();
  }

  void updateCallStatus(String status) {
    if (_activeCall != null) {
      _activeCall = _activeCall!.copyWith(status: status);
      notifyListeners();
    }
  }

  void clearActiveCall() {
    _activeCall = null;
    notifyListeners();
  }

  Future<void> loadCallHistory({required String userId}) async {
    _isLoading = true;
    notifyListeners();

    try {
      _callHistory = await CallService.getCallHistory(
        userId: userId,
        limit: 50,
      );
    } catch (e) {
      print('[CallProvider] Error loading history: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> endCall({
    required String callId,
    required String endReason,
  }) async {
    try {
      await CallService.endCall(callId: callId, endReason: endReason);
      clearActiveCall();
    } catch (e) {
      print('[CallProvider] Error ending call: $e');
    }
  }
}

class IncomingCallNotifier extends ChangeNotifier {
  CallModel? _incomingCall;

  IncomingCallNotifier();

  CallModel? get incomingCall => _incomingCall;

  void setIncomingCall(CallModel call) {
    _incomingCall = call;
    notifyListeners();
  }

  void clearIncomingCall() {
    _incomingCall = null;
    notifyListeners();
  }

  Future<void> acceptCall({required String userId}) async {
    if (_incomingCall != null) {
      try {
        await CallService.acceptCall(
          callId: _incomingCall!.callId,
          receiverId: userId,
        );
        _incomingCall = _incomingCall!.copyWith(status: 'active');
        notifyListeners();
      } catch (e) {
        print('[IncomingCallNotifier] Error accepting call: $e');
      }
    }
  }

  Future<void> rejectCall() async {
    if (_incomingCall != null) {
      try {
        await CallService.rejectCall(
          callId: _incomingCall!.callId,
          initiatorId: _incomingCall!.initiatorId,
        );
        clearIncomingCall();
      } catch (e) {
        print('[IncomingCallNotifier] Error rejecting call: $e');
      }
    }
  }
}
