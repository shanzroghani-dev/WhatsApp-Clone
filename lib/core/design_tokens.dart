import 'package:flutter/material.dart';

/// Centralized Design Tokens for WhatsApp Clone
/// Follows Material 3 design system with custom color palette

class AppColors {
  // Primary Accent - Modern Blue-Teal Gradient
  static const Color primary = Color(0xFF00B4DB); // Vibrant cyan-blue
  static const Color primaryDark = Color(0xFF0083B0); // Deep ocean blue
  static const Color primaryLight = Color(0xFF4DD0E1); // Light cyan
  static const Color accent = Color(0xFF667EEA); // Purple accent
  static const Color accentLight = Color(0xFF764BA2); // Deep purple

  // Dark Mode - Modern Dark Theme
  static const Color darkBg = Color(0xFF0F0F0F); // Almost black
  static const Color darkSurface = Color(0xFF1C1C1E); // Card surface
  static const Color darkSurfaceVariant = Color(0xFF2C2C2E); // Elevated surface
  static const Color darkText = Color(0xFFFFFFFF); // Pure white text
  static const Color darkTextSecondary = Color(0xFFAAAAAA); // Gray text

  // Light Mode - Clean Light Theme
  static const Color lightBg = Color(0xFFF5F7FA); // Soft gray background
  static const Color lightSurface = Color(0xFFFFFFFF); // Pure white
  static const Color lightSurfaceVariant = Color(0xFFF8F9FA); // Light variant
  static const Color lightText = Color(0xFF1A1A1A); // Almost black text
  static const Color lightTextSecondary = Color(0xFF6B7280); // Medium gray

  // Semantic Colors - Modern Palette
  static const Color success = Color(0xFF10B981); // Green
  static const Color error = Color(0xFFEF4444); // Red
  static const Color warning = Color(0xFFF59E0B); // Amber
  static const Color info = Color(0xFF3B82F6); // Blue

  // Chat Bubbles - Gradient Inspired
  static const Color sentBubble = Color(0xFF667EEA); // Purple gradient start
  static const Color sentBubbleEnd = Color(0xFF764BA2); // Purple gradient end
  static const Color receivedBubbleDark = Color(0xFF2C2C2E); // Dark mode
  static const Color receivedBubbleLight = Color(0xFFF3F4F6); // Light mode

  // Special Effects
  static const Color shimmerBase = Color(0xFFE0E0E0);
  static const Color shimmerHighlight = Color(0xFFF5F5F5);
  static const Color overlay = Color(0x66000000); // 40% black overlay

  // Utilities
  static const Color transparent = Colors.transparent;
  static const Color black = Color(0xFF000000);
  static const Color white = Color(0xFFFFFFFF);
  
  // Gradients
  static const LinearGradient primaryGradient = LinearGradient(
    colors: [Color(0xFF667EEA), Color(0xFF764BA2)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
  
  static const LinearGradient accentGradient = LinearGradient(
    colors: [Color(0xFF00B4DB), Color(0xFF0083B0)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}

class AppSpacing {
  // Standard padding/margins (8px baseline)
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20;
  static const double xxl = 24;
  static const double xxxl = 32;

  // Screen padding
  static const double screenPadding = lg; // 16px

  // Card padding
  static const double cardPadding = lg; // 16px

  // Chat bubble padding
  static const double chatBubblePaddingV = md; // 12px vertical
  static const double chatBubblePaddingH = lg; // 16px horizontal

  // Vertical spacing between elements
  static const double elementSpacing = md; // 12px
  static const double sectionSpacing = xxxl; // 32px

  // Between buttons
  static const double buttonSpacing = lg; // 16px
}

class AppRadius {
  // Modern, consistent roundness
  static const double xs = 8; // Small elements
  static const double sm = 12; // Buttons, inputs
  static const double md = 16; // Cards
  static const double lg = 20; // Large cards
  static const double xl = 24; // Modals
  static const double xxl = 32; // Hero sections
  static const double circle = 999; // Circular (avatars, badges)

  // Border
  static const double inputBorder = 2; // Input focus border width
}

class AppTypography {
  // Font family
  static const String fontFamily = 'Manrope';

  // Heading styles
  static const TextStyle heading1 = TextStyle(
    fontFamily: fontFamily,
    fontSize: 28,
    fontWeight: FontWeight.w800,
    height: 1.25,
    letterSpacing: -0.5,
  );

  static const TextStyle heading2 = TextStyle(
    fontFamily: fontFamily,
    fontSize: 24,
    fontWeight: FontWeight.w700,
    height: 1.25,
    letterSpacing: -0.5,
  );

  static const TextStyle heading3 = TextStyle(
    fontFamily: fontFamily,
    fontSize: 20,
    fontWeight: FontWeight.w700,
    height: 1.25,
    letterSpacing: -0.5,
  );

  // Body text
  static const TextStyle body = TextStyle(
    fontFamily: fontFamily,
    fontSize: 16,
    fontWeight: FontWeight.w400,
    height: 1.5,
    letterSpacing: 0,
  );

  static const TextStyle bodyMedium = TextStyle(
    fontFamily: fontFamily,
    fontSize: 16,
    fontWeight: FontWeight.w500,
    height: 1.5,
    letterSpacing: 0,
  );

  static const TextStyle bodyBold = TextStyle(
    fontFamily: fontFamily,
    fontSize: 16,
    fontWeight: FontWeight.w700,
    height: 1.5,
    letterSpacing: 0,
  );

  // Captions & Labels
  static const TextStyle caption = TextStyle(
    fontFamily: fontFamily,
    fontSize: 12,
    fontWeight: FontWeight.w500,
    height: 1.2,
    letterSpacing: 0,
  );

  static const TextStyle captionRegular = TextStyle(
    fontFamily: fontFamily,
    fontSize: 12,
    fontWeight: FontWeight.w400,
    height: 1.2,
    letterSpacing: 0,
  );

  // Button text
  static const TextStyle button = TextStyle(
    fontFamily: fontFamily,
    fontSize: 16,
    fontWeight: FontWeight.w500,
    height: 1.5,
    letterSpacing: 0,
  );

  static const TextStyle buttonBold = TextStyle(
    fontFamily: fontFamily,
    fontSize: 16,
    fontWeight: FontWeight.w700,
    height: 1.5,
    letterSpacing: 0,
  );
}

class AppShadows {
  // Modern elevation shadows
  static const BoxShadow subtle = BoxShadow(
    color: Color(0x0A000000), // 4% opacity
    blurRadius: 10,
    offset: Offset(0, 2),
    spreadRadius: 0,
  );

  static const BoxShadow medium = BoxShadow(
    color: Color(0x14000000), // 8% opacity
    blurRadius: 20,
    offset: Offset(0, 4),
    spreadRadius: 0,
  );

  static const BoxShadow elevated = BoxShadow(
    color: Color(0x1F000000), // 12% opacity
    blurRadius: 30,
    offset: Offset(0, 8),
    spreadRadius: 0,
  );
  
  static const BoxShadow card = BoxShadow(
    color: Color(0x0D000000), // 5% opacity
    blurRadius: 15,
    offset: Offset(0, 3),
    spreadRadius: -1,
  );

  static const List<BoxShadow> subtleList = [subtle];
  static const List<BoxShadow> mediumList = [medium];
  static const List<BoxShadow> elevatedList = [elevated];
  static const List<BoxShadow> cardList = [card];
  
  // Colored shadows for special effects
  static BoxShadow coloredShadow(Color color) => BoxShadow(
    color: color.withOpacity(0.3),
    blurRadius: 20,
    offset: const Offset(0, 8),
    spreadRadius: -2,
  );
}

class AppAnimations {
  // Duration constants
  static const Duration fast = Duration(milliseconds: 150);
  static const Duration medium = Duration(milliseconds: 300);
  static const Duration slow = Duration(milliseconds: 500);

  // Curves
  static const Curve easeInOut = Curves.easeInOut;
  static const Curve easeOut = Curves.easeOut;
}

class AppDimensions {
  // Button dimensions
  static const double buttonHeight = 56;
  static const double buttonHeightSmall = 44;

  // Avatar sizes
  static const double avatarLarge = 56;
  static const double avatarMedium = 48;
  static const double avatarSmall = 40;

  // Icon sizes
  static const double iconLarge = 32;
  static const double iconMedium = 24;
  static const double iconSmall = 18;

  // Input field height
  static const double inputHeight = 56;
}
