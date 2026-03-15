import 'package:flutter_test/flutter_test.dart';
import 'package:whatsapp_clone/chat/call_service_utils.dart';
import 'package:whatsapp_clone/models/call_model.dart';

void main() {
  group('CallModel', () {
    test('toJson and fromJson keep core fields', () {
      final initiatedAt = DateTime.fromMillisecondsSinceEpoch(1700000000000);
      final answeredAt = initiatedAt.add(const Duration(seconds: 5));
      final endedAt = answeredAt.add(const Duration(minutes: 2));

      final model = CallModel(
        callId: 'call_1',
        initiatorId: 'u1',
        initiatorName: 'Alice',
        initiatorProfilePic: 'alice.png',
        receiverId: 'u2',
        receiverName: 'Bob',
        receiverProfilePic: 'bob.png',
        initiatedAt: initiatedAt,
        answeredAt: answeredAt,
        endedAt: endedAt,
        callType: 'video',
        status: 'ended',
        durationSeconds: 120,
        endReason: 'user_ended',
        avgNetworkQuality: 2,
        avgBitrate: 845.5,
        wasAnswered: true,
      );

      final roundTrip = CallModel.fromJson(model.toJson());

      expect(roundTrip.callId, 'call_1');
      expect(roundTrip.callType, 'video');
      expect(roundTrip.status, 'ended');
      expect(roundTrip.durationSeconds, 120);
      expect(roundTrip.endReason, 'user_ended');
      expect(roundTrip.avgNetworkQuality, 2);
      expect(roundTrip.avgBitrate, 845.5);
      expect(roundTrip.wasAnswered, isTrue);
      expect(
        roundTrip.initiatedAt.millisecondsSinceEpoch,
        initiatedAt.millisecondsSinceEpoch,
      );
      expect(
        roundTrip.answeredAt?.millisecondsSinceEpoch,
        answeredAt.millisecondsSinceEpoch,
      );
      expect(
        roundTrip.endedAt?.millisecondsSinceEpoch,
        endedAt.millisecondsSinceEpoch,
      );
    });

    test('copyWith updates only provided values', () {
      final base = CallModel(
        callId: 'call_2',
        initiatorId: 'u1',
        initiatorName: 'Alice',
        initiatorProfilePic: '',
        receiverId: 'u2',
        receiverName: 'Bob',
        receiverProfilePic: '',
        initiatedAt: DateTime.fromMillisecondsSinceEpoch(1700000000000),
        callType: 'voice',
        status: 'ringing',
      );

      final updated = base.copyWith(status: 'active', durationSeconds: 30);

      expect(updated.callId, base.callId);
      expect(updated.callType, 'voice');
      expect(updated.status, 'active');
      expect(updated.durationSeconds, 30);
      expect(updated.receiverId, 'u2');
    });

    test('copyWith can clear nullable fields explicitly', () {
      final base = CallModel(
        callId: 'call_3',
        initiatorId: 'u1',
        initiatorName: 'Alice',
        initiatorProfilePic: 'alice.png',
        receiverId: 'u2',
        receiverName: 'Bob',
        receiverProfilePic: 'bob.png',
        initiatedAt: DateTime.fromMillisecondsSinceEpoch(1700000000000),
        answeredAt: DateTime.fromMillisecondsSinceEpoch(1700000005000),
        endedAt: DateTime.fromMillisecondsSinceEpoch(1700000010000),
        callType: CallType.video,
        status: CallStatus.ended,
        endReason: CallEndReason.userEnded,
        avgNetworkQuality: 2,
        avgBitrate: 512.0,
        wasAnswered: true,
      );

      final cleared = base.copyWith(
        answeredAt: null,
        endedAt: null,
        endReason: null,
        avgNetworkQuality: null,
        avgBitrate: null,
        wasAnswered: null,
      );

      expect(cleared.answeredAt, isNull);
      expect(cleared.endedAt, isNull);
      expect(cleared.endReason, isNull);
      expect(cleared.avgNetworkQuality, isNull);
      expect(cleared.avgBitrate, isNull);
      expect(cleared.wasAnswered, isFalse);
    });

    test(
      'fromJson preserves persisted wasAnswered when answeredAt is missing',
      () {
        final model = CallModel.fromJson({
          'callId': 'call_4',
          'initiatorId': 'u1',
          'initiatorName': 'Alice',
          'initiatorProfilePic': '',
          'receiverId': 'u2',
          'receiverName': 'Bob',
          'receiverProfilePic': '',
          'initiatedAt': '1700000000000',
          'callType': CallType.voice,
          'status': CallStatus.ended,
          'durationSeconds': '42',
          'wasAnswered': true,
        });

        expect(model.wasAnswered, isTrue);
        expect(model.answeredAt, isNull);
        expect(model.durationSeconds, 42);
        expect(model.isVoiceCall, isTrue);
        expect(model.hasDuration, isTrue);
      },
    );

    test('fromJson parses string bitrate values', () {
      final model = CallModel.fromJson({
        'callId': 'call_4b',
        'initiatorId': 'u1',
        'initiatorName': 'Alice',
        'initiatorProfilePic': '',
        'receiverId': 'u2',
        'receiverName': 'Bob',
        'receiverProfilePic': '',
        'initiatedAt': '1700000000000',
        'callType': CallType.voice,
        'status': CallStatus.ended,
        'avgBitrate': '845.5',
      });

      expect(model.avgBitrate, 845.5);
    });

    test('copyWith accepts integer bitrate values', () {
      final base = CallModel(
        callId: 'call_4c',
        initiatorId: 'u1',
        initiatorName: 'Alice',
        initiatorProfilePic: '',
        receiverId: 'u2',
        receiverName: 'Bob',
        receiverProfilePic: '',
        initiatedAt: DateTime.fromMillisecondsSinceEpoch(1700000000000),
        callType: CallType.voice,
        status: CallStatus.active,
      );

      final updated = base.copyWith(avgBitrate: 512);

      expect(updated.avgBitrate, 512.0);
    });

    test(
      'helper getters expose direction and termination state consistently',
      () {
        final model = CallModel(
          callId: 'call_5',
          initiatorId: 'u1',
          initiatorName: 'Alice',
          initiatorProfilePic: '',
          receiverId: 'u2',
          receiverName: 'Bob',
          receiverProfilePic: '',
          initiatedAt: DateTime.fromMillisecondsSinceEpoch(1700000000000),
          callType: CallType.video,
          status: CallStatus.ended,
          endReason: CallEndReason.rejected,
        );

        expect(model.isOutgoing('u1'), isTrue);
        expect(model.isIncoming('u2'), isTrue);
        expect(model.getOtherUserId('u1'), 'u2');
        expect(model.getOtherUserName('u2'), 'Alice');
        expect(model.getDirection('u1'), 'outgoing');
        expect(model.isVideoCall, isTrue);
        expect(model.endedWithRejection, isTrue);
        expect(model.hasEnded, isTrue);
        expect(model.isActive, isFalse);
      },
    );

    test('hasEnded is true for missed and rejected calls', () {
      final missed = CallModel(
        callId: 'call_6',
        initiatorId: 'u1',
        initiatorName: 'Alice',
        initiatorProfilePic: '',
        receiverId: 'u2',
        receiverName: 'Bob',
        receiverProfilePic: '',
        initiatedAt: DateTime.fromMillisecondsSinceEpoch(1700000000000),
        callType: CallType.voice,
        status: CallStatus.missed,
      );
      final rejected = missed.copyWith(
        callId: 'call_7',
        status: CallStatus.rejected,
      );

      expect(missed.hasEnded, isTrue);
      expect(rejected.hasEnded, isTrue);
    });
  });
}
