import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:whatsapp_clone/core/design_tokens.dart';
import 'package:whatsapp_clone/providers/theme_mode_provider.dart';

class ThemeModeScreen extends StatelessWidget {
  const ThemeModeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final themeMode = context.watch<ThemeModeNotifier>().themeMode;

    return Scaffold(
      appBar: AppBar(title: const Text('Theme')),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          _ThemeTile(
            title: 'System default',
            subtitle: 'Match your device appearance automatically',
            value: ThemeMode.system,
            groupValue: themeMode,
          ),
          _ThemeTile(
            title: 'Light',
            subtitle: 'Always use light mode',
            value: ThemeMode.light,
            groupValue: themeMode,
          ),
          _ThemeTile(
            title: 'Dark',
            subtitle: 'Always use dark mode',
            value: ThemeMode.dark,
            groupValue: themeMode,
          ),
        ],
      ),
    );
  }
}

class _ThemeTile extends StatelessWidget {
  const _ThemeTile({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.groupValue,
  });

  final String title;
  final String subtitle;
  final ThemeMode value;
  final ThemeMode groupValue;

  @override
  Widget build(BuildContext context) {
    final isSelected = value == groupValue;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : AppColors.lightSurface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(
          color: isSelected
              ? AppColors.primary
              : (isDark
                    ? Colors.white.withValues(alpha: 0.06)
                    : Colors.black.withValues(alpha: 0.06)),
          width: isSelected ? 1.5 : 1,
        ),
      ),
      child: RadioListTile<ThemeMode>(
        value: value,
        groupValue: groupValue,
        onChanged: (selected) {
          if (selected == null) return;
          context.read<ThemeModeNotifier>().setThemeMode(selected);
        },
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(subtitle),
      ),
    );
  }
}
