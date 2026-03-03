import 'dart:async';

import 'package:flutter/material.dart';
import 'package:whatsapp_clone/auth/auth_service.dart';
import 'package:whatsapp_clone/chat/chat_service.dart';
import 'package:whatsapp_clone/core/profile_service.dart';
import 'package:whatsapp_clone/models/user_model.dart';
import 'package:whatsapp_clone/screens/chat_screen.dart';
import 'package:whatsapp_clone/screens/search_users_screen.dart';
import 'package:whatsapp_clone/screens/profile_screen.dart';
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

      _incomingSub ??= ChatService.streamIncomingForUser(me.uid).listen((_) {
        if (mounted) {
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

  Future<void> _logout() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Logout'),
        content: const Text('Are you sure you want to logout?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
            ),
            child: const Text('Logout'),
          ),
        ],
      ),
    );

    if (confirm == true && mounted) {
      await _updateOnlineStatus(false);
      await AuthService.logoutUser();
      if (!mounted) return;
      Navigator.of(context).pushReplacementNamed('/login');
    }
  }

  void _openChat(UserModel peer) {
    if (_currentUser == null) return;
    Navigator.of(context)
        .push(
          MaterialPageRoute(
            builder: (_) => ChatScreen(currentUser: _currentUser!, peer: peer),
          ),
        )
        .then((_) => _loadUsers());
  }

  Future<void> _openProfile() async {
    final result = await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const ProfileScreen(),
      ),
    );

    // Reload users if profile was updated
    if (result == true) {
      _loadUsers();
    }
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
        actions: [
          IconButton(
            onPressed: _openSearch,
            icon: const Icon(Icons.search),
            tooltip: 'Search Users',
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            onSelected: (value) {
              switch (value) {
                case 'profile':
                  _openProfile();
                  break;
                case 'logout':
                  _logout();
                  break;
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'profile',
                child: Row(
                  children: [
                   Icon(Icons.person),
                    SizedBox(width: 12),
                    Text('Profile'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'logout',
                child: Row(
                  children: [
                    Icon(Icons.logout),
                    SizedBox(width: 12),
                    Text('Logout'),
                  ],
                ),
              ),
            ],
          ),
        ],
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
                                              ? lastMessage
                                              : (user.status.isNotEmpty 
                                                  ? user.status 
                                                  : '@${user.uniqueNumber}'),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                                            fontSize: 14,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  
                                  const SizedBox(width: AppSpacing.sm),
                                  
                                  // Arrow Icon
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
