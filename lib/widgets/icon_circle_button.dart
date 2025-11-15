import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/design_system.dart';

/// Circular icon button using design system
/// 
/// Example:
/// ```dart
/// IconCircleButton(
///   icon: Icons.favorite,
///   onPressed: () => print('Pressed'),
///   size: 48,
/// )
/// ```
class IconCircleButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onPressed;
  final double size;
  final Color? backgroundColor;
  final Color? iconColor;
  final bool hasGlow;
  final String? tooltip;

  const IconCircleButton({
    super.key,
    required this.icon,
    this.onPressed,
    this.size = 48,
    this.backgroundColor,
    this.iconColor,
    this.hasGlow = false,
    this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    Widget button = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: backgroundColor ?? DesignSystem.primary,
        shape: BoxShape.circle,
        boxShadow: hasGlow ? DesignSystem.shadowGlow : null,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed != null
              ? () {
                  HapticFeedback.lightImpact();
                  onPressed?.call();
                }
              : null,
          borderRadius: DesignSystem.borderRadiusIcon,
          child: Center(
            child: Icon(
              icon,
              color: iconColor ?? (backgroundColor != null && backgroundColor == DesignSystem.primary 
                  ? Colors.white 
                  : Theme.of(context).colorScheme.onSurface),
              size: size * 0.5,
            ),
          ),
        ),
      ),
    );

    if (tooltip != null) {
      button = Tooltip(
        message: tooltip!,
        child: button,
      );
    }

    return button;
  }
}

