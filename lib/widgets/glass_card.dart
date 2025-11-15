import 'dart:ui';
import 'package:flutter/material.dart';
import '../theme/design_system.dart';

/// Glass morphism card widget using design system
/// 
/// Example:
/// ```dart
/// GlassCard(
///   child: Text('Content'),
///   padding: EdgeInsets.all(16),
/// )
/// ```
class GlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsets? padding;
  final EdgeInsets? margin;
  final double? borderRadius;
  final VoidCallback? onTap;
  final Color? backgroundColor;
  final bool useBackdropBlur;

  const GlassCard({
    super.key,
    required this.child,
    this.padding,
    this.margin,
    this.borderRadius,
    this.onTap,
    this.backgroundColor,
    this.useBackdropBlur = true,
  });

  @override
  Widget build(BuildContext context) {
    final radius = borderRadius ?? DesignSystem.radiusCard;
    final cardPadding = padding ?? const EdgeInsets.all(DesignSystem.spacingMD);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    
    // Use theme-aware colors
    final cardColor = backgroundColor ?? 
        (isDark 
            ? theme.colorScheme.surface 
            : Colors.white.withValues(alpha: 0.95));
    final borderColor = backgroundColor != null 
        ? DesignSystem.glassBorder 
        : (isDark 
            ? Colors.white.withValues(alpha: 0.1) 
            : Colors.white.withValues(alpha: 0.4));

    Widget content = Container(
      padding: cardPadding,
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(
          color: borderColor,
          width: 1.5,
        ),
        boxShadow: DesignSystem.shadowSoft,
      ),
      child: child,
    );

    if (useBackdropBlur && backgroundColor == null) {
      content = ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: BackdropFilter(
          filter: ImageFilter.blur(
            sigmaX: 10,
            sigmaY: 10,
          ),
          child: Container(
            padding: cardPadding,
            decoration: BoxDecoration(
              color: cardColor,
              borderRadius: BorderRadius.circular(radius),
              border: Border.all(
                color: borderColor,
                width: 1.5,
              ),
            ),
            child: child,
          ),
        ),
      );
    }

    if (onTap != null) {
      content = InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(radius),
        child: content,
      );
    }

    if (margin != null) {
      content = Container(margin: margin, child: content);
    }

    return content;
  }
}

