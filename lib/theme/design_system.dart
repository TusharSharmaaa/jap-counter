import 'dart:ui';
import 'package:flutter/material.dart';

/// Complete Design System for the App
/// Single source of truth for all design tokens
class DesignSystem {
  DesignSystem._();

  // ============================================================================
  // COLORS
  // ============================================================================

  /// Background Colors
  static const Color backgroundLight = Color(0xFFFFF4E4);
  static const Color backgroundMedium = Color(0xFFFFEED6);
  static const Color backgroundDark = Color(0xFFFFE8E6);

  /// Primary Colors
  static const Color primary = Color(0xFFFF8A3D);
  static const Color primaryDark = Color(0xFFFF5722);
  static const Color accentGlow = Color(0xFFFF7043);
  
  /// Eye-friendly button color - softer, muted orange
  static const Color buttonPrimary = Color(0xFFD97757); // Softer, more muted orange

  /// Text Colors (dark for light theme)
  static const Color textWhite = Color(0xFF1A1A1A); // Dark text instead of white
  static const Color textSoft = Color(0xFF666666); // Medium gray instead of white70

  // ============================================================================
  // GRADIENTS
  // ============================================================================

  /// Primary gradient for backgrounds
  static const LinearGradient primaryGradient = LinearGradient(
    colors: [primary, primaryDark],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  /// Glow gradient for accents
  static const LinearGradient glowGradient = LinearGradient(
    colors: [primary, accentGlow],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  /// Background gradient
  static const LinearGradient backgroundGradient = LinearGradient(
    colors: [backgroundLight, backgroundMedium, backgroundDark],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );

  // ============================================================================
  // CORNER RADII
  // ============================================================================

  static const double radiusButton = 14;
  static const double radiusCard = 18;
  static const double radiusIconCircle = 999;
  static const double radiusNavBar = 24;

  // ============================================================================
  // SHADOWS
  // ============================================================================

  /// Soft shadow: 0, 8, blur 24, rgba(255,138,61,0.12)
  static List<BoxShadow> get shadowSoft => [
        BoxShadow(
          color: primary.withValues(alpha: 0.12),
          offset: const Offset(0, 8),
          blurRadius: 24,
        ),
      ];

  /// Glow shadow: 0, 12, blur 48, rgba(255,138,61,0.28)
  static List<BoxShadow> get shadowGlow => [
        BoxShadow(
          color: primary.withValues(alpha: 0.28),
          offset: const Offset(0, 12),
          blurRadius: 48,
        ),
      ];

  // ============================================================================
  // GLASS EFFECT
  // ============================================================================

  /// Glass color: rgba(255,255,255,0.22)
  static const Color glassColor = Color.fromRGBO(255, 255, 255, 0.22);

  /// Glass border: rgba(255,255,255,0.20)
  static const Color glassBorder = Color.fromRGBO(255, 255, 255, 0.20);

  /// Glass blur: 20px
  static const double glassBlur = 20.0;

  /// Glass card decoration
  static BoxDecoration get glassCard => BoxDecoration(
        color: glassColor,
        borderRadius: BorderRadius.circular(radiusCard),
        border: Border.all(
          color: glassBorder,
          width: 1,
        ),
        boxShadow: shadowSoft,
      );

  // ============================================================================
  // TYPOGRAPHY
  // ============================================================================

  /// Title: 22 bold white
  static const TextStyle textTitle = TextStyle(
    fontSize: 22,
    fontWeight: FontWeight.bold,
    color: textWhite,
  );

  /// Label: 16 semibold white
  static const TextStyle textLabel = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w600, // semibold
    color: textWhite,
  );

  /// Small: 12-14 white70
  static const TextStyle textSmall = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.normal,
    color: textSoft,
  );

  static const TextStyle textSmall12 = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.normal,
    color: textSoft,
  );

  // ============================================================================
  // SPACING TOKENS
  // ============================================================================

  static const double spacingXS = 4;
  static const double spacingSM = 8;
  static const double spacingMD = 16;
  static const double spacingLG = 24;
  static const double spacingXL = 32;
  static const double spacingXXL = 40;

  // ============================================================================
  // BUTTON STYLES
  // ============================================================================

  /// Primary button style with eye-friendly colors
  static ButtonStyle get primaryButton => FilledButton.styleFrom(
        backgroundColor: buttonPrimary, // Softer, eye-friendly color
        foregroundColor: Colors.white, // Keep white text on buttons
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusButton),
        ),
        textStyle: textLabel,
        padding: const EdgeInsets.symmetric(
          horizontal: spacingMD,
          vertical: spacingSM,
        ),
        elevation: 0,
      );

  /// Primary button with glow effect
  /// Note: For actual glow shadow effect, wrap button in Container with boxShadow
  static ButtonStyle get primaryButtonGlow => primaryButton;

  // ============================================================================
  // CARD STYLES
  // ============================================================================

  /// Glass card style
  static BoxDecoration get cardGlass => glassCard;

  /// Regular card style with shadow - subtle for cream backdrop
  static BoxDecoration get cardRegular => BoxDecoration(
        color: Colors.white.withValues(alpha: 0.5), // Reduced from 0.9
        borderRadius: BorderRadius.circular(radiusCard),
        boxShadow: shadowSoft,
      );

  /// Card with glow effect - subtle for cream backdrop
  static BoxDecoration get cardGlow => BoxDecoration(
        color: Colors.white.withValues(alpha: 0.5), // Reduced from 0.9
        borderRadius: BorderRadius.circular(radiusCard),
        boxShadow: shadowGlow,
      );

  // ============================================================================
  // SHAPE BORDER RADIUS
  // ============================================================================

  static BorderRadius get borderRadiusButton => BorderRadius.circular(radiusButton);
  static BorderRadius get borderRadiusCard => BorderRadius.circular(radiusCard);
  static BorderRadius get borderRadiusIcon => BorderRadius.circular(radiusIconCircle);
  static BorderRadius get borderRadiusNavBar => BorderRadius.circular(radiusNavBar);

  // ============================================================================
  // GLASS MORPHISM WIDGET
  // ============================================================================

  /// Glass morphism widget with backdrop blur
  static Widget glassWidget({
    required Widget child,
    double? borderRadius,
    EdgeInsets? padding,
  }) {
    final radius = borderRadius ?? radiusCard;
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: glassBlur, sigmaY: glassBlur),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: glassColor,
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(
              color: glassBorder,
              width: 1,
            ),
            boxShadow: shadowSoft,
          ),
          child: child,
        ),
      ),
    );
  }

  /// Wrap a button widget with glow shadow effect
  static Widget buttonWithGlow(Widget button) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: borderRadiusButton,
        boxShadow: shadowGlow,
      ),
      child: button,
    );
  }
}

