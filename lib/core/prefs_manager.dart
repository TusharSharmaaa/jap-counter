import 'dart:async' show Completer, TimeoutException;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Singleton manager for SharedPreferences to reduce I/O overhead.
/// All stores should use this instead of calling SharedPreferences.getInstance() directly.
/// 
/// OPTIMIZED for millions of users:
/// - Thread-safe initialization with proper locking
/// - Timeout protection to prevent hanging
/// - Error recovery mechanisms
class PrefsManager {
  static SharedPreferences? _instance;
  static bool _initializing = false;
  static Completer<SharedPreferences>? _initCompleter;

  /// Get the SharedPreferences instance.
  /// If not initialized, initializes it once and reuses the instance.
  /// 
  /// OPTIMIZATION: Uses completer pattern to prevent multiple simultaneous initializations
  /// and adds timeout protection for slow storage devices.
  static Future<SharedPreferences> get instance async {
    if (_instance != null) {
      return _instance!;
    }

    // If initialization is in progress, wait for existing completer
    if (_initCompleter != null) {
      return _initCompleter!.future;
    }

    // Create new completer for this initialization
    _initCompleter = Completer<SharedPreferences>();
    
    // Prevent multiple simultaneous initializations
    while (_initializing) {
      await Future.delayed(const Duration(milliseconds: 10));
    }

    _initializing = true;
    try {
      // Add timeout to prevent hanging on slow/corrupted storage
      _instance = await SharedPreferences.getInstance()
          .timeout(
            const Duration(seconds: 5),
            onTimeout: () {
              if (kDebugMode) {
                debugPrint('[PrefsManager] Initialization timeout');
              }
              throw TimeoutException('SharedPreferences initialization timeout');
            },
          );
      
      if (!_initCompleter!.isCompleted) {
        _initCompleter!.complete(_instance!);
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[PrefsManager] Initialization failed: $e');
      }
      if (!_initCompleter!.isCompleted) {
        _initCompleter!.completeError(e);
      }
      // Re-throw to allow callers to handle
      rethrow;
    } finally {
      _initializing = false;
      _initCompleter = null;
    }

    return _instance!;
  }

  /// Ensure SharedPreferences is initialized.
  /// Call this during app startup to initialize early.
  static Future<void> ensureInitialized() async {
    try {
      await instance;
    } catch (e) {
      // Log but don't throw - app can continue with limited functionality
      if (kDebugMode) {
        debugPrint('[PrefsManager] ensureInitialized failed: $e');
      }
    }
  }

  /// Clear the cached instance (useful for testing).
  static void clearInstance() {
    _instance = null;
    _initCompleter = null;
    _initializing = false;
  }
}





