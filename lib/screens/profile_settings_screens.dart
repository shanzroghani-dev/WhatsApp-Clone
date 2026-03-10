import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:whatsapp_clone/core/design_tokens.dart';
import 'package:whatsapp_clone/core/local_db_service.dart';
import 'package:whatsapp_clone/core/notification_service.dart';
import 'package:whatsapp_clone/core/security_service.dart';
import 'package:whatsapp_clone/widgets/skeleton_loader.dart';

class PrivacySettingsScreen extends StatefulWidget {
  const PrivacySettingsScreen({super.key});

  @override
  State<PrivacySettingsScreen> createState() => _PrivacySettingsScreenState();
}

class _PrivacySettingsScreenState extends State<PrivacySettingsScreen> {
  bool _showOnlineStatus = true;
  bool _showLastSeen = true;
  bool _readReceipts = true;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _showOnlineStatus = prefs.getBool('privacy_show_online_status') ?? true;
      _showLastSeen = prefs.getBool('privacy_show_last_seen') ?? true;
      _readReceipts = prefs.getBool('privacy_read_receipts') ?? true;
      _loading = false;
    });
  }

  Future<void> _saveBool(String key, bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(key, value);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: SkeletonCenter());
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Privacy')),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          _SectionCard(
            children: [
              SwitchListTile(
                value: _showOnlineStatus,
                onChanged: (value) {
                  setState(() => _showOnlineStatus = value);
                  _saveBool('privacy_show_online_status', value);
                },
                title: const Text('Show online status'),
                subtitle: const Text('Allow others to see when you are online'),
              ),
              const Divider(height: 1),
              SwitchListTile(
                value: _showLastSeen,
                onChanged: (value) {
                  setState(() => _showLastSeen = value);
                  _saveBool('privacy_show_last_seen', value);
                },
                title: const Text('Show last seen'),
                subtitle: const Text('Display when you were last active'),
              ),
              const Divider(height: 1),
              SwitchListTile(
                value: _readReceipts,
                onChanged: (value) {
                  setState(() => _readReceipts = value);
                  _saveBool('privacy_read_receipts', value);
                },
                title: const Text('Read receipts'),
                subtitle: const Text('Send and receive read confirmations'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class SecuritySettingsScreen extends StatefulWidget {
  const SecuritySettingsScreen({super.key});

  @override
  State<SecuritySettingsScreen> createState() => _SecuritySettingsScreenState();
}

class _SecuritySettingsScreenState extends State<SecuritySettingsScreen> {
  bool _screenLock = false;
  bool _biometricPrompt = false;
  bool _hasPin = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final hasPin = await SecurityService.hasPin();
    setState(() {
      _screenLock = prefs.getBool('security_screen_lock') ?? false;
      _biometricPrompt = prefs.getBool('security_biometric_prompt') ?? false;
      _hasPin = hasPin;
      _loading = false;
    });
  }

  Future<String?> _showPinDialog({required bool isChange}) async {
    final controller = TextEditingController();
    final confirmController = TextEditingController();
    final errorState = ValueNotifier<String?>('');

    try {
      final result = await showDialog<String>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) {
          return WillPopScope(
            onWillPop: () async {
              FocusScope.of(dialogContext).unfocus();
              return true;
            },
            child: StatefulBuilder(
              builder: (context, setInnerState) {
                return AlertDialog(
                  title: Text(isChange ? 'Change App PIN' : 'Set App PIN'),
                  content: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        TextField(
                          controller: controller,
                          keyboardType: TextInputType.number,
                          obscureText: true,
                          maxLength: 6,
                          decoration: const InputDecoration(
                            labelText: 'PIN (4-6 digits)',
                            counterText: '',
                          ),
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        ValueListenableBuilder<String?>(
                          valueListenable: errorState,
                          builder: (context, error, _) {
                            return TextField(
                              controller: confirmController,
                              keyboardType: TextInputType.number,
                              obscureText: true,
                              maxLength: 6,
                              decoration: InputDecoration(
                                labelText: 'Confirm PIN',
                                counterText: '',
                                errorText: error,
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                  actions: [
                    TextButton(
                      autofocus: false,
                      onPressed: () {
                        FocusScope.of(dialogContext).unfocus();
                        Navigator.of(dialogContext).pop();
                      },
                      child: const Text('Cancel'),
                    ),
                    ElevatedButton(
                      autofocus: false,
                      onPressed: () {
                        final pin = controller.text.trim();
                        final confirm = confirmController.text.trim();
                        final valid = RegExp(r'^[0-9]{4,6}$').hasMatch(pin);
                        if (!valid) {
                          errorState.value = 'PIN must be 4-6 digits';
                          return;
                        }
                        if (pin != confirm) {
                          errorState.value = 'PIN does not match';
                          return;
                        }
                        FocusScope.of(dialogContext).unfocus();
                        Navigator.of(dialogContext).pop(pin);
                      },
                      child: const Text('Save'),
                    ),
                  ],
                );
              },
            ),
          );
        },
      );

      return result;
    } finally {
      controller.dispose();
      confirmController.dispose();
      errorState.dispose();
    }
  }

  Future<void> _toggleScreenLock(bool value) async {
    if (value && !_hasPin) {
      final pin = await _showPinDialog(isChange: false);
      if (pin == null) return;
      await SecurityService.setPin(pin);
      _hasPin = true;
    }

    setState(() {
      _screenLock = value;
      if (!value) {
        _biometricPrompt = false;
      }
    });

    await SecurityService.setScreenLockEnabled(value);
    if (!value) {
      await SecurityService.setBiometricPromptEnabled(false);
    }
  }

  Future<void> _toggleBiometric(bool value) async {
    if (!_screenLock) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Enable screen lock first')));
      return;
    }

    if (value) {
      final canUse = await SecurityService.canUseBiometrics();
      if (!canUse) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Biometrics not available on this device'),
          ),
        );
        return;
      }
    }

    setState(() => _biometricPrompt = value);
    await SecurityService.setBiometricPromptEnabled(value);
  }

  Future<void> _changePin() async {
    final pin = await _showPinDialog(isChange: true);
    if (pin == null) return;
    await SecurityService.setPin(pin);
    if (!mounted) return;
    setState(() => _hasPin = true);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('PIN updated successfully')));
  }

  Future<void> _removePin() async {
    await SecurityService.clearPin();
    await SecurityService.setScreenLockEnabled(false);
    await SecurityService.setBiometricPromptEnabled(false);
    if (!mounted) return;
    setState(() {
      _hasPin = false;
      _screenLock = false;
      _biometricPrompt = false;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('PIN removed and screen lock disabled')),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: SkeletonCenter());
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Security')),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          _SectionCard(
            children: [
              SwitchListTile(
                value: _screenLock,
                onChanged: _toggleScreenLock,
                title: const Text('Screen lock'),
                subtitle: const Text('Require unlock before opening chats'),
              ),
              const Divider(height: 1),
              SwitchListTile(
                value: _biometricPrompt,
                onChanged: _toggleBiometric,
                title: const Text('Biometric prompt'),
                subtitle: const Text(
                  'Ask for fingerprint/face when screen lock is enabled',
                ),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.pin_outlined),
                title: Text(_hasPin ? 'Change app PIN' : 'Set app PIN'),
                onTap: _changePin,
              ),
              if (_hasPin) ...[
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.lock_reset_outlined),
                  title: const Text('Remove app PIN'),
                  onTap: _removePin,
                ),
              ],
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          _SectionCard(
            children: [
              ListTile(
                leading: const Icon(Icons.info_outline),
                title: const Text('Encryption'),
                subtitle: const Text(
                  'Messages are encrypted before local storage and while sending.',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class NotificationSettingsScreen extends StatefulWidget {
  const NotificationSettingsScreen({super.key});

  @override
  State<NotificationSettingsScreen> createState() =>
      _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState
    extends State<NotificationSettingsScreen> {
  bool _messageNotifications = true;
  bool _soundEnabled = true;
  bool _vibrationEnabled = true;
  bool _previewEnabled = true;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _messageNotifications = prefs.getBool('notifications_messages') ?? true;
      _soundEnabled = prefs.getBool('notifications_sound') ?? true;
      _vibrationEnabled = prefs.getBool('notifications_vibration') ?? true;
      _previewEnabled = prefs.getBool('notifications_preview') ?? true;
      _loading = false;
    });
  }

  Future<void> _saveBool(String key, bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(key, value);
    await NotificationService.refreshNotificationPreferences();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: SkeletonCenter());
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Notifications')),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          _SectionCard(
            children: [
              SwitchListTile(
                value: _messageNotifications,
                onChanged: (value) {
                  setState(() => _messageNotifications = value);
                  _saveBool('notifications_messages', value);
                },
                title: const Text('Message notifications'),
                subtitle: const Text('Receive notifications for new messages'),
              ),
              const Divider(height: 1),
              SwitchListTile(
                value: _soundEnabled,
                onChanged: (value) {
                  setState(() => _soundEnabled = value);
                  _saveBool('notifications_sound', value);
                },
                title: const Text('Notification sound'),
              ),
              const Divider(height: 1),
              SwitchListTile(
                value: _vibrationEnabled,
                onChanged: (value) {
                  setState(() => _vibrationEnabled = value);
                  _saveBool('notifications_vibration', value);
                },
                title: const Text('Vibration'),
              ),
              const Divider(height: 1),
              SwitchListTile(
                value: _previewEnabled,
                onChanged: (value) {
                  setState(() => _previewEnabled = value);
                  _saveBool('notifications_preview', value);
                },
                title: const Text('Show message preview'),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          OutlinedButton.icon(
            onPressed: NotificationService.sendTestNotification,
            icon: const Icon(Icons.notifications_active_outlined),
            label: const Text('Send test notification'),
          ),
        ],
      ),
    );
  }
}

class StorageSettingsScreen extends StatefulWidget {
  const StorageSettingsScreen({super.key, required this.currentUserUid});

  final String currentUserUid;

  @override
  State<StorageSettingsScreen> createState() => _StorageSettingsScreenState();
}

class _StorageSettingsScreenState extends State<StorageSettingsScreen> {
  int _messageCount = 0;
  int _chatCount = 0;
  int _dbSizeBytes = 0;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  Future<void> _loadStats() async {
    setState(() => _loading = true);

    final messageCount = await LocalDBService.getTotalMessageCount();
    final chatCount = await LocalDBService.getChatListCount(
      widget.currentUserUid,
    );

    final databasesPath = await getDatabasesPath();
    final dbPath = p.join(databasesPath, 'whatsapp_clone.db');
    final dbFile = File(dbPath);
    final dbSizeBytes = await dbFile.exists() ? await dbFile.length() : 0;

    if (!mounted) return;
    setState(() {
      _messageCount = messageCount;
      _chatCount = chatCount;
      _dbSizeBytes = dbSizeBytes;
      _loading = false;
    });
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
  }

  Future<void> _clearExpiredMessages() async {
    await LocalDBService.deleteOldLocalMessages();
    await _loadStats();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Expired local messages removed')),
    );
  }

  Future<void> _clearChatPreviews() async {
    await LocalDBService.clearChatListEntries(widget.currentUserUid);
    await _loadStats();
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Chat previews cleared')));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Storage')),
      body: _loading
          ? const SkeletonCenter()
          : RefreshIndicator(
              onRefresh: _loadStats,
              child: ListView(
                padding: const EdgeInsets.all(AppSpacing.lg),
                children: [
                  _SectionCard(
                    children: [
                      ListTile(
                        leading: const Icon(Icons.message_outlined),
                        title: const Text('Local messages'),
                        trailing: Text('$_messageCount'),
                      ),
                      const Divider(height: 1),
                      ListTile(
                        leading: const Icon(Icons.chat_outlined),
                        title: const Text('Chat previews'),
                        trailing: Text('$_chatCount'),
                      ),
                      const Divider(height: 1),
                      ListTile(
                        leading: const Icon(Icons.sd_storage_outlined),
                        title: const Text('Database size'),
                        trailing: Text(_formatBytes(_dbSizeBytes)),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.md),
                  OutlinedButton.icon(
                    onPressed: _clearExpiredMessages,
                    icon: const Icon(Icons.cleaning_services_outlined),
                    label: const Text('Clear expired messages'),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  OutlinedButton.icon(
                    onPressed: _clearChatPreviews,
                    icon: const Icon(Icons.delete_sweep_outlined),
                    label: const Text('Clear chat previews'),
                  ),
                ],
              ),
            ),
    );
  }
}

class HelpSupportScreen extends StatelessWidget {
  const HelpSupportScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Help & Support')),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          _SectionCard(
            children: [
              ListTile(
                leading: const Icon(Icons.email_outlined),
                title: const Text('Contact support'),
                subtitle: const Text('support@whatsapp-clone.app'),
                onTap: () {
                  Clipboard.setData(
                    const ClipboardData(text: 'support@whatsapp-clone.app'),
                  );
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Support email copied')),
                  );
                },
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.bug_report_outlined),
                title: const Text('Report a bug'),
                subtitle: const Text('Share logs and steps to reproduce'),
                onTap: () async {
                  await Share.share(
                    'Bug report\n\nDescribe the issue:\n1.\n2.\n3.\n\nApp: WhatsApp Clone 1.0.0',
                    subject: 'WhatsApp Clone Bug Report',
                  );
                },
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class StarredMessagesScreen extends StatelessWidget {
  const StarredMessagesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(title: const Text('Starred Messages')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xxl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.star_outline_rounded,
                size: 56,
                color: isDark
                    ? AppColors.darkTextSecondary
                    : AppColors.lightTextSecondary,
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                'No starred messages yet',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'Long-press any message in chat and choose Star to save it here.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: isDark
                      ? AppColors.darkTextSecondary
                      : AppColors.lightTextSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : AppColors.lightSurface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        boxShadow: AppShadows.cardList,
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.05)
              : Colors.black.withValues(alpha: 0.05),
        ),
      ),
      child: Column(children: children),
    );
  }
}
