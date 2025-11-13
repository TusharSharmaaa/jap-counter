import 'dart:async' show unawaited, Timer, Completer;
import 'package:shared_preferences/shared_preferences.dart';

import '../core/prefs_manager.dart';
import 'activity_store.dart';
import 'xp_store.dart';

/// Offline-only store for Counter page with daily reset.
class CounterStore {
  CounterStore._(this._prefs);

  final SharedPreferences _prefs;
  
  // Lock to prevent race conditions in increment operations
  static Future<void>? _currentIncrement;
  
  // In-memory cache for performance (batched writes)
  int? _cachedToday;
  int? _cachedLifetime;
  bool _cacheDirty = false;
  static Timer? _syncTimer;
  static CounterStore? _syncInstance;

  // Keys
  static const _kTodayJaps = 'counter.todayJaps';
  static const _kLifetimeJaps = 'counter.lifetimeJaps';
  static const _kLastDate = 'counter.lastDate'; // YYYY-MM-DD

  /// Factory that also enforces daily reset.
  static Future<CounterStore> create() async {
    final prefs = await PrefsManager.instance;
    final store = CounterStore._(prefs);
    
    // Force sync any pending writes from previous instance before loading
    if (_syncInstance?._cacheDirty == true) {
      await _syncInstance!._syncToDisk();
    }
    
    await store._resetIfNewDay();
    // Load cache from disk - ensure we read the latest persisted values
    store._cachedToday = prefs.getInt(_kTodayJaps) ?? 0;
    final storedLifetime = prefs.getInt(_kLifetimeJaps) ?? 0;
    
    // CRITICAL: Calculate lifetime MALAS from completed malas in history
    // This ensures we only count COMPLETE malas (108 japs = 1 mala)
    // Strategy: Sum all completed malas from previous days + today's current completed malas
    
    final todayKey = _yyyymmdd(DateTime.now());
    final history = await ActivityStore.getDailyHistory();
    final todayJaps = store._cachedToday ?? 0;
    
    // Calculate today's completed malas from current counter (only complete malas)
    final todayCompletedMalas = todayJaps ~/ 108;
    
    // Sum completed malas from all previous days (excluding today)
    // This gives us the total completed malas from all past days
    int lifetimeMalasFromPreviousDays = 0;
    for (final entry in history.entries) {
      final dateKey = entry.key;
      final entryData = entry.value;
      
      // Skip today - we'll use current counter value instead
      if (dateKey == todayKey) {
        continue;
      }
      
      // Sum completed malas from this day
      if (entryData is Map<String, dynamic>) {
        final malas = entryData['malas'] as num?;
        if (malas != null) {
          lifetimeMalasFromPreviousDays += malas.toInt();
        }
      }
    }
    
    // Total lifetime malas = previous days' completed malas + today's current completed malas
    // This ensures we only count COMPLETE malas (108 japs = 1 mala)
    final totalLifetimeMalas = lifetimeMalasFromPreviousDays + todayCompletedMalas;
    
    // Store the calculated lifetime malas (completed malas only)
    store._cachedLifetimeMalas = totalLifetimeMalas;
    
    // Convert lifetime malas to japs for storage compatibility
    // This is the minimum japs needed for the completed malas (malas * 108)
    final calculatedLifetimeJapsFromMalas = totalLifetimeMalas * 108;
    
    // Also calculate lifetime japs from history for comparison
    // Sum all japs from previous days (excluding today)
    int lifetimeJapsFromPreviousDays = 0;
    int todayJapsFromHistory = 0;
    for (final entry in history.entries) {
      final dateKey = entry.key;
      final entryData = entry.value;
      
      if (entryData is Map<String, dynamic>) {
        final japs = entryData['japs'] as num?;
        if (japs != null) {
          if (dateKey == todayKey) {
            // Store today's japs from history for comparison
            todayJapsFromHistory = japs.toInt();
          } else {
            // Sum japs from previous days
            lifetimeJapsFromPreviousDays += japs.toInt();
          }
        }
      }
    }
    
    // Total lifetime japs = previous days' japs + today's current japs
    final calculatedLifetimeJapsFromHistory = lifetimeJapsFromPreviousDays + todayJaps;
    
    // IMPORTANT: Lifetime malas is calculated from COMPLETED malas only
    // We should NOT recalculate malas from japs, as japs might include partial malas
    // Lifetime malas is the source of truth for malas count (only complete malas)
    
    // For lifetime japs, use the maximum of:
    // 1. Lifetime japs calculated from completed malas (malas * 108) - minimum japs for completed malas
    // 2. Lifetime japs from history (sum of all japs) - might be higher if there are partial malas
    // 3. Stored lifetime japs - preserves data even if history is incomplete
    // This ensures we never lose data, but malas count remains based on completed malas only
    var calculatedLifetimeJaps = calculatedLifetimeJapsFromMalas;
    if (calculatedLifetimeJapsFromHistory > calculatedLifetimeJaps) {
      calculatedLifetimeJaps = calculatedLifetimeJapsFromHistory;
    }
    if (storedLifetime > calculatedLifetimeJaps) {
      calculatedLifetimeJaps = storedLifetime;
    }
    
    // Safety check: lifetime japs should never be less than today's japs
    // This ensures consistency
    if (calculatedLifetimeJaps < todayJaps) {
      calculatedLifetimeJaps = todayJaps;
      // If we had to use today's japs, we might need to update malas if it's higher
      // But only if today's completed malas are higher than what we calculated
      final todayCompletedMalasFromJaps = calculatedLifetimeJaps ~/ 108;
      if (todayCompletedMalasFromJaps > totalLifetimeMalas) {
        // This should never happen, but if it does, use the higher value
        // This means stored lifetime was way off
        store._cachedLifetimeMalas = todayCompletedMalasFromJaps;
      }
      // Otherwise, keep the malas we calculated from history (more accurate)
    }
    
    // Store lifetime japs (might include partial malas, but that's OK for japs count)
    store._cachedLifetime = calculatedLifetimeJaps;
    
    // CRITICAL: Lifetime malas is calculated from COMPLETED malas only
    // We do NOT recalculate it from japs, because japs might include partial malas
    // The malas count should always reflect only COMPLETE malas (108 japs = 1 mala)
    // This is already stored in store._cachedLifetimeMalas above
    
    // If calculated lifetime is higher than stored, update stored value
    // This syncs stored value with history-based calculation
    if (store._cachedLifetime! > storedLifetime) {
      store._cacheDirty = true;
      await store._syncToDisk();
    }
    
    _syncInstance = store;
    return store;
  }

  int get todayJaps => _cachedToday ?? _prefs.getInt(_kTodayJaps) ?? 0;
  int get lifetimeJaps => _cachedLifetime ?? _prefs.getInt(_kLifetimeJaps) ?? 0;

  int get todayMalas => todayJaps ~/ 108;
  
  /// Get lifetime malas - calculated from completed malas in history, not from japs
  /// This ensures we only count complete malas (108 japs = 1 mala)
  int get lifetimeMalas {
    // Use cached lifetime malas if available (calculated from history)
    // Otherwise, fall back to calculating from japs (but this should be rare)
    if (_cachedLifetimeMalas != null) {
      return _cachedLifetimeMalas!;
    }
    // Fallback: calculate from japs (should only happen if cache is not initialized)
    return lifetimeJaps ~/ 108;
  }
  
  // Cache for lifetime malas calculated from history
  int? _cachedLifetimeMalas;
  
  /// Refresh lifetime malas calculation from history
  /// This should be called after recording daily summary to update the cache
  Future<void> refreshLifetimeMalas() async {
    // Recalculate lifetime malas from history
    final todayKey = _yyyymmdd(DateTime.now());
    final history = await ActivityStore.getDailyHistory();
    final todayJaps = _cachedToday ?? _prefs.getInt(_kTodayJaps) ?? 0;
    
    // Calculate today's completed malas
    final todayCompletedMalas = todayJaps ~/ 108;
    
    // Sum completed malas from all previous days (excluding today)
    int lifetimeMalasFromPreviousDays = 0;
    for (final entry in history.entries) {
      final dateKey = entry.key;
      final entryData = entry.value;
      
      // Skip today - we'll use current counter value instead
      if (dateKey == todayKey) {
        continue;
      }
      
      // Sum completed malas from this day
      if (entryData is Map<String, dynamic>) {
        final malas = entryData['malas'] as num?;
        if (malas != null) {
          lifetimeMalasFromPreviousDays += malas.toInt();
        }
      }
    }
    
    // Total lifetime malas = previous days' completed malas + today's current completed malas
    _cachedLifetimeMalas = lifetimeMalasFromPreviousDays + todayCompletedMalas;
  }

  /// Increment today + lifetime by 1 jap.
  /// Uses a locking mechanism to prevent race conditions in single-threaded Dart code.
  /// Note: This works for single-threaded execution, but SharedPreferences operations
  /// are not thread-safe for concurrent writes across isolates.
  Future<void> increment() async {
    await _resetIfNewDay();
    
    // Wait for any ongoing increment to complete
    if (_currentIncrement != null) {
      await _currentIncrement;
    }
    
    // Create a new increment operation
    final completer = Completer<void>();
    _currentIncrement = completer.future;
    
    try {
      // Ensure cache is initialized from disk if null
      if (_cachedToday == null) {
        _cachedToday = _prefs.getInt(_kTodayJaps) ?? 0;
      }
      if (_cachedLifetime == null) {
        _cachedLifetime = _prefs.getInt(_kLifetimeJaps) ?? 0;
      }
      
      // Update in-memory cache immediately for responsiveness
      // Always increment from the current cached value (which should be initialized above)
      _cachedToday = _cachedToday! + 1;
      _cachedLifetime = _cachedLifetime! + 1;
      _cacheDirty = true;
      
      // Sync every 10 taps OR after 500ms of inactivity
      if (_cachedToday! % 10 == 0) {
        await _syncToDisk(); // Force sync every 10 taps
      } else {
        _scheduleSync();
      }
      
      // Update XP asynchronously (non-blocking)
      unawaited(_updateXP());
    } finally {
      // Clear the lock
      _currentIncrement = null;
      completer.complete();
    }
  }
  
  /// Force immediate sync to disk (used when app goes to background or closes).
  Future<void> forceSyncNow() async {
    _syncTimer?.cancel();
    await _syncToDisk();
  }
  
  void _scheduleSync() {
    _syncTimer?.cancel();
    _syncInstance = this;
    _syncTimer = Timer(const Duration(milliseconds: 500), () async {
      if (_syncInstance?._cacheDirty == true) {
        await _syncInstance!._syncToDisk();
      }
    });
  }
  
  Future<void> _syncToDisk() async {
    if (!_cacheDirty) return;
    try {
      // Always write today (it might be 0 if reset)
      await _prefs.setInt(_kTodayJaps, _cachedToday ?? 0);
      
      // For lifetime, ensure we never write a value less than what's already stored
      // This prevents accidentally resetting lifetime due to initialization issues
      if (_cachedLifetime != null) {
        // Read existing lifetime from disk to ensure we don't overwrite with a lower value
        final existingLifetime = _prefs.getInt(_kLifetimeJaps) ?? 0;
        // Only write if our cached value is greater than or equal to existing
        // This ensures lifetime always increases, never decreases
        if (_cachedLifetime! >= existingLifetime) {
          await _prefs.setInt(_kLifetimeJaps, _cachedLifetime!);
        } else {
          // If cached value is lower (shouldn't happen, but safety check),
          // use the existing value and update cache
          _cachedLifetime = existingLifetime;
        }
      } else {
        // If cache is null, read from disk and update cache, but don't write
        // This preserves existing lifetime value
        final existingLifetime = _prefs.getInt(_kLifetimeJaps) ?? 0;
        _cachedLifetime = existingLifetime;
      }
      _cacheDirty = false;
    } catch (e) {
      // If sync fails, mark dirty again for retry
      _cacheDirty = true;
    }
  }
  
  Future<void> _updateXP() async {
    try {
      final xp = await XPStore.create();
      await xp.addXP(1);
    } catch (_) {
      // Ignore XP update errors
    }
  }

  /// Clears only today's japs (used on new day).
  /// IMPORTANT: Only resets today, never touches lifetime.
  Future<void> _resetToday() async {
    // Ensure lifetime cache is loaded before resetting today
    // This prevents accidentally overwriting lifetime with 0
    if (_cachedLifetime == null) {
      _cachedLifetime = _prefs.getInt(_kLifetimeJaps) ?? 0;
    }
    
    _cachedToday = 0;
    _cacheDirty = true;
    await _syncToDisk();
  }

  /// Resets today when the calendar day changes.
  Future<void> _resetIfNewDay() async {
    final now = DateTime.now();
    final today = _yyyymmdd(now);
    final last = _prefs.getString(_kLastDate);
    if (last != today) {
      await _prefs.setString(_kLastDate, today);
      await _resetToday();
    }
  }

  /// Optional: full reset for debugging.
  Future<void> resetAll() async {
    await _prefs.remove(_kTodayJaps);
    await _prefs.remove(_kLifetimeJaps);
    await _prefs.remove(_kLastDate);
  }

  static String _yyyymmdd(DateTime d) {
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '${d.year}-$m-$day';
  }
}
