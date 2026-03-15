import 'package:flutter_test/flutter_test.dart';
import 'package:whatsapp_clone/models/message_model.dart';

void main() {
  group('MessageModel', () {
    test('fromJson applies defaults for optional flags', () {
      final model = MessageModel.fromJson({
        'id': 'm1',
        'fromId': 'u1',
        'toId': 'u2',
        'text': 'hello',
        'timestamp': 1700000000000,
      });

      expect(model.delivered, isFalse);
      expect(model.read, isFalse);
      expect(model.deliveredAt, isNull);
      expect(model.readAt, isNull);
    });

    test('copyWith updates delivery/read status', () {
      final base = MessageModel(
        id: 'm2',
        fromId: 'u1',
        toId: 'u2',
        text: 'ping',
        timestamp: 1700000000000,
      );

      final updated = base.copyWith(
        delivered: true,
        deliveredAt: 1700000001000,
        read: true,
        readAt: 1700000002000,
      );

      expect(updated.id, 'm2');
      expect(updated.delivered, isTrue);
      expect(updated.read, isTrue);
      expect(updated.deliveredAt, 1700000001000);
      expect(updated.readAt, 1700000002000);
    });
  });
}
