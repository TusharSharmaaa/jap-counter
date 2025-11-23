import 'dart:async' show Completer, unawaited;

import 'package:shared_preferences/shared_preferences.dart';

import '../core/prefs_manager.dart';
import 'xp_store.dart';

/// Tracks meditation minutes: today + lifetime, with daily reset.
class MeditationStore {
  static const _kTodayMinutes = 'med_today_minutes';
  static const _kLifetimeMinutes = 'med_lifetime_minutes';
  static const _kLastDate = 'med_last_date'; // yyyymmdd

  final SharedPreferences _prefs;
  
  // Lock to prevent race conditions in addMinutes operations
  static Completer<void>? _addMinutesLock;

  MeditationStore._(this._prefs);

  static Future<MeditationStore> create() async {
    final prefs = await PrefsManager.instance;
    final store = MeditationStore._(prefs);
    await store._ensureToday();
    return store;
  }

  /// Add minutes to today and lifetime.
  /// CRITICAL FIX: Added locking to prevent race conditions in concurrent writes.
  Future<void> addMinutes(int minutes) async {
    // Wait for any ongoing addMinutes operation to complete
    if (_addMinutesLock != null) {
      await _addMinutesLock!.future;
    }
    
    // Create lock for this operation
    final lock = Completer<void>();
    _addMinutesLock = lock;
    
    try {
      await _ensureToday();
      
      // Read current values
      final today = _prefs.getInt(_kTodayMinutes) ?? 0;
      final life = _prefs.getInt(_kLifetimeMinutes) ?? 0;
      
      // Validate minutes is non-negative
      final validMinutes = minutes < 0 ? 0 : minutes;
      
      // Write new values atomically (protected by lock)
      await _prefs.setInt(_kTodayMinutes, today + validMinutes);
      await _prefs.setInt(_kLifetimeMinutes, life + validMinutes);
      
      // Update XP asynchronously (non-blocking)
      if (validMinutes > 0) {
        unawaited(XPStore.create().then((xp) => xp.addXP(validMinutes ~/ 5)).catchError((_) {
          // Silently ignore XP update errors - not critical
        }));
      }
    } finally {
      // Release lock
      _addMinutesLock = null;
      lock.complete();
    }
  }

  /// Synchronous getter for today's minutes.
  /// Note: Uses synchronous SharedPreferences operations which are safe for getters.
  /// For async contexts, prefer [getTodayMinutesAsync()] instead.
  int get todayMinutes {
    _ensureTodaySync();
    return _prefs.getInt(_kTodayMinutes) ?? 0;
  }
  
  /// Async version for ensuring today is reset - use this when possible
  Future<int> getTodayMinutesAsync() async {
    await _ensureToday();
    return _prefs.getInt(_kTodayMinutes) ?? 0;
  }

  int get lifetimeMinutes => _prefs.getInt(_kLifetimeMinutes) ?? 0;

  // ---- daily reset helpers ----

  Future<void> _ensureToday() async {
    final todayStr = _yyyymmddNow();
    final last = _prefs.getString(_kLastDate);
    if (last != todayStr) {
      await _prefs.setInt(_kTodayMinutes, 0);
      await _prefs.setString(_kLastDate, todayStr);
    }
  }

  void _ensureTodaySync() {
    final todayStr = _yyyymmddNow();
    final last = _prefs.getString(_kLastDate);
    if (last != todayStr) {
      _prefs.setInt(_kTodayMinutes, 0);
      _prefs.setString(_kLastDate, todayStr);
    }
  }

  String _yyyymmddNow() {
    final now = DateTime.now();
    final y = now.year.toString().padLeft(4, '0');
    final m = now.month.toString().padLeft(2, '0');
    final d = now.day.toString().padLeft(2, '0');
    return '$y$m$d';
  }

  Future<void> resetAll() async {
    await _prefs.remove(_kTodayMinutes);
    await _prefs.remove(_kLifetimeMinutes);
    await _prefs.remove(_kLastDate);
  }
}
