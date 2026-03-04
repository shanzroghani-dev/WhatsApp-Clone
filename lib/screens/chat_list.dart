import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:whatsapp_clone/auth/auth_service.dart';
import 'package:whatsapp_clone/chat/chat_service.dart';
import 'package:whatsapp_clone/core/profile_service.dart';
import 'package:whatsapp_clone/models/user_model.dart';
import 'package:whatsapp_clone/providers/messages_provider.dart';
import 'package:whatsapp_clone/screens/chat/chat_screen.dart';
import 'package:whatsapp_clone/screens/search_users_screen.dart';
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
  final Map<String, String> _lastMessageByUid = {};
  final Map<String, int> _unreadCounts = {};
  final Map<String, DateTime> _lastMessageTimeByUid = {};
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
    _updateOnlineStatus(false);
    super.dispose();
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

      _incomingSub ??= ChatService.streamIncomingForUser(me.uid).listen((message) {
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

      for (final entry in chatEntries) {
        final peerUid = entry['peerUID'] as String?;
        if (peerUid == null || peerUid.isEmpty) continue;

        final profile = await ProfileService.getProfile(peerUid);
        final peer = profile ??
            UserModel(
              uid: peerUid,
              uniqueNumber: peerUid.substring(0, 8),
              email: '',
              displayName: 'Unknown user',
              status: 'Tap to open chat',
            );

        users.add(peer);
        _lastMessageByUid[peerUid] = (entry['lastMessage'] as String?) ?? '';
        _lastMessageTimeByUid[peerUid] = DateTime.now();
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
    // Clear unread count when opening chat
    setState(() {
      _unreadCounts[peer.uid] = 0;
    });
    Navigator.of(context)
        .push(
          MaterialPageRoute(
            builder: (_) => ChangeNotifierProvider(
              create: (_) => MessagesStateNotifier(),
              child: ChatScreen(currentUser: _currentUser!, peer: peer),
            ),
          ),
        )
        .then((_) => _loadUsers());
  }



  void _openSearch() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const SearchUsersScreen(),
      ),
    ).then((_) => _loadUsers());
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Chats'),
    
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
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
                            boxShadow: [
                              AppShadows.coloredShadow(AppColors.accent),
                            ],
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
                            color: isDark ? AppColors.darkText : AppColors.lightText,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.md),
                        Text(
                          'Find users and start chatting!',
                          style: theme.textTheme.bodyLarge?.copyWith(
                            color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: AppSpacing.xxxl),
                        Container(
                          height: 56,
                          decoration: BoxDecoration(
                            gradient: AppColors.primaryGradient,
                            borderRadius: BorderRadius.circular(AppRadius.sm),
                            boxShadow: [
                              AppShadows.coloredShadow(AppColors.accent),
                            ],
                          ),
                          child: ElevatedButton.icon(
                            onPressed: _openSearch,
                            icon: const Icon(Icons.search_rounded, color: Colors.white),
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
              : RefreshIndicator(
                  onRefresh: _loadUsers,
                  child: ListView.builder(
                    physics: const BouncingScrollPhysics(),
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    itemCount: _users.length,
                    itemBuilder: (_, index) {
                      final user = _users[index];
                      final lastMessage = _lastMessageByUid[user.uid] ?? '';
                      
                      return Container(
                        margin: const EdgeInsets.only(bottom: AppSpacing.md),
                        decoration: BoxDecoration(
                          color: isDark ? AppColors.darkSurface : AppColors.lightSurface,
                          borderRadius: BorderRadius.circular(AppRadius.md),
                          boxShadow: AppShadows.cardList,
                          border: Border.all(
                            color: isDark ? Colors.white.withOpacity(0.05) : Colors.black.withOpacity(0.05),
                            width: 1,
                          ),
                        ),
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: () => _openChat(user),
                            borderRadius: BorderRadius.circular(AppRadius.md),
                            child: Padding(
                              padding: const EdgeInsets.all(AppSpacing.lg),
                              child: Row(
                                children: [
                                  // Avatar with Gradient Border
                                  Stack(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.all(3),
                                        decoration: BoxDecoration(
                                          gradient: user.isOnline 
                                              ? AppColors.primaryGradient 
                                              : null,
                                          color: user.isOnline 
                                              ? null 
                                              : (isDark ? Colors.white12 : Colors.black12),
                                          shape: BoxShape.circle,
                                        ),
                                        child: ProfileAvatar(
                                          imageUrl: user.profilePic,
                                          displayName: user.displayName,
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
                                              color: AppColors.success,
                                              shape: BoxShape.circle,
                                              border: Border.all(
                                                color: isDark ? AppColors.darkSurface : AppColors.lightSurface,
                                                width: 2.5,
                                              ),
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                  
                                  const SizedBox(width: AppSpacing.lg),
                                  
                                  // Content
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Expanded(
                                              child: Text(
                                                user.displayName,
                                                style: theme.textTheme.titleMedium?.copyWith(
                                                  fontWeight: FontWeight.w700,
                                                  color: isDark ? AppColors.darkText : AppColors.lightText,
                                                ),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                            SizedBox(width: AppSpacing.sm.toDouble()),
                                            Text(
                                              _formatMessageTime(_lastMessageTimeByUid[user.uid]),
                                              style: TextStyle(
                                                fontSize: 11,
                                                color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                                              ),
                                            ),
                                            if (user.isOnline)
                                              SizedBox(width: AppSpacing.sm.toDouble()),
                                            if (user.isOnline)
                                              Container(
                                                padding: const EdgeInsets.symmetric(
                                                  horizontal: AppSpacing.sm,
                                                  vertical: 2,
                                                ),
                                                decoration: BoxDecoration(
                                                  gradient: AppColors.accentGradient,
                                                  borderRadius: BorderRadius.circular(AppRadius.xs),
                                                ),
                                                child: const Text(
                                                  'Online',
                                                  style: TextStyle(
                                                    fontSize: 10,
                                                    fontWeight: FontWeight.w700,
                                                    color: Colors.white,
                                                  ),
                                                ),
                                              ),
                                          ],
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          lastMessage.isNotEmpty
                                              ? _truncateMessage(lastMessage, 40)
                                              : (user.status.isNotEmpty 
                                                  ? user.status 
                                                  : '@${user.uniqueNumber}'),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                                            fontSize: 13,
                                            fontWeight: (_unreadCounts[user.uid] ?? 0) > 0 ? FontWeight.w600 : FontWeight.w400,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  
                                  const SizedBox(width: AppSpacing.sm),
                                  
                                  // Unread Badge or Arrow Icon
                                  if ((_unreadCounts[user.uid] ?? 0) > 0)
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: AppSpacing.sm,
                                        vertical: 4,
                                      ),
                                      decoration: BoxDecoration(
                                        gradient: AppColors.primaryGradient,
                                        borderRadius: BorderRadius.circular(AppRadius.xs),
                                      ),
                                      child: Text(
                                        _unreadCounts[user.uid].toString(),
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
                                        gradient: AppColors.primaryGradient,
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
                      );
                    },
                  ),
                ),
      floatingActionButton: _users.isNotEmpty
          ? Container(
              decoration: BoxDecoration(
                gradient: AppColors.primaryGradient,
                borderRadius: BorderRadius.circular(AppRadius.md),
                boxShadow: [
                  AppShadows.coloredShadow(AppColors.accent),
                ],
              ),
              child: FloatingActionButton(
                onPressed: _openSearch,
                tooltip: 'New Chat',
                backgroundColor: Colors.transparent,
                elevation: 0,
                child: const Icon(
                  Icons.edit_rounded,
                  color: Colors.white,
                ),
              ),
            )
          : null,
    );
  }
}
