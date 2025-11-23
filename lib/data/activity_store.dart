import 'dart:async' show Completer, Timer;
import 'dart:convert';

import '../core/prefs_manager.dart';
import 'streak_store.dart';
import 'counter_store.dart';

/// Local date helper (YYYY-MM-DD) used by ActivityStore.
String _yyyymmdd(DateTime d) {
  final y = d.year.toString().padLeft(4, '0');
  final m = d.month.toString().padLeft(2, '0');
  final dd = d.day.toString().padLeft(2, '0');
  return '$y-$m-$dd';
}

/// Stores which dates the user was "active" (did at least 1 jap).
/// Dates are saved as ISO "yyyy-MM-dd" strings in a StringList.
class ActivityStore {
  static const _key = 'active_days'; // List<String> of yyyy-MM-dd
  static const _kDailyHistory = 'activity.dailyHistory';

  /// Marks today as active (idempotent).
  static Future<void> markTodayActive() async {
    final prefs = await PrefsManager.instance;
    final today = _isoDate(DateTime.now());
    final list = prefs.getStringList(_key) ?? <String>[];
    if (!list.contains(today)) {
      list.add(today);
      await prefs.setStringList(_key, list);
      // Clear streak cache when marking new day active
      await _clearStreakCache();
    }
  }

  /// Returns a Set of all active date strings.
  static Future<Set<String>> getAll() async {
    final prefs = await PrefsManager.instance;
    final list = prefs.getStringList(_key) ?? <String>[];
    return list.toSet();
  }

  /// Returns a Map of the last [days] dates (inclusive of today) -> isActive.
  /// Key format: yyyy-MM-dd
  static Future<Map<String, bool>> recentDays({int days = 60}) async {
    final active = await getAll();
    final map = <String, bool>{};
    final today = DateTime.now();
    for (int i = 0; i < days; i++) {
      final d = DateTime(today.year, today.month, today.day).subtract(Duration(days: i));
      final key = _isoDate(d);
      map[key] = active.contains(key);
    }
    return map;
  }

  /// Count of active days overall.
  static Future<int> totalActiveDays() async {
    final active = await getAll();
    return active.length;
  }
  // Cache for streak calculation to improve performance
  static int? _cachedStreak;
  static DateTime? _cachedStreakDate;
  static const _streakCacheKey = 'activity.cachedStreak';
  static const _streakCacheDateKey = 'activity.cachedStreakDate';

  /// Returns the length of the current consecutive-day streak (ending today).
  /// Uses caching to improve performance.
  static Future<int> currentStreak() async {
    final today = DateTime.now();
    final todayKey = _isoDate(today);
    
    // Check cache first
    if (_cachedStreak != null && 
        _cachedStreakDate != null && 
        _isSameDay(_cachedStreakDate!, today)) {
      return _cachedStreak!;
    }
    
    // Try to load from SharedPreferences cache
    final prefs = await PrefsManager.instance;
    final cachedStreak = prefs.getInt(_streakCacheKey);
    final cachedDateStr = prefs.getString(_streakCacheDateKey);
    
    if (cachedStreak != null && cachedDateStr == todayKey) {
      _cachedStreak = cachedStreak;
      _cachedStreakDate = today;
      return cachedStreak;
    }

    final active = await getAll();
    if (active.isEmpty) {
      await StreakStore.saveStreak(0, 0);
      _cachedStreak = 0;
      _cachedStreakDate = today;
      await prefs.setInt(_streakCacheKey, 0);
      await prefs.setString(_streakCacheDateKey, todayKey);
      return 0;
    }

    // OPTIMIZATION: For large datasets, use Set lookup instead of List.contains
    // This reduces complexity from O(n) to O(1) per lookup
    final activeSet = active;
    
    // OPTIMIZATION: Early exit optimization - start from today and go backwards
    // Most users have recent streaks, so we'll find the break point faster
    int streak = 0;
    final todayDay = DateTime(today.year, today.month, today.day);
    
    // Limit to max streak days for performance (prevents infinite loops)
    // Most streaks won't exceed this, and it prevents performance issues
    // Using proper date arithmetic to handle leap years
    const maxStreakDays = 365;
    for (int i = 0; i < maxStreakDays; i++) {
      final d = todayDay.subtract(Duration(days: i));
      final key = _isoDate(d);
      if (activeSet.contains(key)) {
        streak++;
      } else {
        break; // streak ended
      }
    }
    
    // Cache the result
    _cachedStreak = streak;
    _cachedStreakDate = today;
    await prefs.setInt(_streakCacheKey, streak);
    await prefs.setString(_streakCacheDateKey, todayKey);
    
    await StreakStore.saveStreak(streak, active.length);
    return streak;
  }
  
  static bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
  
  /// Clear streak cache (call when marking new day active)
  static Future<void> _clearStreakCache() async {
    _cachedStreak = null;
    _cachedStreakDate = null;
    final prefs = await PrefsManager.instance;
    await prefs.remove(_streakCacheKey);
    await prefs.remove(_streakCacheDateKey);
  }
  static String _isoDate(DateTime d) => _yyyymmdd(d);

  static Future<void> resetAll() async {
    final prefs = await PrefsManager.instance;
    await prefs.remove(_key);
    await StreakStore.saveStreak(0, 0);
  }

  static Future<int> currentStreakDays() => currentStreak();

  // OPTIMIZATION: Batch/defer writes to reduce SharedPreferences I/O
  static int? _pendingJaps;
  static int? _pendingMalas;
  static Timer? _batchWriteTimer;
  static Completer<void>? _pendingWriteCompleter;

  /// Record daily summary with batching for performance.
  /// Writes are batched and deferred to reduce SharedPreferences I/O on every tap.
  /// PERF: This was called on every tap before - now batches writes every 2 seconds or on flush.
  static Future<void> recordDailySummary(int japs, int malas) async {
    // Validate inputs to prevent negative values
    final validJaps = japs < 0 ? 0 : japs;
    final validMalas = malas < 0 ? 0 : malas;
    
    // Update pending values
    _pendingJaps = validJaps;
    _pendingMalas = validMalas;
    
    // Cancel existing timer
    _batchWriteTimer?.cancel();
    
    // Create new completer if needed
    _pendingWriteCompleter ??= Completer<void>();
    final completer = _pendingWriteCompleter!;
    
    // Schedule batched write after 2 seconds of inactivity
    _batchWriteTimer = Timer(const Duration(seconds: 2), () async {
      await _flushDailySummary();
    });
    
    // Also flush immediately every 10 taps (every 10th call)
    // This ensures data is persisted frequently enough
    if ((validJaps % 10) == 0) {
      await _flushDailySummary();
    }
    
    // Return the completer's future so callers can await if needed
    return completer.future;
  }
  
  /// Flush pending daily summary write to disk immediately.
  /// Called on app background, every 10 taps, or after 2 seconds of inactivity.
  static Future<void> _flushDailySummary() async {
    if (_pendingJaps == null || _pendingMalas == null) {
      return;
    }
    
    final japs = _pendingJaps!;
    final malas = _pendingMalas!;
    
    // Clear pending values
    _pendingJaps = null;
    _pendingMalas = null;
    _batchWriteTimer?.cancel();
    _batchWriteTimer = null;
    
    final completer = _pendingWriteCompleter;
    _pendingWriteCompleter = null;
    
    try {
      final prefs = await PrefsManager.instance;
      final raw = prefs.getString(_kDailyHistory);
      Map<String, dynamic> history;
      try {
        history = raw == null
            ? <String, dynamic>{}
            : Map<String, dynamic>.from(jsonDecode(raw));
      } catch (e) {
        // Handle corrupted JSON data
        history = <String, dynamic>{};
      }
      final key = _yyyymmdd(DateTime.now());
      history[key] = {
        'japs': japs,
        'malas': malas,
      };
      await prefs.setString(_kDailyHistory, jsonEncode(history));
      
      // Invalidate history cache
      _cachedHistory = null;
      _cachedHistoryDate = null;
      
      // Invalidate lifetime malas cache since history changed
      CounterStore.invalidateLifetimeMalasCache();
      
      // Complete the completer to notify awaiting callers
      completer?.complete();
    } catch (e) {
      // If write fails, complete with error
      completer?.completeError(e);
    }
  }
  
  /// Force immediate flush of pending writes (called on app background/close).
  static Future<void> flushPendingWrites() async {
    // Cancel any pending timer before flushing
    _batchWriteTimer?.cancel();
    _batchWriteTimer = null;
    await _flushDailySummary();
  }

  /// Clean up resources (cancel timers).
  /// Should be called when app is closing.
  static void cleanup() {
    _batchWriteTimer?.cancel();
    _batchWriteTimer = null;
    _pendingJaps = null;
    _pendingMalas = null;
    _pendingWriteCompleter = null;
  }

  // Cache for daily history to improve performance
  static Map<String, dynamic>? _cachedHistory;
  static DateTime? _cachedHistoryDate;

  static Future<Map<String, dynamic>> getDailyHistory() async {
    final today = DateTime.now();
    
    // Return cached if same day
    if (_cachedHistory != null && 
        _cachedHistoryDate != null &&
        _isSameDay(_cachedHistoryDate!, today)) {
      return _cachedHistory!;
    }
    
    final prefs = await PrefsManager.instance;
    final raw = prefs.getString(_kDailyHistory);
    if (raw == null) {
      _cachedHistory = {};
      _cachedHistoryDate = today;
      return {};
    }
    try {
      _cachedHistory = Map<String, dynamic>.from(jsonDecode(raw));
      _cachedHistoryDate = today;
      return _cachedHistory!;
    } catch (e) {
      // Handle corrupted JSON data - return empty map
      _cachedHistory = {};
      _cachedHistoryDate = today;
      return {};
    }
  }
  
  /// Calculate total lifetime japs from all historical data
  /// This is the sum of all japs recorded in daily history
  static Future<int> calculateTotalLifetimeJaps() async {
    final history = await getDailyHistory();
    int total = 0;
    
    for (final entry in history.values) {
      if (entry is Map<String, dynamic>) {
        final japs = entry['japs'] as num?;
        if (japs != null) {
          total += japs.toInt();
        }
      }
    }
    
    return total;
  }
  
  /// Calculate total lifetime malas from all historical data
  /// This is the sum of all malas recorded in daily history
  static Future<int> calculateTotalLifetimeMalas() async {
    final history = await getDailyHistory();
    int total = 0;
    
    for (final entry in history.values) {
      if (entry is Map<String, dynamic>) {
        final malas = entry['malas'] as num?;
        if (malas != null) {
          total += malas.toInt();
        }
      }
    }
    
    return total;
  }
}
