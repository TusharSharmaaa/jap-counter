import 'package:flutter/material.dart';
import 'design_system.dart';

ThemeData buildTheme(Brightness b) {
  // Create color scheme based on brand colors
  // Use light theme for brand colors (design system is light-themed)
  final effectiveBrightness = Brightness.light;
  
  final colorScheme = ColorScheme.fromSeed(
    seedColor: DesignSystem.primary,
    brightness: effectiveBrightness,
    primary: DesignSystem.primary,
    secondary: DesignSystem.accentGlow,
    surface: DesignSystem.backgroundLight,
    error: DesignSystem.primaryDark,
  ).copyWith(
    // Ensure all text colors are dark for visibility on light backgrounds
    onSurface: const Color(0xFF1A1A1A),
    onSurfaceVariant: const Color(0xFF666666),
    onBackground: const Color(0xFF1A1A1A),
    onPrimary: Colors.white, // Keep white on primary/orange buttons
  );

  final base = ThemeData(
    useMaterial3: true,
    brightness: effectiveBrightness, // Match ColorScheme brightness
    visualDensity: VisualDensity.adaptivePlatformDensity,
    colorScheme: colorScheme,
  );

  return base.copyWith(
    scaffoldBackgroundColor: DesignSystem.backgroundLight,
    appBarTheme: AppBarTheme(
      elevation: 0,
      centerTitle: true,
      backgroundColor: Colors.transparent,
      foregroundColor: const Color(0xFF1A1A1A), // Dark text for AppBar
      titleTextStyle: DesignSystem.textTitle.copyWith(fontSize: 20),
    ),
    cardTheme: CardThemeData(
      margin: const EdgeInsets.all(DesignSystem.spacingSM),
      clipBehavior: Clip.antiAliasWithSaveLayer,
      shape: RoundedRectangleBorder(
        borderRadius: DesignSystem.borderRadiusCard,
      ),
      elevation: 0,
      color: DesignSystem.glassColor,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: DesignSystem.primaryButton,
    ),
    textTheme: TextTheme(
      titleLarge: DesignSystem.textTitle,
      titleMedium: DesignSystem.textTitle.copyWith(fontSize: 20),
      bodyLarge: DesignSystem.textLabel,
      bodyMedium: DesignSystem.textLabel.copyWith(fontSize: 14),
      bodySmall: DesignSystem.textSmall,
      labelLarge: DesignSystem.textLabel,
      labelSmall: DesignSystem.textSmall12,
    ),
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: FadeUpwardsPageTransitionsBuilder(),
        TargetPlatform.iOS: FadeUpwardsPageTransitionsBuilder(),
        TargetPlatform.linux: FadeUpwardsPageTransitionsBuilder(),
        TargetPlatform.macOS: FadeUpwardsPageTransitionsBuilder(),
        TargetPlatform.windows: FadeUpwardsPageTransitionsBuilder(),
      },
    ),
  );
}

