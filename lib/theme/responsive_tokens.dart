import 'package:flutter/material.dart';

/// Design tokens for responsive layouts
/// Single source of truth for breakpoints, spacing, typography, and component sizes
class ResponsiveTokens {
  ResponsiveTokens._();

  // Breakpoints (logical dp)
  static const double breakpointSmall = 360;
  static const double breakpointNormal = 420;
  static const double breakpointLarge = 719;
  static const double breakpointTablet = 720;

  // Spacing tokens (dp)
  static const double spacingXS = 4;
  static const double spacingSM = 8;
  static const double spacingMD = 16;
  static const double spacingLG = 24;
  static const double spacingXL = 40;

  // Button min sizes (dp)
  static const double buttonMinWidth = 64;
  static const double buttonMinHeight = 48;

  // Ad banner heights (logical dp)
  static const double adBannerHeightPortrait = 50;
  static const double adBannerHeightLandscape = 90;

  // Typography scale multipliers
  static const double typographyHeadline = 1.6;
  static const double typographyTitle = 1.3;
  static const double typographyBody = 1.0;
  static const double typographySmall = 0.85;

  /// Get responsive base font size based on screen width
  /// Formula: clamp(12, screenWidth / 28, 18)
  static double getBaseFontSize(double screenWidth) {
    return (screenWidth / 28).clamp(12.0, 18.0);
  }

  /// Get responsive font size for a given scale
  static double getFontSize(double screenWidth, double scale) {
    return getBaseFontSize(screenWidth) * scale;
  }

  /// Check if screen is small phone
  static bool isSmallPhone(double width) => width <= breakpointSmall;

  /// Check if screen is normal phone
  static bool isNormalPhone(double width) =>
      width > breakpointSmall && width <= breakpointNormal;

  /// Check if screen is large phone/phablet
  static bool isLargePhone(double width) =>
      width > breakpointNormal && width < breakpointTablet;

  /// Check if screen is tablet
  static bool isTablet(double width) => width >= breakpointTablet;

  /// Get ad banner height based on orientation
  static double getAdBannerHeight(bool isLandscape) {
    return isLandscape ? adBannerHeightLandscape : adBannerHeightPortrait;
  }

  /// Get responsive padding based on screen width
  static EdgeInsets getResponsivePadding(double width) {
    if (isTablet(width)) {
      return const EdgeInsets.symmetric(horizontal: spacingLG, vertical: spacingMD);
    } else if (isSmallPhone(width)) {
      return const EdgeInsets.symmetric(horizontal: spacingSM, vertical: spacingXS);
    }
    return const EdgeInsets.symmetric(horizontal: spacingMD, vertical: spacingSM);
  }

  /// Get responsive spacing between elements
  static double getResponsiveSpacing(double width) {
    if (isTablet(width)) {
      return spacingLG;
    } else if (isSmallPhone(width)) {
      return spacingSM;
    }
    return spacingMD;
  }
}

