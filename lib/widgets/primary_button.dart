import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/design_system.dart';

/// Primary button using design system
/// 
/// Example:
/// ```dart
/// PrimaryButton(
///   text: 'Save',
///   onPressed: () => print('Pressed'),
/// )
/// ```
class PrimaryButton extends StatelessWidget {
  final String text;
  final VoidCallback? onPressed;
  final bool isLoading;
  final bool hasGlow;
  final IconData? icon;
  final EdgeInsets? padding;

  const PrimaryButton({
    super.key,
    required this.text,
    this.onPressed,
    this.isLoading = false,
    this.hasGlow = false,
    this.icon,
    this.padding,
  });

  @override
  Widget build(BuildContext context) {
    Widget button = FilledButton(
      onPressed: isLoading ? null : onPressed,
      style: DesignSystem.primaryButton.copyWith(
        padding: padding != null
            ? WidgetStateProperty.all(padding)
            : null,
      ),
      onLongPress: () {
        HapticFeedback.mediumImpact();
      },
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (isLoading) ...[
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
              ),
            ),
            const SizedBox(width: DesignSystem.spacingSM),
          ] else if (icon != null) ...[
            Icon(icon, size: 20),
            const SizedBox(width: DesignSystem.spacingSM),
          ],
          Text(
            text,
            style: DesignSystem.textLabel,
          ),
        ],
      ),
    );

    if (hasGlow) {
      return DesignSystem.buttonWithGlow(button);
    }

    return button;
  }
}

