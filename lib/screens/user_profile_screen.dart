import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:whatsapp_clone/models/user_model.dart';
import 'package:whatsapp_clone/core/design_tokens.dart';

/// Screen to view another user's profile details
class UserProfileScreen extends StatelessWidget {
  final UserModel user;

  const UserProfileScreen({
    super.key,
    required this.user,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? AppColors.darkBg : AppColors.lightBg,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 260,
            pinned: true,
            backgroundColor: isDark ? AppColors.darkSurface : AppColors.lightSurface,
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      isDark
                          ? AppColors.primary.withOpacity(0.15)
                          : AppColors.primary.withOpacity(0.08),
                      isDark ? AppColors.darkSurface : AppColors.lightSurface,
                    ],
                  ),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const SizedBox(height: 60),
                    GestureDetector(
                      onTap: user.profilePic.isNotEmpty
                          ? () => _showFullImage(context)
                          : null,
                      child: Hero(
                        tag: 'user_avatar_${user.uid}',
                        child: Container(
                          width: 140,
                          height: 140,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: AppColors.primary.withOpacity(0.3),
                              width: 3,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.2),
                                blurRadius: 12,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: ClipOval(
                            child: user.profilePic.isNotEmpty
                                ? Image.network(
                                    user.profilePic,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) => _defaultAvatar(),
                                  )
                                : _defaultAvatar(),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      user.displayName,
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                        color: isDark ? AppColors.darkText : AppColors.lightText,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: user.isOnline ? Colors.green : Colors.grey,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          user.isOnline ? 'Online' : 'Offline',
                          style: TextStyle(
                            fontSize: 14,
                            color: isDark ? Colors.white70 : Colors.black54,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildInfoCard(
                    context,
                    isDark,
                    icon: Icons.info_outline,
                    title: 'About',
                    content: user.status.isNotEmpty ? user.status : 'Available',
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  _buildInfoCard(
                    context,
                    isDark,
                    icon: Icons.email_outlined,
                    title: 'Email',
                    content: user.email,
                    copyable: true,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  _buildInfoCard(
                    context,
                    isDark,
                    icon: Icons.tag,
                    title: 'User Number',
                    content: user.uniqueNumber,
                    copyable: true,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  _buildInfoCard(
                    context,
                    isDark,
                    icon: Icons.access_time,
                    title: 'Last Seen',
                    content: _formatLastSeen(user.lastSeen),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  _buildInfoCard(
                    context,
                    isDark,
                    icon: Icons.calendar_today,
                    title: 'Joined',
                    content: _formatDate(user.createdAt),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _defaultAvatar() {
    return Container(
      color: Colors.grey[400],
      child: Icon(Icons.person, color: Colors.grey[700], size: 70),
    );
  }

  Widget _buildInfoCard(
    BuildContext context,
    bool isDark, {
    required IconData icon,
    required String title,
    required String content,
    bool copyable = false,
  }) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : AppColors.lightSurface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(
          color: isDark
              ? Colors.white.withOpacity(0.05)
              : Colors.black.withOpacity(0.05),
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(AppSpacing.sm),
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.1),
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
            child: Icon(
              icon,
              color: AppColors.primary,
              size: 20,
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark ? Colors.white60 : Colors.black45,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  content,
                  style: TextStyle(
                    fontSize: 15,
                    color: isDark ? AppColors.darkText : AppColors.lightText,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          if (copyable)
            IconButton(
              icon: Icon(
                Icons.copy,
                size: 18,
                color: isDark ? Colors.white60 : Colors.black45,
              ),
              onPressed: () {
                Clipboard.setData(ClipboardData(text: content));
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('$title copied to clipboard'),
                    duration: const Duration(seconds: 1),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }

  String _formatLastSeen(DateTime lastSeen) {
    final now = DateTime.now();
    final difference = now.difference(lastSeen);

    if (difference.inMinutes < 1) {
      return 'Just now';
    } else if (difference.inMinutes < 60) {
      return '${difference.inMinutes} minutes ago';
    } else if (difference.inHours < 24) {
      return '${difference.inHours} hours ago';
    } else if (difference.inDays < 7) {
      return '${difference.inDays} days ago';
    } else {
      return '${lastSeen.day}/${lastSeen.month}/${lastSeen.year}';
    }
  }

  String _formatDate(DateTime date) {
    final months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec'
    ];
    return '${date.day} ${months[date.month - 1]} ${date.year}';
  }

  void _showFullImage(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            iconTheme: const IconThemeData(color: Colors.white),
          ),
          body: Center(
            child: Hero(
              tag: 'user_avatar_${user.uid}',
              child: InteractiveViewer(
                child: Image.network(
                  user.profilePic,
                  fit: BoxFit.contain,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
