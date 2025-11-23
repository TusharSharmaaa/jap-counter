import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';

/// Utility class for safe translation handling.
/// Extracts duplicate translation helper logic from multiple files.
class TranslationHelper {
  TranslationHelper._();

  /// Safely translate a key with optional arguments.
  /// Falls back to AppStrings.resolve if context scope is not available.
  static String safeTr(
    BuildContext? context,
    String language,
    String key, {
    Map<String, String>? args,
  }) {
    if (context != null) {
      final scope = AppLocalizationScope.maybeOf(context);
      if (scope != null) {
        return context.tr(key, args: args);
      }
    }
    
    var value = AppStrings.resolve(language, key);
    if (args != null) {
      args.forEach((k, v) {
        value = value.replaceAll('{$k}', v);
      });
    }
    return value;
  }
}

