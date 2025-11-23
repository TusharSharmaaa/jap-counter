/// App-wide constants
class AppConstants {
  AppConstants._();

  /// App name used throughout the application
  static const String appName = 'Naam Jap Counter : Sadhna';
  
  /// App package name
  static const String packageName = 'com.example.jap_counter';
  
  /// Play Store URL
  static const String playStoreUrl = 
      'https://play.google.com/store/apps/details?id=$packageName';

  // Counter constants
  /// Number of japs in one complete mala
  static const int japsPerMala = 108;
  
  /// Maximum streak calculation limit (days)
  static const int maxStreakDays = 365;
  
  /// Batch write timer duration (seconds)
  static const int batchWriteDelaySeconds = 2;
  
  /// Flush every N taps
  static const int flushEveryNTaps = 10;
  
  /// Maximum goal value
  static const int maxGoalValue = 50;
  
  /// Minimum goal value
  static const int minGoalValue = 0;
  
  /// Chart cache invalidation debounce (milliseconds)
  static const int chartCacheDebounceMs = 500;
}

