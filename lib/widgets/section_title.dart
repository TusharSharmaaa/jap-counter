import 'package:flutter/material.dart';
import '../theme/design_system.dart';

/// Section title widget using design system
/// 
/// Example:
/// ```dart
/// SectionTitle(
///   title: 'Statistics',
///   subtitle: 'Your progress',
/// )
/// ```
class SectionTitle extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final EdgeInsets? padding;
  final TextStyle? titleStyle;
  final TextStyle? subtitleStyle;

  const SectionTitle({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
    this.padding,
    this.titleStyle,
    this.subtitleStyle,
  });

  @override
  Widget build(BuildContext context) {
    final sectionPadding = padding ?? 
        const EdgeInsets.only(
          left: DesignSystem.spacingMD,
          right: DesignSystem.spacingMD,
          top: DesignSystem.spacingLG,
          bottom: DesignSystem.spacingSM,
        );

    return Padding(
      padding: sectionPadding,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: titleStyle ?? DesignSystem.textTitle,
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: DesignSystem.spacingXS),
                  Text(
                    subtitle!,
                    style: subtitleStyle ?? DesignSystem.textSmall,
                  ),
                ],
              ],
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

