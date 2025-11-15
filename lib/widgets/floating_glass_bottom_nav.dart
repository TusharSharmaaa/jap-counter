import 'dart:ui';
import 'package:flutter/material.dart';
import '../theme/design_system.dart';

/// Bottom navigation item model
class BottomNavItem {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool isSelected;

  const BottomNavItem({
    required this.icon,
    required this.label,
    required this.onTap,
    this.isSelected = false,
  });
}

/// Floating glass bottom navigation bar using design system
/// 
/// Example:
/// ```dart
/// FloatingGlassBottomNav(
///   items: [
///     BottomNavItem(
///       icon: Icons.home,
///       label: 'Home',
///       onTap: () {},
///       isSelected: true,
///     ),
///     BottomNavItem(
///       icon: Icons.stats,
///       label: 'Stats',
///       onTap: () {},
///     ),
///   ],
/// )
/// ```
class FloatingGlassBottomNav extends StatelessWidget {
  final List<BottomNavItem> items;
  final EdgeInsets? padding;
  final double? height;

  const FloatingGlassBottomNav({
    super.key,
    required this.items,
    this.padding,
    this.height,
  });

  @override
  Widget build(BuildContext context) {
    final navHeight = height ?? 72.0;
    final navPadding = padding ?? 
        const EdgeInsets.symmetric(
          horizontal: DesignSystem.spacingMD,
          vertical: DesignSystem.spacingSM,
        );

    return Container(
      margin: EdgeInsets.only(
        left: DesignSystem.spacingMD,
        right: DesignSystem.spacingMD,
        bottom: DesignSystem.spacingMD,
      ),
      height: navHeight,
      child: ClipRRect(
        borderRadius: DesignSystem.borderRadiusNavBar,
        child: BackdropFilter(
          filter: ImageFilter.blur(
            sigmaX: DesignSystem.glassBlur,
            sigmaY: DesignSystem.glassBlur,
          ),
          child: Container(
            padding: navPadding,
            decoration: BoxDecoration(
              color: DesignSystem.glassColor.withValues(alpha: 0.8),
              borderRadius: DesignSystem.borderRadiusNavBar,
              border: Border.all(
                color: DesignSystem.glassBorder,
                width: 1,
              ),
              boxShadow: DesignSystem.shadowSoft,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: items.map((item) {
                return _NavItem(item: item);
              }).toList(),
            ),
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final BottomNavItem item;

  const _NavItem({required this.item});

  @override
  Widget build(BuildContext context) {
    final isSelected = item.isSelected;
    final color = isSelected 
        ? DesignSystem.primary 
        : DesignSystem.textSoft;

    return Expanded(
      child: InkWell(
        onTap: item.onTap,
        borderRadius: BorderRadius.circular(DesignSystem.radiusButton),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              item.icon,
              color: color,
              size: isSelected ? 26 : 24,
            ),
            const SizedBox(height: DesignSystem.spacingXS),
            Text(
              item.label,
              style: DesignSystem.textSmall12.copyWith(
                color: color,
                fontWeight: isSelected 
                    ? FontWeight.w600 
                    : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }
}


