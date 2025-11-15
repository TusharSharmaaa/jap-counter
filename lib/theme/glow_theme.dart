import 'package:flutter/material.dart';
import 'design_system.dart';

class GlowTheme {
  /// Glass card with glow effect
  static BoxDecoration card(BuildContext context) => DesignSystem.cardGlass;

  /// Card with glow shadow
  static BoxDecoration cardGlow(BuildContext context) => DesignSystem.cardGlow;

  /// Regular card
  static BoxDecoration cardRegular(BuildContext context) => DesignSystem.cardRegular;

  /// Primary button style
  static ButtonStyle filledButton(BuildContext context) => DesignSystem.primaryButton;

  /// Primary button with glow effect
  static ButtonStyle filledButtonGlow(BuildContext context) => DesignSystem.primaryButtonGlow;

  /// Gradient shader for text
  static Shader linearGradient(BuildContext context) => DesignSystem.glowGradient.createShader(
        const Rect.fromLTWH(0, 0, 200, 70),
      );
}

