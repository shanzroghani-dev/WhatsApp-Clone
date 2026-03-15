import 'package:flutter_test/flutter_test.dart';
import 'package:whatsapp_clone/models/message_model.dart';
import 'package:whatsapp_clone/providers/messages_provider.dart';

MessageModel _msg({required String id, required int ts}) {
  return MessageModel(
    id: id,
    fromId: 'u1',
    toId: 'u2',
    text: id,
    timestamp: ts,
  );
}

void main() {
  group('MessagesStateNotifier', () {
    test('setMessages keeps pending temp messages and sorts timeline', () {
      final notifier = MessagesStateNotifier();

      notifier.insertMessage(_msg(id: 'temp_1', ts: 300));
      notifier.setMessages([
        _msg(id: 'db_2', ts: 200),
        _msg(id: 'db_1', ts: 100),
      ]);

      expect(notifier.messages.map((m) => m.id).toList(), ['db_1', 'db_2', 'temp_1']);
      expect(notifier.visibleCount, 3);
      expect(notifier.initialLoadComplete, isTrue);
    });

    test('insertMessage triggers callback for temp and uploading IDs', () {
      final notifier = MessagesStateNotifier();
      var callbackCount = 0;
      notifier.setOnTempMessageInserted(() => callbackCount++);

      notifier.insertMessage(_msg(id: 'normal_1', ts: 100));
      notifier.insertMessage(_msg(id: 'temp_1', ts: 110));
      notifier.insertMessage(_msg(id: 'uploading_1', ts: 120));

      expect(callbackCount, 2);
    });

    test('removeMessage adjusts visibleCount only when removed message is visible', () {
      final notifier = MessagesStateNotifier();
      notifier.setMessages([
        _msg(id: 'a', ts: 100),
        _msg(id: 'b', ts: 200),
      ]);

      notifier.decrementVisibleCount(); // 1 visible
      expect(notifier.visibleCount, 1);

      notifier.removeMessage('b'); // removing hidden message should not decrement
      expect(notifier.visibleCount, 1);

      notifier.removeMessage('a'); // removing visible message should decrement
      expect(notifier.visibleCount, 0);
    });
  });

  group('MessagesProviderManager', () {
    test('getChatKey is order-independent', () {
      final key1 = MessagesProviderManager.getChatKey('u1', 'u2');
      final key2 = MessagesProviderManager.getChatKey('u2', 'u1');

      expect(key1, key2);
      expect(key1, 'u1_u2');
    });
  });
}
