import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:whatsapp_clone/auth/auth_service.dart';
import 'package:whatsapp_clone/core/profile_service.dart';
import 'package:whatsapp_clone/models/user_model.dart';
import 'package:whatsapp_clone/widgets/profile_avatar.dart';
import 'package:whatsapp_clone/widgets/custom_button.dart';
import 'package:whatsapp_clone/widgets/custom_text_field.dart';
import 'package:whatsapp_clone/core/design_tokens.dart';

/// Screen for editing user profile
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
  UserModel? _currentUser;
  File? _selectedImage;
  String? _displayNameError;
  String? _statusError;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  @override
  void dispose() {
    _displayNameController.dispose();
    _statusController.dispose();
    super.dispose();
  }

  Future<void> _loadProfile() async {
    setState(() => _loading = true);

    try {
      _currentUser = await AuthService.getCurrentUser();
      if (_currentUser != null) {
        _displayNameController.text = _currentUser!.displayName;
        _statusController.text = _currentUser!.status;
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load profile: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _pickImage() async {
    try {
      final pickedFile = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 85,
      );

      if (pickedFile != null) {
        setState(() {
          _selectedImage = File(pickedFile.path);
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to pick image: $e')),
        );
      }
    }
  }

  Future<void> _saveProfile() async {
    // Validate
    _displayNameError = null;
    _statusError = null;

    if (_displayNameController.text.trim().isEmpty) {
      setState(() => _displayNameError = 'Display name is required');
      return;
    }

    if (_displayNameController.text.trim().length < 2) {
      setState(() => _displayNameError = 'Display name must be at least 2 characters');
      return;
    }

    if (_statusController.text.trim().length > 100) {
      setState(() => _statusError = 'Status must be 100 characters or less');
      return;
    }

    setState(() => _saving = true);

    try {
      String? profilePicUrl;

      // Upload new profile picture if selected
      if (_selectedImage != null && _currentUser != null) {
        profilePicUrl = await ProfileService.uploadProfilePic(
          _currentUser!.uid,
          _selectedImage!,
        );
      }

      // Update profile
      if (_currentUser != null) {
        await ProfileService.updateProfile(
          _currentUser!.uid,
          displayName: _displayNameController.text.trim(),
          status: _statusController.text.trim(),
          profilePicUrl: profilePicUrl,
        );
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Profile updated successfully')),
        );
        Navigator.pop(context, true); // Return true to indicate changes were made
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to update profile: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('Edit Profile'),
        actions: [
          if (_saving)
            const Padding(
              padding: EdgeInsets.all(16.0),
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const SizedBox(height: AppSpacing.xl),

                  // Profile Picture
                  Stack(
                    children: [
                      GestureDetector(
                        onTap: _pickImage,
                        child: Container(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: colorScheme.primary.withOpacity(0.3),
                              width: 3,
                            ),
                          ),
                          child: _selectedImage != null
                              ? CircleAvatar(
                                  radius: 64,
                                  backgroundImage: FileImage(_selectedImage!),
                                )
                              : ProfileAvatar(
                                  imageUrl: _currentUser?.profilePic,
                                  displayName: _currentUser?.displayName ?? '',
                                  radius: 64,
                                ),
                        ),
                      ),
                      Positioned(
                        bottom: 0,
                        right: 0,
                        child: Container(
                          decoration: BoxDecoration(
                            color: colorScheme.primary,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: colorScheme.surface,
                              width: 3,
                            ),
                          ),
                          child: IconButton(
                            icon: const Icon(Icons.camera_alt, color: Colors.white),
                            onPressed: _pickImage,
                          ),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: AppSpacing.md),
                  
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.lg,
                      vertical: AppSpacing.sm,
                    ),
                    decoration: BoxDecoration(
                      color: colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                    ),
                    child: Text(
                      '@${_currentUser?.uniqueNumber ?? ''}',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: colorScheme.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),

                  const SizedBox(height: AppSpacing.xxxl),

                  // Display Name Field
                  CustomTextField(
                    controller: _displayNameController,
                    label: 'Display Name',
                    hint: 'Enter your display name',
                    prefixIcon: Icons.person,
                    errorText: _displayNameError,
                  ),

                  const SizedBox(height: AppSpacing.xl),

                  // Status Field
                  CustomTextField(
                    controller: _statusController,
                    label: 'Status',
                    hint: 'What\'s on your mind?',
                    prefixIcon: Icons.message,
                    errorText: _statusError,
                    maxLines: 3,
                  ),

                  const SizedBox(height: AppSpacing.xxxl),

                  // Save Button
                  CustomButton(
                    label: 'Save Changes',
                    onPressed: _saveProfile,
                    isLoading: _saving,
                    isEnabled: !_saving,
                  ),

                  const SizedBox(height: AppSpacing.xl),

                  // Info Card
                  Card(
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
                  ),
                  
                  const SizedBox(height: AppSpacing.xxxl),
                ],
              ),
            ),
    );
  }

  Widget _buildInfoRow(ThemeData theme, String label, String value, IconData icon) {
    return Row(
      children: [
        Icon(
          icon,
          size: 18,
          color: theme.iconTheme.color?.withOpacity(0.5),
        ),
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
              Text(
                value,
                style: theme.textTheme.bodyLarge,
              ),
            ],
          ),
        ),
      ],
    );
  }

  String _formatDate(DateTime? date) {
    if (date == null) return 'Unknown';
    final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${months[date.month - 1]} ${date.day}, ${date.year}';
  }
}
