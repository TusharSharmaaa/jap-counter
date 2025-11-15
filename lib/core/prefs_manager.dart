import 'package:shared_preferences/shared_preferences.dart';

/// Singleton manager for SharedPreferences to reduce I/O overhead.
/// All stores should use this instead of calling SharedPreferences.getInstance() directly.
class PrefsManager {
  static SharedPreferences? _instance;
  static bool _initializing = false;

  /// Get the SharedPreferences instance.
  /// If not initialized, initializes it once and reuses the instance.
  static Future<SharedPreferences> get instance async {
    if (_instance != null) {
      return _instance!;
    }

    // Prevent multiple simultaneous initializations
    while (_initializing) {
      await Future.delayed(const Duration(milliseconds: 10));
    }

    _initializing = true;
    try {
      _instance ??= await SharedPreferences.getInstance();
    } finally {
      _initializing = false;
    }

    return _instance!;
  }

  /// Ensure SharedPreferences is initialized.
  /// Call this during app startup to initialize early.
  static Future<void> ensureInitialized() async {
    await instance;
  }

  /// Clear the cached instance (useful for testing).
  static void clearInstance() {
    _instance = null;
  }
}





