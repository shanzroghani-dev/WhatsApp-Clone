import 'package:flutter/foundation.dart';
import 'package:whatsapp_clone/chat/chat_service.dart';
import 'package:whatsapp_clone/models/message_model.dart';

/// Global manager for Messages providers (one per chat conversation)
class MessagesProviderManager {
  static final MessagesProviderManager _instance =
      MessagesProviderManager._internal();
  factory MessagesProviderManager() => _instance;
  MessagesProviderManager._internal();

  final Map<String, MessagesStateNotifier> _providers = {};

  /// Get or create a messages provider for a specific chat
  /// Loads messages from local DB immediately if creating new provider
  MessagesStateNotifier getProvider(
    String chatKey,
    String userId1,
    String userId2,
  ) {
    if (!_providers.containsKey(chatKey)) {
      final provider = MessagesStateNotifier();
      _providers[chatKey] = provider;
      // Load messages from local DB immediately
      provider.loadFromLocalDB(userId1, userId2);
    }
    return _providers[chatKey]!;
  }

  /// Generate a unique chat key from two user IDs
  static String getChatKey(String userId1, String userId2) {
    final sorted = [userId1, userId2]..sort();
    return '${sorted[0]}_${sorted[1]}';
  }

  /// Optional: Clear a specific chat's provider (when logging out, etc.)
  void clearProvider(String chatKey) {
    _providers[chatKey]?.dispose();
    _providers.remove(chatKey);
  }

  /// Optional: Clear all providers
  void clearAll() {
    for (var provider in _providers.values) {
      provider.dispose();
    }
    _providers.clear();
  }
}

/// Messages state notifier
class MessagesStateNotifier extends ChangeNotifier {
  List<MessageModel> _messages = [];
  int _visibleCount = 0;
  bool _initialLoadComplete = false;

  // Callback for temp message insertion
  VoidCallback? _onTempMessageInserted;

  // Getters
  List<MessageModel> get messages => _messages;
  int get visibleCount => _visibleCount;
  bool get initialLoadComplete => _initialLoadComplete;

  /// Set callback to be called when temp message is inserted
  void setOnTempMessageInserted(VoidCallback? callback) {
    _onTempMessageInserted = callback;
  }

  List<MessageModel> get visibleMessages {
    return _messages.take(_visibleCount).toList();
  }

  /// Load messages from local database immediately (eager loading)
  Future<void> loadFromLocalDB(String userId1, String userId2) async {
    try {
      final messages = await ChatService.getMessagesBetween(userId1, userId2);
      // Always preserve pending messages that might have been added
      setMessages(messages);
    } catch (e) {
      // Mark as loaded even on error to prevent hanging
      _initialLoadComplete = true;
      notifyListeners();
    }
  }

  // Setters
  void setMessages(List<MessageModel> messages) {
    // Preserve temporary/pending messages that are not yet in database.
    final databaseIds = messages.map((m) => m.id).toSet();
    final pendingMessages = _messages.where((m) {
      final isPending =
          m.id.startsWith('temp_') || m.id.startsWith('uploading_');
      return isPending && !databaseIds.contains(m.id);
    }).toList();

    // Keep a stable ascending timeline (oldest -> newest).
    final merged = [...messages, ...pendingMessages]
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));

    _messages = merged;
    _visibleCount = _messages.length;
    _initialLoadComplete = true;
    notifyListeners();
  }

  void insertMessage(MessageModel message) {
    _messages.add(message);
    _messages.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    _visibleCount = (_visibleCount + 1).clamp(0, _messages.length);

    // Check if this is a temp message and call callback immediately
    if (message.id.startsWith('temp_') || message.id.startsWith('uploading_')) {
      _onTempMessageInserted?.call();
    }

    notifyListeners();
  }

  void removeMessage(String id) {
    final removedIndex = _messages.indexWhere((m) => m.id == id);
    if (removedIndex == -1) return;

    _messages.removeAt(removedIndex);
    // Only decrement visible count if removed message was visible
    if (removedIndex < _visibleCount) {
      _visibleCount = (_visibleCount - 1).clamp(0, _messages.length);
    }
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
