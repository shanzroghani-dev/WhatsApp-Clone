import 'package:flutter_test/flutter_test.dart';
import 'package:whatsapp_clone/providers/messages_provider.dart';

void main() {
  test('chat key stays deterministic for same user pair', () {
    final keyA = MessagesProviderManager.getChatKey('alice', 'bob');
    final keyB = MessagesProviderManager.getChatKey('bob', 'alice');

    expect(keyA, keyB);
    expect(keyA, 'alice_bob');
  });
}
