// Core constants and configuration
class AppConstants {
  // Firebase paths
  static const String usersCollection = 'users';
  static const String usernamesCollection = 'usernames';
  static const String messagesPath = 'messages';
  static const String usernamesPath = 'usernames';

  // Encryption
  static const int aesKeySize = 32; // 256-bit key
  static const int ivSize = 16; // 128-bit IV

  // Message TTL
  static const Duration messageTTL = Duration(hours: 24);

  // Local storage tables
  static const String localMessagesTable = 'messages';
  static const String localProfilesTable = 'user_profiles';
  static const String localOutgoingQueueTable = 'outgoing_queue';
  static const String localChatListTable = 'chat_list';

  // UI
  static const int pageTransitionDuration = 300; // ms
  static const double defaultPadding = 16.0;
  static const double defaultBorderRadius = 8.0;
}
