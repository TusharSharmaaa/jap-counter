import 'package:flutter/material.dart';
import 'design_system.dart';

class BrandGradients {
  static BoxDecoration timerBackground(BuildContext context, {required bool isRunning}) {
    final backgroundColor = Theme.of(context).scaffoldBackgroundColor;
    return BoxDecoration(
      gradient: RadialGradient(
        center: const Alignment(0, -0.4),
        radius: 1.2,
        colors: isRunning
            ? [
                DesignSystem.buttonPrimary.withValues(alpha: 0.15),
                backgroundColor,
              ]
            : [
                backgroundColor,
                backgroundColor,
              ],
      ),
    );
  }

  /// Share card gradient using brand colors
  static LinearGradient shareCard() => DesignSystem.glowGradient;

  /// Primary gradient for cards and surfaces
  static LinearGradient primary() => DesignSystem.primaryGradient;

  /// Background gradient
  static LinearGradient background() => DesignSystem.backgroundGradient;
}

