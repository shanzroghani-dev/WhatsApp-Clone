import 'package:flutter/material.dart';

/// Reusable custom button widget
class CustomButton extends StatelessWidget {
  final String label;
  final VoidCallback onPressed;
  final Color? backgroundColor;
  final Color? textColor;
  final bool isLoading;
  final bool isEnabled;
  final EdgeInsets padding;
  final double cornerRadius;
  final double? width;
  final double? height;
  final IconData? icon;
  final MainAxisAlignment? mainAxisAlignment;

  const CustomButton({
    Key? key,
    required this.label,
    required this.onPressed,
    this.backgroundColor,
    this.textColor,
    this.isLoading = false,
    this.isEnabled = true,
    this.padding = const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
    this.cornerRadius = 8,
    this.width,
    this.height,
    this.icon,
    this.mainAxisAlignment = MainAxisAlignment.center,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final txtColor = textColor ?? colorScheme.onPrimary;
    final btnWidth = width ?? double.infinity;
    final btnHeight = height ?? 56;

    return SizedBox(
      width: btnWidth,
      height: btnHeight,
      child: ElevatedButton(
        onPressed: (isEnabled && !isLoading) ? onPressed : null,
        style: backgroundColor != null
            ? ElevatedButton.styleFrom(
                backgroundColor: backgroundColor,
                disabledBackgroundColor: backgroundColor!.withOpacity(0.6),
              )
            : null,
        child: isLoading
            ? SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(txtColor),
                ),
              )
            : Row(
                mainAxisAlignment:
                    mainAxisAlignment ?? MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (icon != null) ...[
                    Icon(icon, color: txtColor),
                    const SizedBox(width: 8),
                  ],
                  Text(
                    label,
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: txtColor,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
