import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:whatsapp_clone/auth/auth_service.dart';
import 'package:whatsapp_clone/chat/chat_service.dart';
import 'package:whatsapp_clone/core/profile_service.dart';
import 'package:whatsapp_clone/models/user_model.dart';
import 'package:whatsapp_clone/providers/media_provider.dart';
import 'package:whatsapp_clone/providers/messages_provider.dart';
import 'package:whatsapp_clone/providers/recording_provider.dart';
import 'package:whatsapp_clone/providers/upload_provider.dart';
import 'package:whatsapp_clone/screens/chat/chat_screen.dart';
import 'package:whatsapp_clone/screens/search_users_screen.dart';
import 'package:whatsapp_clone/widgets/skeleton_loader.dart';
import 'package:whatsapp_clone/widgets/profile_avatar.dart';
import 'package:whatsapp_clone/core/design_tokens.dart';

class ChatListScreen extends StatefulWidget {
  const ChatListScreen({super.key});

  @override
  State<ChatListScreen> createState() => _ChatListScreenState();
}

class _ChatListScreenState extends State<ChatListScreen> {
  UserModel? _currentUser;
  List<UserModel> _users = [];
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  final Map<String, String> _lastMessageByUid = {};
  final Map<String, int> _unreadCounts = {};
  final Map<String, DateTime?> _lastMessageTimeByUid = {};
  StreamSubscription? _incomingSub;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadUsers();
    _updateOnlineStatus(true);
  }

  @override
  void dispose() {
    _incomingSub?.cancel();
    _searchController.dispose();
    _updateOnlineStatus(false);
    super.dispose();
  }

  List<UserModel> get _filteredUsers {
    if (_searchQuery.trim().isEmpty) return _users;
    final query = _searchQuery.toLowerCase();
    return _users.where((user) {
      final lastMessage = (_lastMessageByUid[user.uid] ?? '').toLowerCase();
      final name = user.displayName.toLowerCase();
      final status = user.status.toLowerCase();
      final tag = user.uniqueNumber.toLowerCase();
      return name.contains(query) ||
          status.contains(query) ||
          lastMessage.contains(query) ||
          tag.contains(query);
    }).toList();
  }

  String _formatMessageTime(DateTime? time) {
    if (time == null) return '';
    final now = DateTime.now();
    final difference = now.difference(time);

    if (difference.inMinutes < 1) return 'Now';
    if (difference.inMinutes < 60) return '${difference.inMinutes}m';
    if (difference.inHours < 24) return '${difference.inHours}h';
    if (difference.inDays == 1) return 'Yesterday';
    if (difference.inDays < 7) return '${difference.inDays}d';

    return '${time.day}/${time.month}';
  }

  String _truncateMessage(String message, int maxLength) {
    if (message.length <= maxLength) return message;
    return '${message.substring(0, maxLength)}..';
  }

  Future<void> _updateOnlineStatus(bool isOnline) async {
    final prefs = await SharedPreferences.getInstance();
    final shareOnlineStatus =
        prefs.getBool('privacy_show_online_status') ?? true;
    if (!shareOnlineStatus) {
      return;
    }

    final user = await AuthService.getCurrentUser();
    if (user != null) {
      await ProfileService.updateOnlineStatus(user.uid, isOnline);
    }
  }

  Future<void> _loadUsers() async {
    try {
      final me = await AuthService.getCurrentUser();
      if (me == null) {
        if (mounted) {
          Navigator.of(context).pushReplacementNamed('/login');
        }
        return;
      }

      _incomingSub ??= ChatService.streamIncomingForUser(me.uid).listen((
        message,
      ) {
        if (mounted) {
          // Increment unread count for this sender
          setState(() {
            final senderUid = message.fromId;
            _unreadCounts[senderUid] = (_unreadCounts[senderUid] ?? 0) + 1;
          });
          // Refresh to update last message
          _loadUsers();
        }
      });

      final chatEntries = await ChatService.getLocalChatList(me.uid);
      final users = <UserModel>[];
      _lastMessageByUid.clear();
      _lastMessageTimeByUid.clear();

      for (final entry in chatEntries) {
        final peerUid = entry['peerUID'] as String?;
        if (peerUid == null || peerUid.isEmpty) continue;

        final profile = await ProfileService.getProfile(peerUid);
        final peer =
            profile ??
            UserModel(
              uid: peerUid,
              uniqueNumber: peerUid.substring(0, 8),
              email: '',
              displayName: 'Unknown user',
              status: 'Tap to open chat',
            );

        users.add(peer);
        _lastMessageByUid[peerUid] = (entry['lastMessage'] as String?) ?? '';
        final lastTimestamp = (entry['lastTimestamp'] as int?) ?? 0;
        _lastMessageTimeByUid[peerUid] = lastTimestamp > 0
            ? DateTime.fromMillisecondsSinceEpoch(lastTimestamp)
            : null;
      }

      setState(() {
        _currentUser = me;
        _users = users.where((u) => u.uid != me.uid).toList();
        _loading = false;
      });
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  void _openChat(UserModel peer) {
    if (_currentUser == null) return;
    HapticFeedback.lightImpact();
    // Clear unread count when opening chat
    setState(() {
      _unreadCounts[peer.uid] = 0;
    });
    Navigator.of(context)
        .push(
          MaterialPageRoute(
            builder: (routeContext) {
              // Capture global providers from parent context
              final recordingProvider = Provider.of<RecordingStateNotifier>(
                context,
                listen: false,
              );
              final mediaProvider = Provider.of<MediaStateNotifier>(
                context,
                listen: false,
              );
              final uploadProvider = Provider.of<UploadStateNotifier>(
                context,
                listen: false,
              );

              // Get or create Messages provider for this chat conversation
              final chatKey = MessagesProviderManager.getChatKey(
                _currentUser!.uid,
                peer.uid,
              );
              final messagesProvider = MessagesProviderManager().getProvider(
                chatKey,
                _currentUser!.uid,
                peer.uid,
              );

              // Pass all providers to chat screen
              return MultiProvider(
                providers: [
                  ChangeNotifierProvider<RecordingStateNotifier>.value(
                    value: recordingProvider,
                  ),
                  ChangeNotifierProvider<MediaStateNotifier>.value(
                    value: mediaProvider,
                  ),
                  ChangeNotifierProvider<UploadStateNotifier>.value(
                    value: uploadProvider,
                  ),
                  ChangeNotifierProvider<MessagesStateNotifier>.value(
                    value: messagesProvider,
                  ),
                ],
                child: ChatScreen(currentUser: _currentUser!, peer: peer),
              );
            },
          ),
        )
        .then((_) => _loadUsers());
  }

  void _openSearch() {
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => SearchUsersScreen()))
        .then((_) => _loadUsers());
  }

  void _showDeleteChatDialog(UserModel user) {
    if (_currentUser == null) return;
    HapticFeedback.mediumImpact();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Chat'),
        content: Text('Delete this chat with ${user.displayName}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _deleteChatForMe(user);
            },
            child: const Text('Delete for Me'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _showDeleteForEveryoneConfirmation(user);
            },
            child: const Text(
              'Delete for Everyone',
              style: TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );
  }

  void _showDeleteForEveryoneConfirmation(UserModel user) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Chat for Everyone?'),
        content: Text(
          'This will delete all messages in this conversation for both you and ${user.displayName}.\n\nNote: Messages older than 5 minutes cannot be deleted.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _deleteChatForEveryone(user);
            },
            child: const Text(
              'Delete for Everyone',
              style: TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteChatForMe(UserModel user) async {
    if (_currentUser == null) return;

    try {
      print('[ChatList] Deleting chat for me: ${user.uid}');
      await ChatService.deleteConversationForMe(_currentUser!.uid, user.uid);

      if (mounted) {
        // Don't remove from cache - keep chat visible after deletion
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Chat with ${user.displayName} deleted')),
        );
      }
    } catch (e) {
      print('[ChatList] Error deleting chat for me: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error deleting chat: $e')));
      }
    }
  }

  Future<void> _deleteChatForEveryone(UserModel user) async {
    if (_currentUser == null) return;

    try {
      print('[ChatList] Deleting chat for everyone: ${user.uid}');
      await ChatService.deleteConversationForEveryone(
        _currentUser!.uid,
        user.uid,
      );

      if (mounted) {
        // Don't remove from cache - keep chat visible after deletion
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Chat with ${user.displayName} deleted for everyone'),
          ),
        );
      }
    } catch (e) {
      print('[ChatList] Error deleting chat for everyone: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final filteredUsers = _filteredUsers;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Chats'),
        actions: [
          IconButton(
            onPressed: _openSearch,
            icon: const Icon(Icons.person_search_rounded),
            tooltip: 'Find users',
          ),
        ],
      ),
      body: _loading
          ? const SkeletonLoader()
          : _users.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.xxxl),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 120,
                      height: 120,
                      decoration: BoxDecoration(
                        gradient: AppColors.primaryGradient,
                        shape: BoxShape.circle,
                        boxShadow: [AppShadows.coloredShadow(AppColors.accent)],
                      ),
                      child: const Icon(
                        Icons.chat_bubble_rounded,
                        size: 60,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xxxl),
                    Text(
                      'No chats yet',
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: isDark
                            ? AppColors.darkText
                            : AppColors.lightText,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    Text(
                      'Find users and start chatting!',
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: isDark
                            ? AppColors.darkTextSecondary
                            : AppColors.lightTextSecondary,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: AppSpacing.xxxl),
                    Container(
                      height: 56,
                      decoration: BoxDecoration(
                        gradient: AppColors.primaryGradient,
                        borderRadius: BorderRadius.circular(AppRadius.sm),
                        boxShadow: [AppShadows.coloredShadow(AppColors.accent)],
                      ),
                      child: ElevatedButton.icon(
                        onPressed: _openSearch,
                        icon: const Icon(
                          Icons.search_rounded,
                          color: Colors.white,
                        ),
                        label: const Text(
                          'Find Users',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 16,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.transparent,
                          shadowColor: Colors.transparent,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(AppRadius.sm),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            )
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.lg,
                    AppSpacing.md,
                    AppSpacing.lg,
                    AppSpacing.sm,
                  ),
                  child: Container(
                    decoration: BoxDecoration(
                      color: isDark
                          ? AppColors.darkSurfaceVariant
                          : AppColors.lightSurface,
                      borderRadius: BorderRadius.circular(AppRadius.md),
                      border: Border.all(
                        color: isDark
                            ? Colors.white.withValues(alpha: 0.08)
                            : Colors.black.withValues(alpha: 0.06),
                      ),
                    ),
                    child: TextField(
                      controller: _searchController,
                      onChanged: (value) {
                        setState(() {
                          _searchQuery = value;
                        });
                      },
                      textInputAction: TextInputAction.search,
                      decoration: InputDecoration(
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.lg,
                          vertical: AppSpacing.md,
                        ),
                        hintText: 'Search chats, people, or messages',
                        hintStyle: TextStyle(
                          color: isDark
                              ? AppColors.darkTextSecondary
                              : AppColors.lightTextSecondary,
                        ),
                        prefixIcon: const Icon(Icons.search_rounded),
                        suffixIcon: _searchQuery.isEmpty
                            ? null
                            : IconButton(
                                onPressed: () {
                                  _searchController.clear();
                                  setState(() => _searchQuery = '');
                                },
                                icon: const Icon(Icons.close_rounded),
                              ),
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.lg,
                    0,
                    AppSpacing.lg,
                    AppSpacing.md,
                  ),
                  child: Row(
                    children: [
                      Text(
                        '${filteredUsers.length} ${filteredUsers.length == 1 ? 'chat' : 'chats'}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: isDark
                              ? AppColors.darkTextSecondary
                              : AppColors.lightTextSecondary,
                        ),
                      ),
                      const Spacer(),
                      if (_searchQuery.isNotEmpty)
                        Text(
                          'Filtered',
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: AppColors.primary,
                          ),
                        ),
                    ],
                  ),
                ),
                Expanded(
                  child: filteredUsers.isEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(AppSpacing.xxxl),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.search_off_rounded,
                                  size: 54,
                                  color: isDark
                                      ? AppColors.darkTextSecondary
                                      : AppColors.lightTextSecondary,
                                ),
                                const SizedBox(height: AppSpacing.md),
                                Text(
                                  'No matching chats',
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: AppSpacing.sm),
                                Text(
                                  'Try a different name, username, or message keyword.',
                                  textAlign: TextAlign.center,
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    color: isDark
                                        ? AppColors.darkTextSecondary
                                        : AppColors.lightTextSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        )
                      : RefreshIndicator(
                          onRefresh: _loadUsers,
                          child: ListView.builder(
                            physics: const BouncingScrollPhysics(),
                            padding: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.lg,
                              vertical: AppSpacing.sm,
                            ),
                            itemCount: filteredUsers.length,
                            itemBuilder: (_, index) {
                              final user = filteredUsers[index];
                              final lastMessage =
                                  _lastMessageByUid[user.uid] ?? '';

                              return Dismissible(
                                key: Key(user.uid),
                                direction: DismissDirection.endToStart,
                                confirmDismiss: (direction) async {
                                  HapticFeedback.mediumImpact();
                                  return await showDialog<bool>(
                                        context: context,
                                        builder: (context) => AlertDialog(
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(
                                              AppRadius.md,
                                            ),
                                          ),
                                          title: Row(
                                            children: [
                                              Container(
                                                padding: const EdgeInsets.all(
                                                  AppSpacing.sm,
                                                ),
                                                decoration: BoxDecoration(
                                                  color: AppColors.error
                                                      .withValues(alpha: 0.1),
                                                  borderRadius:
                                                      BorderRadius.circular(
                                                        AppRadius.xs,
                                                      ),
                                                ),
                                                child: Icon(
                                                  Icons.delete_rounded,
                                                  color: AppColors.error,
                                                  size: 24,
                                                ),
                                              ),
                                              const SizedBox(
                                                width: AppSpacing.md,
                                              ),
                                              const Text('Delete Chat'),
                                            ],
                                          ),
                                          content: Text(
                                            'Delete this chat with ${user.displayName}?',
                                          ),
                                          actions: [
                                            TextButton(
                                              onPressed: () =>
                                                  Navigator.pop(context, false),
                                              child: const Text('Cancel'),
                                            ),
                                            Container(
                                              decoration: BoxDecoration(
                                                color: AppColors.error,
                                                borderRadius:
                                                    BorderRadius.circular(
                                                      AppRadius.sm,
                                                    ),
                                              ),
                                              child: TextButton(
                                                onPressed: () => Navigator.pop(
                                                  context,
                                                  true,
                                                ),
                                                child: const Text(
                                                  'Delete',
                                                  style: TextStyle(
                                                    color: Colors.white,
                                                    fontWeight: FontWeight.w700,
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ) ??
                                      false;
                                },
                                onDismissed: (direction) {
                                  HapticFeedback.heavyImpact();
                                  _deleteChatForMe(user);
                                },
                                background: Container(
                                  margin: const EdgeInsets.only(
                                    bottom: AppSpacing.md,
                                  ),
                                  decoration: BoxDecoration(
                                    color: AppColors.error,
                                    borderRadius: BorderRadius.circular(
                                      AppRadius.md,
                                    ),
                                  ),
                                  alignment: Alignment.centerRight,
                                  padding: const EdgeInsets.only(
                                    right: AppSpacing.xl,
                                  ),
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      const Icon(
                                        Icons.delete_rounded,
                                        color: Colors.white,
                                        size: 32,
                                      ),
                                      const SizedBox(height: AppSpacing.xs),
                                      Text(
                                        'Delete',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w700,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                child: Container(
                                  margin: const EdgeInsets.only(
                                    bottom: AppSpacing.md,
                                  ),
                                  decoration: BoxDecoration(
                                    color: isDark
                                        ? AppColors.darkSurface
                                        : AppColors.lightSurface,
                                    borderRadius: BorderRadius.circular(
                                      AppRadius.md,
                                    ),
                                    boxShadow: AppShadows.cardList,
                                    border: Border.all(
                                      color: isDark
                                          ? Colors.white.withValues(alpha: 0.05)
                                          : Colors.black.withValues(
                                              alpha: 0.05,
                                            ),
                                      width: 1,
                                    ),
                                  ),
                                  child: Material(
                                    color: Colors.transparent,
                                    child: InkWell(
                                      onTap: () => _openChat(user),
                                      onLongPress: () =>
                                          _showDeleteChatDialog(user),
                                      borderRadius: BorderRadius.circular(
                                        AppRadius.md,
                                      ),
                                      child: Padding(
                                        padding: const EdgeInsets.all(
                                          AppSpacing.lg,
                                        ),
                                        child: Row(
                                          children: [
                                            Stack(
                                              children: [
                                                Container(
                                                  padding: const EdgeInsets.all(
                                                    3,
                                                  ),
                                                  decoration: BoxDecoration(
                                                    gradient: user.isOnline
                                                        ? AppColors
                                                              .primaryGradient
                                                        : null,
                                                    color: user.isOnline
                                                        ? null
                                                        : (isDark
                                                              ? Colors.white12
                                                              : Colors.black12),
                                                    shape: BoxShape.circle,
                                                  ),
                                                  child: ProfileAvatar(
                                                    imageUrl: user.profilePic,
                                                    displayName:
                                                        user.displayName,
                                                    radius: 28,
                                                    showOnlineIndicator: false,
                                                  ),
                                                ),
                                                if (user.isOnline)
                                                  Positioned(
                                                    right: 0,
                                                    bottom: 0,
                                                    child: Container(
                                                      width: 16,
                                                      height: 16,
                                                      decoration: BoxDecoration(
                                                        color:
                                                            AppColors.success,
                                                        shape: BoxShape.circle,
                                                        border: Border.all(
                                                          color: isDark
                                                              ? AppColors
                                                                    .darkSurface
                                                              : AppColors
                                                                    .lightSurface,
                                                          width: 2.5,
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                              ],
                                            ),
                                            const SizedBox(
                                              width: AppSpacing.lg,
                                            ),
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Row(
                                                    children: [
                                                      Expanded(
                                                        child: Text(
                                                          user.displayName,
                                                          style: theme
                                                              .textTheme
                                                              .titleMedium
                                                              ?.copyWith(
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w700,
                                                                color: isDark
                                                                    ? AppColors
                                                                          .darkText
                                                                    : AppColors
                                                                          .lightText,
                                                              ),
                                                          maxLines: 1,
                                                          overflow: TextOverflow
                                                              .ellipsis,
                                                        ),
                                                      ),
                                                      const SizedBox(
                                                        width: AppSpacing.sm,
                                                      ),
                                                      Text(
                                                        _formatMessageTime(
                                                          _lastMessageTimeByUid[user
                                                              .uid],
                                                        ),
                                                        style: TextStyle(
                                                          fontSize: 11,
                                                          color: isDark
                                                              ? AppColors
                                                                    .darkTextSecondary
                                                              : AppColors
                                                                    .lightTextSecondary,
                                                        ),
                                                      ),
                                                      if (user.isOnline)
                                                        const SizedBox(
                                                          width: AppSpacing.sm,
                                                        ),
                                                      if (user.isOnline)
                                                        Container(
                                                          padding:
                                                              const EdgeInsets.symmetric(
                                                                horizontal:
                                                                    AppSpacing
                                                                        .sm,
                                                                vertical: 2,
                                                              ),
                                                          decoration: BoxDecoration(
                                                            gradient: AppColors
                                                                .accentGradient,
                                                            borderRadius:
                                                                BorderRadius.circular(
                                                                  AppRadius.xs,
                                                                ),
                                                          ),
                                                          child: const Text(
                                                            'Online',
                                                            style: TextStyle(
                                                              fontSize: 10,
                                                              fontWeight:
                                                                  FontWeight
                                                                      .w700,
                                                              color:
                                                                  Colors.white,
                                                            ),
                                                          ),
                                                        ),
                                                    ],
                                                  ),
                                                  const SizedBox(height: 4),
                                                  Text(
                                                    lastMessage.isNotEmpty
                                                        ? _truncateMessage(
                                                            lastMessage,
                                                            40,
                                                          )
                                                        : (user
                                                                  .status
                                                                  .isNotEmpty
                                                              ? user.status
                                                              : '@${user.uniqueNumber}'),
                                                    maxLines: 1,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    style: TextStyle(
                                                      color: isDark
                                                          ? AppColors
                                                                .darkTextSecondary
                                                          : AppColors
                                                                .lightTextSecondary,
                                                      fontSize: 13,
                                                      fontWeight:
                                                          (_unreadCounts[user
                                                                      .uid] ??
                                                                  0) >
                                                              0
                                                          ? FontWeight.w600
                                                          : FontWeight.w400,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                            const SizedBox(
                                              width: AppSpacing.sm,
                                            ),
                                            if ((_unreadCounts[user.uid] ?? 0) >
                                                0)
                                              Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: AppSpacing.sm,
                                                      vertical: 4,
                                                    ),
                                                decoration: BoxDecoration(
                                                  gradient:
                                                      AppColors.primaryGradient,
                                                  borderRadius:
                                                      BorderRadius.circular(
                                                        AppRadius.xs,
                                                      ),
                                                ),
                                                child: Text(
                                                  _unreadCounts[user.uid]
                                                      .toString(),
                                                  style: const TextStyle(
                                                    color: Colors.white,
                                                    fontWeight: FontWeight.w700,
                                                    fontSize: 12,
                                                  ),
                                                ),
                                              )
                                            else
                                              Container(
                                                width: 32,
                                                height: 32,
                                                decoration: BoxDecoration(
                                                  gradient:
                                                      AppColors.primaryGradient,
                                                  shape: BoxShape.circle,
                                                ),
                                                child: const Icon(
                                                  Icons.arrow_forward_ios,
                                                  size: 14,
                                                  color: Colors.white,
                                                ),
                                              ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                ),
              ],
            ),
      floatingActionButton: _users.isNotEmpty
          ? Container(
              decoration: BoxDecoration(
                gradient: AppColors.primaryGradient,
                borderRadius: BorderRadius.circular(AppRadius.md),
                boxShadow: [AppShadows.coloredShadow(AppColors.accent)],
              ),
              child: FloatingActionButton(
                onPressed: _openSearch,
                tooltip: 'New Chat',
                backgroundColor: Colors.transparent,
                elevation: 0,
                child: const Icon(Icons.edit_rounded, color: Colors.white),
              ),
            )
          : null,
    );
  }
}
