import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:whatsapp_clone/auth/auth_service.dart';
import 'package:whatsapp_clone/core/firebase_service.dart';
import 'package:whatsapp_clone/core/local_db_service.dart';
import 'package:whatsapp_clone/models/user_model.dart';
import 'package:whatsapp_clone/providers/media_provider.dart';
import 'package:whatsapp_clone/providers/messages_provider.dart';
import 'package:whatsapp_clone/providers/recording_provider.dart';
import 'package:whatsapp_clone/providers/upload_provider.dart';
import 'package:whatsapp_clone/screens/chat/chat_screen.dart';
import 'package:whatsapp_clone/widgets/profile_avatar.dart';
import 'package:whatsapp_clone/core/design_tokens.dart';

/// Dedicated screen for searching and finding users
class SearchUsersScreen extends StatefulWidget {
  const SearchUsersScreen({super.key});

  @override
  State<SearchUsersScreen> createState() => _SearchUsersScreenState();
}

class _SearchUsersScreenState extends State<SearchUsersScreen> {
  final _searchController = TextEditingController();
  UserModel? _currentUser;
  UserModel? _foundUser;
  bool _searching = false;
  bool _searched = false;

  @override
  void initState() {
    super.initState();
    _loadCurrentUser();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadCurrentUser() async {
    _currentUser = await AuthService.getCurrentUser();
  }

  Future<void> _searchUser() async {
    final query = _searchController.text.trim();
    if (query.isEmpty) return;

    setState(() {
      _searching = true;
      _searched = true;
      _foundUser = null;
    });

    try {
      final found = await FirebaseService.searchUserByEmailOrNumber(query);

      if (!mounted) return;

      setState(() {
        _foundUser = found;
        _searching = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _searching = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Search failed: $e')));
    }
  }

  Future<void> _startChat() async {
    if (_foundUser == null || _currentUser == null) return;

    if (_foundUser!.uid == _currentUser!.uid) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('You cannot chat with yourself')),
      );
      return;
    }

    // Cache the user profile locally
    await LocalDBService.cacheUserProfile(_foundUser!);

    if (!mounted) return;

    // Navigate to chat screen
    Navigator.of(context).pushReplacement(
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
            _foundUser!.uid,
          );
          final messagesProvider = MessagesProviderManager().getProvider(
            chatKey,
            _currentUser!.uid,
            _foundUser!.uid,
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
            child: ChatScreen(currentUser: _currentUser!, peer: _foundUser!),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Find Users')),
      body: Column(
        children: [
          // Search Bar Section
          Container(
            padding: const EdgeInsets.all(AppSpacing.lg),
            color: colorScheme.surface,
            child: Column(
              children: [
                TextField(
                  controller: _searchController,
                  autofocus: true,
                  style: theme.textTheme.bodyLarge,
                  decoration: InputDecoration(
                    hintText: 'Email or unique number',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _searchController.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () {
                              setState(() {
                                _searchController.clear();
                                _foundUser = null;
                                _searched = false;
                              });
                            },
                          )
                        : null,
                  ),
                  onChanged: (value) => setState(() {}),
                  onSubmitted: (_) => _searchUser(),
                ),
                const SizedBox(height: AppSpacing.md),
                Container(
                  width: double.infinity,
                  height: 52,
                  decoration: BoxDecoration(
                    gradient: AppColors.primaryGradient,
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                    boxShadow: [AppShadows.coloredShadow(AppColors.accent)],
                  ),
                  child: ElevatedButton.icon(
                    onPressed: _searching ? null : _searchUser,
                    icon: _searching
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.search_rounded, color: Colors.white),
                    label: Text(
                      _searching ? 'Searching...' : 'Search',
                      style: const TextStyle(
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

          // Results Section
          Expanded(child: _buildResultsSection(theme, colorScheme)),
        ],
      ),
    );
  }

  Widget _buildResultsSection(ThemeData theme, ColorScheme colorScheme) {
    final isDark = theme.brightness == Brightness.dark;

    if (_searching) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                gradient: AppColors.primaryGradient,
                shape: BoxShape.circle,
              ),
              child: const Padding(
                padding: EdgeInsets.all(20),
                child: CircularProgressIndicator(
                  strokeWidth: 3,
                  color: Colors.white,
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
            Text(
              'Searching...',
              style: theme.textTheme.titleMedium?.copyWith(
                color: isDark
                    ? AppColors.darkTextSecondary
                    : AppColors.lightTextSecondary,
              ),
            ),
          ],
        ),
      );
    }

    if (!_searched) {
      return Center(
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
                  Icons.person_search,
                  size: 60,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: AppSpacing.xxxl),
              Text(
                'Find Your Friends',
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: isDark ? AppColors.darkText : AppColors.lightText,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                'Search by email or unique chat number\nto start a conversation',
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: isDark
                      ? AppColors.darkTextSecondary
                      : AppColors.lightTextSecondary,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    if (_foundUser == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                color: isDark
                    ? Colors.white.withOpacity(0.1)
                    : Colors.black.withOpacity(0.05),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.person_off,
                size: 50,
                color: isDark ? Colors.white24 : Colors.black26,
              ),
            ),
            const SizedBox(height: AppSpacing.xxxl),
            Text(
              'No User Found',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
                color: isDark ? AppColors.darkText : AppColors.lightText,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxxl),
              child: Text(
                'Try searching with a different email or number',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: isDark
                      ? AppColors.darkTextSecondary
                      : AppColors.lightTextSecondary,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      );
    }

    // User found - show profile card with beautiful design
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'User Found 🎉',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: isDark ? AppColors.darkText : AppColors.lightText,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Container(
            decoration: BoxDecoration(
              color: isDark ? AppColors.darkSurface : AppColors.lightSurface,
              borderRadius: BorderRadius.circular(AppRadius.lg),
              boxShadow: [AppShadows.card],
              border: Border.all(
                color: isDark
                    ? Colors.white.withOpacity(0.05)
                    : Colors.black.withOpacity(0.05),
                width: 1,
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.xxl),
              child: Column(
                children: [
                  // Avatar with gradient border
                  Stack(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          gradient: AppColors.primaryGradient,
                          shape: BoxShape.circle,
                          boxShadow: [
                            AppShadows.coloredShadow(AppColors.accent),
                          ],
                        ),
                        child: ProfileAvatar(
                          imageUrl: _foundUser!.profilePic,
                          displayName: _foundUser!.displayName,
                          radius: 52,
                          showOnlineIndicator: false,
                        ),
                      ),
                      if (_foundUser!.isOnline)
                        Positioned(
                          right: 4,
                          bottom: 4,
                          child: Container(
                            width: 20,
                            height: 20,
                            decoration: BoxDecoration(
                              color: AppColors.success,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: isDark
                                    ? AppColors.darkSurface
                                    : AppColors.lightSurface,
                                width: 3,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  Text(
                    _foundUser!.displayName,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: isDark ? AppColors.darkText : AppColors.lightText,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.lg,
                      vertical: AppSpacing.sm,
                    ),
                    decoration: BoxDecoration(
                      gradient: AppColors.accentGradient,
                      borderRadius: BorderRadius.circular(AppRadius.xs),
                    ),
                    child: Text(
                      '@${_foundUser!.uniqueNumber}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                  ),
                  if (_foundUser!.status.isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.lg),
                    Container(
                      padding: const EdgeInsets.all(AppSpacing.lg),
                      decoration: BoxDecoration(
                        color: isDark
                            ? AppColors.darkSurfaceVariant
                            : AppColors.lightSurfaceVariant,
                        borderRadius: BorderRadius.circular(AppRadius.sm),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.info_outline,
                            size: 16,
                            color: isDark
                                ? AppColors.darkTextSecondary
                                : AppColors.lightTextSecondary,
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          Flexible(
                            child: Text(
                              _foundUser!.status,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: isDark
                                    ? AppColors.darkTextSecondary
                                    : AppColors.lightTextSecondary,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: AppSpacing.xxxl),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(Icons.close),
                          label: const Text('Cancel'),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                              vertical: AppSpacing.lg,
                            ),
                            side: BorderSide(
                              color: isDark ? Colors.white24 : Colors.black26,
                              width: 1.5,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(AppRadius.sm),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        flex: 2,
                        child: Container(
                          height: 48,
                          decoration: BoxDecoration(
                            gradient: AppColors.primaryGradient,
                            borderRadius: BorderRadius.circular(AppRadius.sm),
                            boxShadow: [
                              AppShadows.coloredShadow(AppColors.accent),
                            ],
                          ),
                          child: ElevatedButton.icon(
                            onPressed: _startChat,
                            icon: const Icon(
                              Icons.chat_rounded,
                              color: Colors.white,
                            ),
                            label: const Text(
                              'Start Chat',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.transparent,
                              shadowColor: Colors.transparent,
                              padding: const EdgeInsets.symmetric(
                                vertical: AppSpacing.lg,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(
                                  AppRadius.sm,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
