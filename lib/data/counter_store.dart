import 'dart:async' show unawaited, Timer, Completer;
import 'package:shared_preferences/shared_preferences.dart';

import '../core/prefs_manager.dart';
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
    await store._resetIfNewDay();
    // Load cache from disk
    store._cachedToday = prefs.getInt(_kTodayJaps) ?? 0;
    store._cachedLifetime = prefs.getInt(_kLifetimeJaps) ?? 0;
    _syncInstance = store;
    return store;
  }

  int get todayJaps => _cachedToday ?? _prefs.getInt(_kTodayJaps) ?? 0;
  int get lifetimeJaps => _cachedLifetime ?? _prefs.getInt(_kLifetimeJaps) ?? 0;

  int get todayMalas => todayJaps ~/ 108;
  int get lifetimeMalas => lifetimeJaps ~/ 108;

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
      // Update in-memory cache immediately for responsiveness
      _cachedToday = (_cachedToday ?? _prefs.getInt(_kTodayJaps) ?? 0) + 1;
      _cachedLifetime = (_cachedLifetime ?? _prefs.getInt(_kLifetimeJaps) ?? 0) + 1;
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
      await _prefs.setInt(_kTodayJaps, _cachedToday ?? 0);
      await _prefs.setInt(_kLifetimeJaps, _cachedLifetime ?? 0);
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
  Future<void> _resetToday() async {
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
