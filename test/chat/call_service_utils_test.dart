import 'package:flutter_test/flutter_test.dart';
import 'package:whatsapp_clone/chat/call_service_utils.dart';

void main() {
  group('shouldAutoEndAsNoAnswer', () {
    test('returns true only for ringing and unanswered call', () {
      expect(
        shouldAutoEndAsNoAnswer(status: 'ringing', answeredAt: null),
        isTrue,
      );
      expect(
        shouldAutoEndAsNoAnswer(
          status: 'ringing',
          answeredAt: DateTime.fromMillisecondsSinceEpoch(1),
        ),
        isFalse,
      );
      expect(
        shouldAutoEndAsNoAnswer(status: 'active', answeredAt: null),
        isFalse,
      );
    });
  });

  group('calculateDurationSeconds', () {
    test('returns zero for unanswered calls', () {
      final now = DateTime.fromMillisecondsSinceEpoch(10000);
      expect(calculateDurationSeconds(now: now, answeredAt: null), 0);
    });

    test('returns elapsed seconds for answered calls', () {
      final answeredAt = DateTime.fromMillisecondsSinceEpoch(10000);
      final now = DateTime.fromMillisecondsSinceEpoch(25500);
      expect(calculateDurationSeconds(now: now, answeredAt: answeredAt), 15);
    });

    test('guards against negative values when clocks drift', () {
      final answeredAt = DateTime.fromMillisecondsSinceEpoch(20000);
      final now = DateTime.fromMillisecondsSinceEpoch(15000);
      expect(calculateDurationSeconds(now: now, answeredAt: answeredAt), 0);
    });
  });

  test('timeout end reason is no_answer', () {
    expect(timeoutEndReason, 'no_answer');
  });
}
