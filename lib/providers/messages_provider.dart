import 'package:flutter/foundation.dart';
import 'package:whatsapp_clone/models/message_model.dart';

/// Messages state notifier
class MessagesStateNotifier extends ChangeNotifier {
  List<MessageModel> _messages = [];
  int _visibleCount = 0;

  // Getters
  List<MessageModel> get messages => _messages;
  int get visibleCount => _visibleCount;
  
  List<MessageModel> get visibleMessages {
    return _messages.take(_visibleCount).toList();
  }

  // Setters
  void setMessages(List<MessageModel> messages) {
    _messages = messages;
    _visibleCount = messages.length;
    notifyListeners();
  }

  void insertMessage(MessageModel message) {
    _messages.insert(0, message);
    _visibleCount = (_visibleCount + 1).clamp(0, _messages.length);
    notifyListeners();
  }

  void removeMessage(String id) {
    _messages.removeWhere((m) => m.id == id);
    _visibleCount = (_visibleCount - 1).clamp(0, _messages.length);
    notifyListeners();
  }

  void updateMessage(MessageModel message) {
    final index = _messages.indexWhere((m) => m.id == message.id);
    if (index != -1) {
      _messages[index] = message;
      notifyListeners();
    }
  }

  void incrementVisibleCount() {
    _visibleCount = (_visibleCount + 1).clamp(0, _messages.length);
    notifyListeners();
  }

  void decrementVisibleCount() {
    _visibleCount = (_visibleCount - 1).clamp(0, _messages.length);
    notifyListeners();
  }

  void clear() {
    _messages = [];
    _visibleCount = 0;
    notifyListeners();
  }
}
