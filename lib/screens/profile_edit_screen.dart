import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:whatsapp_clone/auth/auth_service.dart';
import 'package:whatsapp_clone/models/user_model.dart';
import 'package:whatsapp_clone/core/design_tokens.dart';
import 'package:whatsapp_clone/core/profile_service.dart';
import 'package:whatsapp_clone/widgets/skeleton_loader.dart';
import 'package:whatsapp_clone/widgets/custom_button.dart';
import 'package:whatsapp_clone/widgets/custom_text_field.dart';
import 'package:whatsapp_clone/widgets/profile_avatar.dart';

/// Screen for editing user profile.
class ProfileEditScreen extends StatefulWidget {
  const ProfileEditScreen({super.key});

  @override
  State<ProfileEditScreen> createState() => _ProfileEditScreenState();
}

class _ProfileEditScreenState extends State<ProfileEditScreen> {
  final _displayNameController = TextEditingController();
  final _statusController = TextEditingController();
  final _imagePicker = ImagePicker();

  bool _loading = true;
  bool _saving = false;
  bool _hasChanges = false;
  bool _hasImageChange = false;

  UserModel? _currentUser;
  File? _selectedImage;
  String _initialDisplayName = '';
  String _initialStatus = '';

  String? _displayNameError;
  String? _statusError;

  static const int _maxStatusLength = 100;

  @override
  void initState() {
    super.initState();
    _displayNameController.addListener(_onFieldChanged);
    _statusController.addListener(_onFieldChanged);
    _loadProfile();
  }

  @override
  void dispose() {
    _displayNameController.removeListener(_onFieldChanged);
    _statusController.removeListener(_onFieldChanged);
    _displayNameController.dispose();
    _statusController.dispose();
    super.dispose();
  }

  void _onFieldChanged() {
    _syncHasChanges();
  }

  void _syncHasChanges() {
    final currentName = _displayNameController.text.trim();
    final currentStatus = _statusController.text.trim();
    final hasTextDiff =
        currentName != _initialDisplayName || currentStatus != _initialStatus;
    final nextHasChanges = hasTextDiff || _hasImageChange;

    if (_hasChanges != nextHasChanges && mounted) {
      setState(() => _hasChanges = nextHasChanges);
    }
  }

  Future<void> _loadProfile() async {
    setState(() => _loading = true);

    try {
      final user = await AuthService.getCurrentUser();
      _currentUser = user;

      if (user != null) {
        _displayNameController.removeListener(_onFieldChanged);
        _statusController.removeListener(_onFieldChanged);

        _displayNameController.text = user.displayName;
        _statusController.text = user.status;
        _initialDisplayName = user.displayName.trim();
        _initialStatus = user.status.trim();
        _hasImageChange = false;
        _selectedImage = null;

        _displayNameController.addListener(_onFieldChanged);
        _statusController.addListener(_onFieldChanged);

        _hasChanges = false;
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to load profile: $e')));
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _pickImage() async {
    HapticFeedback.mediumImpact();

    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt, color: Colors.blue),
              title: const Text('Take Photo'),
              onTap: () {
                HapticFeedback.lightImpact();
                Navigator.pop(context, ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library, color: Colors.green),
              title: const Text('Choose from Gallery'),
              onTap: () {
                HapticFeedback.lightImpact();
                Navigator.pop(context, ImageSource.gallery);
              },
            ),
            if (_selectedImage != null ||
                (_currentUser?.profilePic.isNotEmpty ?? false))
              ListTile(
                leading: const Icon(Icons.delete, color: Colors.red),
                title: const Text(
                  'Remove Photo',
                  style: TextStyle(color: Colors.red),
                ),
                onTap: () {
                  HapticFeedback.lightImpact();
                  Navigator.pop(context);
                  setState(() {
                    _selectedImage = null;
                    _hasImageChange = true;
                  });
                  _syncHasChanges();
                },
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );

    if (source == null) return;

    try {
      final pickedFile = await _imagePicker.pickImage(
        source: source,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 85,
      );

      if (pickedFile != null) {
        HapticFeedback.lightImpact();
        setState(() {
          _selectedImage = File(pickedFile.path);
          _hasImageChange = true;
        });
        _syncHasChanges();
      }
    } catch (e) {
      if (!mounted) return;
      HapticFeedback.heavyImpact();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Failed to pick image: ${e.toString().replaceAll('Exception: ', '')}',
          ),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _saveProfile() async {
    HapticFeedback.mediumImpact();

    setState(() {
      _displayNameError = null;
      _statusError = null;
    });

    if (_displayNameController.text.trim().isEmpty) {
      HapticFeedback.heavyImpact();
      setState(() => _displayNameError = 'Display name is required');
      return;
    }

    if (_displayNameController.text.trim().length < 2) {
      HapticFeedback.heavyImpact();
      setState(
        () => _displayNameError = 'Display name must be at least 2 characters',
      );
      return;
    }

    if (_statusController.text.trim().length > _maxStatusLength) {
      HapticFeedback.heavyImpact();
      setState(
        () => _statusError =
            'Status must be $_maxStatusLength characters or less',
      );
      return;
    }

    setState(() => _saving = true);

    try {
      String? profilePicUrl;

      if (_selectedImage != null && _currentUser != null) {
        profilePicUrl = await ProfileService.uploadProfilePic(
          _currentUser!.uid,
          _selectedImage!,
        );
      }

      if (_currentUser != null) {
        await ProfileService.updateProfile(
          _currentUser!.uid,
          displayName: _displayNameController.text.trim(),
          status: _statusController.text.trim(),
          profilePicUrl: profilePicUrl,
        );
      }

      if (!mounted) return;
      HapticFeedback.lightImpact();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Row(
            children: [
              Icon(Icons.check_circle, color: Colors.white),
              SizedBox(width: 12),
              Text('Profile updated successfully'),
            ],
          ),
          backgroundColor: Colors.green,
        ),
      );
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      HapticFeedback.heavyImpact();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.error, color: Colors.white),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Failed to update: ${e.toString().replaceAll('Exception: ', '')}',
                ),
              ),
            ],
          ),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 4),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  Future<void> _resetChanges() async {
    HapticFeedback.mediumImpact();

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reset Changes?'),
        content: const Text(
          'This will restore all fields to their original values.',
        ),
        actions: [
          TextButton(
            onPressed: () {
              HapticFeedback.lightImpact();
              Navigator.pop(context, false);
            },
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              HapticFeedback.lightImpact();
              Navigator.pop(context, true);
            },
            child: const Text('Reset', style: TextStyle(color: Colors.orange)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      _displayNameController.removeListener(_onFieldChanged);
      _statusController.removeListener(_onFieldChanged);

      setState(() {
        _displayNameController.text = _currentUser?.displayName ?? '';
        _statusController.text = _currentUser?.status ?? '';
        _selectedImage = null;
        _hasImageChange = false;
        _displayNameError = null;
        _statusError = null;
        _hasChanges = false;
      });

      _displayNameController.addListener(_onFieldChanged);
      _statusController.addListener(_onFieldChanged);
    }
  }

  Future<bool> _showDiscardDialog() async {
    HapticFeedback.mediumImpact();

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Discard Changes?'),
        content: const Text(
          'You have unsaved changes. Are you sure you want to discard them?',
        ),
        actions: [
          TextButton(
            onPressed: () {
              HapticFeedback.lightImpact();
              Navigator.pop(context, false);
            },
            child: const Text('Continue Editing'),
          ),
          TextButton(
            onPressed: () {
              HapticFeedback.lightImpact();
              Navigator.pop(context, true);
            },
            child: const Text('Discard', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    return result ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return PopScope(
      canPop: !_hasChanges,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;

        final shouldPop = await _showDiscardDialog();
        if (shouldPop && mounted) {
          Navigator.pop(context);
        }
      },
      child: Scaffold(
        backgroundColor: colorScheme.surface,
        appBar: AppBar(
          title: const Text('Edit Profile'),
          centerTitle: true,
          elevation: 0,
          actions: [
            if (_saving)
              const Padding(
                padding: EdgeInsets.all(16.0),
                child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
          ],
        ),
        body: _loading
            ? const SkeletonCenter()
            : SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  AppSpacing.lg,
                  AppSpacing.lg,
                  AppSpacing.xxxl,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildHeroHeader(theme, colorScheme),
                    const SizedBox(height: AppSpacing.lg),
                    _buildFormCard(theme, colorScheme),
                    const SizedBox(height: AppSpacing.lg),
                    _buildActionsCard(theme, colorScheme),
                    const SizedBox(height: AppSpacing.lg),
                    _buildAccountCard(theme),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _buildHeroHeader(ThemeData theme, ColorScheme colorScheme) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            colorScheme.primary.withOpacity(0.22),
            colorScheme.tertiary.withOpacity(0.12),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      child: Column(
        children: [
          Stack(
            children: [
              Hero(
                tag: 'profile_picture_${_currentUser?.uid}',
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: _pickImage,
                    borderRadius: BorderRadius.circular(100),
                    child: Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: colorScheme.primary.withOpacity(0.35),
                          width: 3,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: colorScheme.primary.withOpacity(0.2),
                            blurRadius: 18,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: _selectedImage != null
                          ? CircleAvatar(
                              radius: 58,
                              backgroundImage: FileImage(_selectedImage!),
                            )
                          : ProfileAvatar(
                              imageUrl: _currentUser?.profilePic,
                              displayName: _currentUser?.displayName ?? '',
                              radius: 58,
                            ),
                    ),
                  ),
                ),
              ),
              Positioned(
                bottom: 2,
                right: 2,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: colorScheme.primary,
                    shape: BoxShape.circle,
                    border: Border.all(color: colorScheme.surface, width: 2),
                  ),
                  child: IconButton(
                    icon: const Icon(Icons.camera_alt, color: Colors.white),
                    iconSize: 18,
                    onPressed: _pickImage,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            _displayNameController.text.trim().isEmpty
                ? (_currentUser?.displayName ?? 'Your Name')
                : _displayNameController.text.trim(),
            textAlign: TextAlign.center,
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Tap photo to update avatar',
            style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey),
          ),
          const SizedBox(height: AppSpacing.md),
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.xs,
            ),
            decoration: BoxDecoration(
              color: colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
            child: Text(
              '@${_currentUser?.uniqueNumber ?? ''}',
              style: theme.textTheme.labelLarge?.copyWith(
                color: colorScheme.primary,
                letterSpacing: 0.2,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFormCard(ThemeData theme, ColorScheme colorScheme) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: colorScheme.outline.withOpacity(0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.edit_note, color: colorScheme.primary),
              const SizedBox(width: AppSpacing.sm),
              Text(
                'Profile Details',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          CustomTextField(
            controller: _displayNameController,
            label: 'Display Name',
            hint: 'Enter your display name',
            prefixIcon: Icons.person,
            errorText: _displayNameError,
            onChanged: (_) => _syncHasChanges(),
          ),
          const SizedBox(height: AppSpacing.lg),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              CustomTextField(
                controller: _statusController,
                label: 'Status',
                hint: 'What\'s on your mind?',
                prefixIcon: Icons.message,
                errorText: _statusError,
                maxLines: 3,
                onChanged: (_) => _syncHasChanges(),
              ),
              const SizedBox(height: 4),
              Text(
                '${_statusController.text.length}/$_maxStatusLength',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: _statusController.text.length > _maxStatusLength
                      ? Colors.red
                      : Colors.grey,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildActionsCard(ThemeData theme, ColorScheme colorScheme) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      child: Column(
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppRadius.md),
              boxShadow: _hasChanges
                  ? [
                      BoxShadow(
                        color: colorScheme.primary.withOpacity(0.28),
                        blurRadius: 16,
                        offset: const Offset(0, 8),
                      ),
                    ]
                  : [],
            ),
            child: CustomButton(
              label: _hasChanges ? 'Save Changes' : 'No Changes Yet',
              onPressed: _saveProfile,
              isLoading: _saving,
              isEnabled: _hasChanges && !_saving,
            ),
          ),
          if (_hasChanges) ...[
            const SizedBox(height: AppSpacing.sm),
            TextButton.icon(
              onPressed: _saving ? null : _resetChanges,
              icon: const Icon(Icons.refresh),
              label: const Text('Reset Changes'),
              style: TextButton.styleFrom(foregroundColor: Colors.orange),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildAccountCard(ThemeData theme) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.info_outline,
                  size: 20,
                  color: theme.iconTheme.color?.withOpacity(0.6),
                ),
                const SizedBox(width: AppSpacing.sm),
                Text(
                  'Account Information',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            _buildInfoRow(
              theme,
              'Email',
              _currentUser?.email ?? '',
              Icons.email,
            ),
            const Divider(height: AppSpacing.xl),
            _buildInfoRow(
              theme,
              'Member Since',
              _formatDate(_currentUser?.createdAt),
              Icons.calendar_today,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(
    ThemeData theme,
    String label,
    String value,
    IconData icon,
  ) {
    return Row(
      children: [
        Icon(icon, size: 18, color: theme.iconTheme.color?.withOpacity(0.5)),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 2),
              Text(value, style: theme.textTheme.bodyLarge),
            ],
          ),
        ),
      ],
    );
  }

  String _formatDate(DateTime? date) {
    if (date == null) return 'Unknown';
    const months = [
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
      'Dec',
    ];
    return '${months[date.month - 1]} ${date.day}, ${date.year}';
  }
}
