import 'package:flutter/material.dart';
import 'design_system.dart';

ThemeData buildTheme(Brightness brightness) {
  final isDark = brightness == Brightness.dark;
  
  // Dark theme colors - clearly visible on dark backgrounds
  // Background: Very dark gray (almost black)
  final darkBackground = const Color(0xFF121212);
  // Surface: Slightly lighter dark gray for cards
  final darkSurface = const Color(0xFF1E1E1E);
  // Surface variant: Even lighter for nested surfaces
  final darkSurfaceVariant = const Color(0xFF2C2C2C);
  // Text colors: White and light gray for good visibility
  final darkOnSurface = Colors.white;
  final darkOnSurfaceVariant = const Color(0xFFB0B0B0); // Light gray
  
  // Light theme colors (existing)
  final lightBackground = DesignSystem.backgroundLight;
  final lightSurface = DesignSystem.glassColor;
  final lightOnSurface = const Color(0xFF1A1A1A);
  final lightOnSurfaceVariant = const Color(0xFF666666);
  
  // Choose colors based on theme
  final backgroundColor = isDark ? darkBackground : lightBackground;
  final surfaceColor = isDark ? darkSurface : lightSurface;
  final surfaceVariantColor = isDark ? darkSurfaceVariant : Colors.white.withValues(alpha: 0.5); // More subtle for cream backdrop
  final onSurfaceColor = isDark ? darkOnSurface : lightOnSurface;
  final onSurfaceVariantColor = isDark ? darkOnSurfaceVariant : lightOnSurfaceVariant;
  
  final colorScheme = ColorScheme.fromSeed(
    seedColor: DesignSystem.primary,
    brightness: brightness,
    primary: DesignSystem.buttonPrimary, // Use eye-friendly button color
    secondary: DesignSystem.accentGlow,
    surface: surfaceColor,
    surfaceVariant: surfaceVariantColor,
    background: backgroundColor,
    error: DesignSystem.primaryDark,
  ).copyWith(
    // Text colors based on theme
    onSurface: onSurfaceColor,
    onSurfaceVariant: onSurfaceVariantColor,
    onBackground: onSurfaceColor,
    onPrimary: Colors.white, // White text on primary/orange buttons
    onSecondary: Colors.white, // White text on secondary buttons
  );

  final base = ThemeData(
    useMaterial3: true,
    brightness: brightness,
    visualDensity: VisualDensity.adaptivePlatformDensity,
    colorScheme: colorScheme,
  );

  // Text styles - ensure white in dark mode, dark in light mode
  final titleStyle = TextStyle(
    fontSize: 22,
    fontWeight: FontWeight.bold,
    color: onSurfaceColor,
  );
  
  final labelStyle = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w600,
    color: onSurfaceColor,
  );
  
  final bodyStyle = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.normal,
    color: onSurfaceVariantColor,
  );
  
  final smallStyle = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.normal,
    color: onSurfaceVariantColor,
  );

  return base.copyWith(
    scaffoldBackgroundColor: backgroundColor,
    appBarTheme: AppBarTheme(
      elevation: 0,
      centerTitle: true,
      backgroundColor: Colors.transparent,
      foregroundColor: onSurfaceColor, // Theme-aware text color
      titleTextStyle: titleStyle.copyWith(fontSize: 20),
      iconTheme: IconThemeData(color: onSurfaceColor),
    ),
    cardTheme: CardThemeData(
      margin: const EdgeInsets.all(DesignSystem.spacingSM),
      clipBehavior: Clip.antiAliasWithSaveLayer,
      shape: RoundedRectangleBorder(
        borderRadius: DesignSystem.borderRadiusCard,
      ),
      elevation: 0,
      color: surfaceColor,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: DesignSystem.primaryButton,
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: DesignSystem.buttonPrimary,
        side: BorderSide(color: DesignSystem.buttonPrimary),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: DesignSystem.buttonPrimary,
      ),
    ),
    textTheme: TextTheme(
      titleLarge: titleStyle,
      titleMedium: titleStyle.copyWith(fontSize: 20),
      bodyLarge: labelStyle,
      bodyMedium: bodyStyle,
      bodySmall: bodyStyle,
      labelLarge: labelStyle,
      labelSmall: smallStyle,
      // Ensure all text styles use theme colors
      displayLarge: titleStyle.copyWith(fontSize: 32),
      displayMedium: titleStyle.copyWith(fontSize: 28),
      displaySmall: titleStyle.copyWith(fontSize: 24),
      headlineLarge: titleStyle.copyWith(fontSize: 20),
      headlineMedium: labelStyle.copyWith(fontSize: 18),
      headlineSmall: labelStyle.copyWith(fontSize: 16),
      titleSmall: labelStyle.copyWith(fontSize: 14),
      labelMedium: bodyStyle,
    ),
    // Icon theme - white in dark mode, dark in light mode
    iconTheme: IconThemeData(
      color: onSurfaceColor,
    ),
    // Divider color - lighter in dark mode for visibility
    dividerColor: isDark 
        ? Colors.white.withValues(alpha: 0.12) 
        : Colors.black.withValues(alpha: 0.12),
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

