import 'package:flutter/material.dart';
import 'package:whatsapp_clone/core/design_tokens.dart';

/// Material 3 Theme Configuration for WhatsApp Clone
class AppTheme {
  /// Light theme
  static ThemeData lightTheme = ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    colorScheme: ColorScheme.light(
      primary: AppColors.primary,
      onPrimary: AppColors.white,
      primaryContainer: AppColors.primaryLight,
      onPrimaryContainer: AppColors.primary,
      secondary: AppColors.primary,
      surface: AppColors.lightSurface,
      onSurface: AppColors.lightText,
      error: AppColors.error,
      onError: AppColors.white,
    ),
    scaffoldBackgroundColor: AppColors.lightBg,

    // AppBar theme
    appBarTheme: AppBarTheme(
      backgroundColor: AppColors.lightSurface,
      foregroundColor: AppColors.lightText,
      elevation: 0,
      centerTitle: false,
      surfaceTintColor: Colors.transparent,
      shadowColor: Colors.black.withOpacity(0.1),
      scrolledUnderElevation: 1,
      iconTheme: const IconThemeData(color: AppColors.lightText, size: 24),
      titleTextStyle: AppTypography.heading3.copyWith(
        color: AppColors.lightText,
        fontWeight: FontWeight.w700,
      ),
    ),

    // Input decoration (text fields)
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.lightBg,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.md,
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.sm),
        borderSide: const BorderSide(color: Colors.grey, width: 1),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.sm),
        borderSide: const BorderSide(color: Colors.grey, width: 1),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.sm),
        borderSide: const BorderSide(
          color: AppColors.primary,
          width: AppRadius.inputBorder,
        ),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.sm),
        borderSide: const BorderSide(color: AppColors.error, width: 1),
      ),
      hintStyle: AppTypography.body.copyWith(
        color: AppColors.lightTextSecondary,
      ),
      labelStyle: AppTypography.caption.copyWith(
        color: AppColors.lightTextSecondary,
      ),
    ),

    // Button themes
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.white,
        minimumSize: const Size(double.infinity, AppDimensions.buttonHeight),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
        elevation: 2,
        textStyle: AppTypography.buttonBold,
      ),
    ),

    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.primary,
        minimumSize: const Size(double.infinity, AppDimensions.buttonHeight),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
        side: const BorderSide(color: AppColors.primary, width: 1.5),
        textStyle: AppTypography.buttonBold,
      ),
    ),

    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: AppColors.primary,
        textStyle: AppTypography.button,
      ),
    ),

    // Floating action button
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: AppColors.primary,
      foregroundColor: AppColors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
    ),

    // Card theme
    cardTheme: CardThemeData(
      color: AppColors.lightSurface,
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      margin: EdgeInsets.zero,
    ),

    // Bottom sheet theme
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: AppColors.lightSurface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(AppRadius.md),
          topRight: Radius.circular(AppRadius.md),
        ),
      ),
    ),

    // Divider
    dividerTheme: const DividerThemeData(color: Colors.grey, thickness: 1),

    // Text theme
    textTheme: TextTheme(
      displayLarge: AppTypography.heading1.copyWith(color: AppColors.lightText),
      displayMedium: AppTypography.heading2.copyWith(
        color: AppColors.lightText,
      ),
      displaySmall: AppTypography.heading3.copyWith(color: AppColors.lightText),
      headlineSmall: AppTypography.heading3.copyWith(
        color: AppColors.lightText,
      ),
      titleLarge: AppTypography.bodyBold.copyWith(color: AppColors.lightText),
      titleMedium: AppTypography.bodyMedium.copyWith(
        color: AppColors.lightText,
      ),
      bodyLarge: AppTypography.body.copyWith(color: AppColors.lightText),
      bodyMedium: AppTypography.body.copyWith(
        color: AppColors.lightTextSecondary,
      ),
      bodySmall: AppTypography.captionRegular.copyWith(
        color: AppColors.lightTextSecondary,
      ),
      labelLarge: AppTypography.button.copyWith(color: AppColors.primary),
      labelMedium: AppTypography.caption.copyWith(
        color: AppColors.lightTextSecondary,
      ),
      labelSmall: AppTypography.captionRegular.copyWith(
        color: AppColors.lightTextSecondary,
      ),
    ),
  );

  /// Dark theme
  static ThemeData darkTheme = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: ColorScheme.dark(
      primary: AppColors.primary,
      onPrimary: AppColors.darkBg,
      primaryContainer: AppColors.primaryDark,
      onPrimaryContainer: AppColors.primary,
      secondary: AppColors.primary,
      surface: AppColors.darkSurface,
      onSurface: AppColors.darkText,
      error: AppColors.error,
      onError: AppColors.white,
    ),
    scaffoldBackgroundColor: AppColors.darkBg,

    // AppBar theme
    appBarTheme: AppBarTheme(
      backgroundColor: AppColors.darkSurface,
      foregroundColor: AppColors.darkText,
      elevation: 0,
      centerTitle: false,
      surfaceTintColor: Colors.transparent,
      shadowColor: Colors.black.withOpacity(0.3),
      scrolledUnderElevation: 1,
      iconTheme: const IconThemeData(color: AppColors.darkText, size: 24),
      titleTextStyle: AppTypography.heading3.copyWith(
        color: AppColors.darkText,
        fontWeight: FontWeight.w700,
      ),
    ),

    // Input decoration (text fields)
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.darkSurface,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.md,
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.sm),
        borderSide: const BorderSide(color: Colors.grey, width: 1),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.sm),
        borderSide: const BorderSide(color: Colors.grey, width: 1),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.sm),
        borderSide: const BorderSide(
          color: AppColors.primary,
          width: AppRadius.inputBorder,
        ),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.sm),
        borderSide: const BorderSide(color: AppColors.error, width: 1),
      ),
      hintStyle: AppTypography.body.copyWith(
        color: AppColors.darkTextSecondary,
      ),
      labelStyle: AppTypography.caption.copyWith(
        color: AppColors.darkTextSecondary,
      ),
    ),

    // Button themes
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.darkBg,
        minimumSize: const Size(double.infinity, AppDimensions.buttonHeight),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
        elevation: 2,
        textStyle: AppTypography.buttonBold,
      ),
    ),

    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.primary,
        minimumSize: const Size(double.infinity, AppDimensions.buttonHeight),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
        side: const BorderSide(color: AppColors.primary, width: 1.5),
        textStyle: AppTypography.buttonBold,
      ),
    ),

    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: AppColors.primary,
        textStyle: AppTypography.button,
      ),
    ),

    // Floating action button
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: AppColors.primary,
      foregroundColor: AppColors.darkBg,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
    ),

    // Card theme
    cardTheme: CardThemeData(
      color: AppColors.darkSurface,
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      margin: EdgeInsets.zero,
    ),

    // Bottom sheet theme
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: AppColors.darkSurface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(AppRadius.md),
          topRight: Radius.circular(AppRadius.md),
        ),
      ),
    ),

    // Divider
    dividerTheme: const DividerThemeData(color: Colors.grey, thickness: 1),

    // Text theme
    textTheme: TextTheme(
      displayLarge: AppTypography.heading1.copyWith(color: AppColors.darkText),
      displayMedium: AppTypography.heading2.copyWith(color: AppColors.darkText),
      displaySmall: AppTypography.heading3.copyWith(color: AppColors.darkText),
      headlineSmall: AppTypography.heading3.copyWith(color: AppColors.darkText),
      titleLarge: AppTypography.bodyBold.copyWith(color: AppColors.darkText),
      titleMedium: AppTypography.bodyMedium.copyWith(color: AppColors.darkText),
      bodyLarge: AppTypography.body.copyWith(color: AppColors.darkText),
      bodyMedium: AppTypography.body.copyWith(
        color: AppColors.darkTextSecondary,
      ),
      bodySmall: AppTypography.captionRegular.copyWith(
        color: AppColors.darkTextSecondary,
      ),
      labelLarge: AppTypography.button.copyWith(color: AppColors.primary),
      labelMedium: AppTypography.caption.copyWith(
        color: AppColors.darkTextSecondary,
      ),
      labelSmall: AppTypography.captionRegular.copyWith(
        color: AppColors.darkTextSecondary,
      ),
    ),
  );
}
