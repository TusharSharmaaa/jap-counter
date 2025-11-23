import 'dart:async' show unawaited, Timer, Completer, TimeoutException;
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/prefs_manager.dart';
import '../utils/retry_helper.dart';
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
  
  // Cache for lifetime malas calculation to avoid expensive recalculations
  static String? _cachedLifetimeMalasDate;
  static int? _cachedLifetimeMalasGlobal;
  
  // Keys
  static const _kTodayJaps = 'counter.todayJaps';
  static const _kLifetimeJaps = 'counter.lifetimeJaps';
  static const _kLastDate = 'counter.lastDate'; // YYYY-MM-DD

  /// Factory that also enforces daily reset.
  /// Uses singleton pattern to avoid expensive recalculations.
  static Future<CounterStore> create() async {
    final prefs = await PrefsManager.instance;
    final todayKey = _yyyymmdd(DateTime.now());
    
    // Reuse existing instance if it exists and date hasn't changed
    if (_syncInstance != null) {
      final lastDate = _syncInstance!._prefs.getString(_kLastDate);
      // If same day and instance exists, reuse it (avoid expensive history calculation)
      if (lastDate == todayKey && !_syncInstance!._cacheDirty) {
        return _syncInstance!;
      }
      
      // Force sync any pending writes from previous instance before loading
      if (_syncInstance!._cacheDirty) {
        await _syncInstance!._syncToDisk();
      }
    }
    
    final store = CounterStore._(prefs);
    
    await store._resetIfNewDay();
    // Load cache from disk - ensure we read the latest persisted values
    store._cachedToday = prefs.getInt(_kTodayJaps) ?? 0;
    final storedLifetime = prefs.getInt(_kLifetimeJaps) ?? 0;
    
    // CRITICAL: Calculate lifetime MALAS from completed malas in history
    // This ensures we only count COMPLETE malas (108 japs = 1 mala)
    // Strategy: Sum all completed malas from previous days + today's current completed malas
    // OPTIMIZATION: Only recalculate if date changed or cache is invalid
    final todayJaps = store._cachedToday ?? 0;
    final todayCompletedMalas = todayJaps ~/ 108;
    
    // Check if we can reuse cached lifetime malas calculation
    int totalLifetimeMalas;
    int lifetimeMalasFromPreviousDays;
    if (_cachedLifetimeMalasDate == todayKey && _cachedLifetimeMalasGlobal != null) {
      // Reuse cached calculation - just update with today's completed malas
      lifetimeMalasFromPreviousDays = _cachedLifetimeMalasGlobal!;
      totalLifetimeMalas = lifetimeMalasFromPreviousDays + todayCompletedMalas;
    } else {
      // Need to recalculate - this is expensive but only happens on new day or first load
      final history = await ActivityStore.getDailyHistory();
      
      // Sum completed malas from all previous days (excluding today)
      lifetimeMalasFromPreviousDays = 0;
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
      totalLifetimeMalas = lifetimeMalasFromPreviousDays + todayCompletedMalas;
      
      // Cache the result for future use
      _cachedLifetimeMalasDate = todayKey;
      _cachedLifetimeMalasGlobal = lifetimeMalasFromPreviousDays;
    }
    
    // Store the calculated lifetime malas (completed malas only)
    store._cachedLifetimeMalas = totalLifetimeMalas;
    
    // Convert lifetime malas to japs for storage compatibility
    final calculatedLifetimeJapsFromMalas = totalLifetimeMalas * 108;
    
    // For lifetime japs, use the maximum of:
    // 1. Lifetime japs calculated from completed malas (malas * 108)
    // 2. Stored lifetime japs - preserves data even if history is incomplete
    var calculatedLifetimeJaps = calculatedLifetimeJapsFromMalas;
    if (storedLifetime > calculatedLifetimeJaps) {
      calculatedLifetimeJaps = storedLifetime;
    }
    
    // Safety check: lifetime japs should never be less than today's japs
    if (calculatedLifetimeJaps < todayJaps) {
      calculatedLifetimeJaps = todayJaps;
      final todayCompletedMalasFromJaps = calculatedLifetimeJaps ~/ 108;
      if (todayCompletedMalasFromJaps > totalLifetimeMalas) {
        store._cachedLifetimeMalas = todayCompletedMalasFromJaps;
      }
    }
    
    // Store lifetime japs
    store._cachedLifetime = calculatedLifetimeJaps;
    
    // If calculated lifetime is higher than stored, update stored value
    if (store._cachedLifetime! > storedLifetime) {
      store._cacheDirty = true;
      await store._syncToDisk();
    }
    
    _syncInstance = store;
    return store;
  }

  int get todayJaps => _cachedToday ?? _prefs.getInt(_kTodayJaps) ?? 0;
  int get lifetimeJaps => _cachedLifetime ?? _prefs.getInt(_kLifetimeJaps) ?? 0;

  int get todayMalas => todayJaps ~/ 108; // TODO: Replace with AppConstants.japsPerMala
  
  /// Get lifetime malas - calculated from completed malas in history, not from japs
  /// This ensures we only count complete malas (108 japs = 1 mala)
  int get lifetimeMalas {
    // Use cached lifetime malas if available (calculated from history)
    // Otherwise, fall back to calculating from japs (but this should be rare)
    if (_cachedLifetimeMalas != null) {
      return _cachedLifetimeMalas!;
    }
    // Fallback: calculate from japs (should only happen if cache is not initialized)
    return lifetimeJaps ~/ 108; // TODO: Replace with AppConstants.japsPerMala
  }
  
  // Cache for lifetime malas calculated from history
  int? _cachedLifetimeMalas;
  
  /// Refresh lifetime malas calculation from history
  /// This should be called after recording daily summary to update the cache
  /// OPTIMIZATION: Uses cached calculation when possible
  Future<void> refreshLifetimeMalas() async {
    final todayKey = _yyyymmdd(DateTime.now());
    final todayJaps = _cachedToday ?? _prefs.getInt(_kTodayJaps) ?? 0;
    final todayCompletedMalas = todayJaps ~/ 108; // TODO: Replace with AppConstants.japsPerMala
    
    // Use cached previous days' malas if available and date matches
    if (_cachedLifetimeMalasDate == todayKey && _cachedLifetimeMalasGlobal != null) {
      _cachedLifetimeMalas = _cachedLifetimeMalasGlobal! + todayCompletedMalas;
      return;
    }
    
    // Otherwise recalculate (should be rare - only after date change or cache invalidated)
    final history = await ActivityStore.getDailyHistory();
    
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
    
    // Cache the previous days' malas for future use
    _cachedLifetimeMalasDate = todayKey;
    _cachedLifetimeMalasGlobal = lifetimeMalasFromPreviousDays;
    
    // Total lifetime malas = previous days' completed malas + today's current completed malas
    _cachedLifetimeMalas = lifetimeMalasFromPreviousDays + todayCompletedMalas;
  }
  
  /// Invalidate lifetime malas cache (call when history changes)
  static void invalidateLifetimeMalasCache() {
    _cachedLifetimeMalasDate = null;
    _cachedLifetimeMalasGlobal = null;
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
      
      // CRITICAL FIX: Reduce batch size from 10 to 5 to minimize data loss risk
      // Sync every 5 taps OR after 500ms of inactivity
      // This ensures maximum 4 taps could be lost (instead of 9) if app crashes
      if (_cachedToday! % 5 == 0) {
        await _syncToDisk(); // Force sync every 5 taps
        // Validate write succeeded
        await _validateSync();
      } else {
        _scheduleSync();
      }
      
      // Update XP asynchronously (non-blocking) with error handling
      unawaited(_updateXP().catchError((error, stackTrace) {
        // Silently ignore XP update errors - not critical
        if (kDebugMode) {
          debugPrint('[CounterStore] XP update failed: $error');
        }
      }));
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
    
    // OPTIMIZATION: Add timeout to prevent hanging on slow I/O
    try {
      await Future.any([
        _performSync(),
        Future.delayed(const Duration(seconds: 2), () {
          throw TimeoutException('Sync timeout');
        }),
      ]);
    } on TimeoutException {
      // If sync times out, mark dirty for retry but don't block
      // This prevents UI freezing on slow storage
      _cacheDirty = true;
    } catch (e) {
      // If sync fails, mark dirty again for retry
      _cacheDirty = true;
    }
  }
  
  Future<void> _performSync() async {
    // CRITICAL FIX: Use retry mechanism for failed writes
    await RetryHelper.retryVoid(
      operation: () async {
        // Always write today (it might be 0 if reset)
        final todayValue = _cachedToday ?? 0;
        await _prefs.setInt(_kTodayJaps, todayValue);
        
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
      },
      maxRetries: 3,
      initialDelay: const Duration(milliseconds: 100),
      maxDelay: const Duration(seconds: 1),
      onRetry: (attempt, error) {
        if (kDebugMode) {
          debugPrint('[CounterStore] Retrying sync (attempt $attempt): $error');
        }
      },
    );
  }
  
  /// Validate that sync succeeded by reading back values
  /// This ensures data persistence and catches write failures early
  Future<void> _validateSync() async {
    try {
      final persistedToday = _prefs.getInt(_kTodayJaps) ?? 0;
      final expectedToday = _cachedToday ?? 0;
      
      // If persisted value is less than expected, there was a write failure
      // This can happen on slow storage or if write was interrupted
      if (persistedToday < expectedToday) {
        if (kDebugMode) {
          debugPrint('[CounterStore] Sync validation failed: persisted=$persistedToday, expected=$expectedToday');
        }
        // Mark dirty again to retry sync
        _cacheDirty = true;
        // Retry sync immediately
        await _performSync();
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[CounterStore] Sync validation error: $e');
      }
      // Mark dirty for retry
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
