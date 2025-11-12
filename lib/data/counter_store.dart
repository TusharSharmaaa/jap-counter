import 'package:shared_preferences/shared_preferences.dart';

import 'xp_store.dart';

/// Offline-only store for Counter page with daily reset.
class CounterStore {
  CounterStore._(this._prefs);

  final SharedPreferences _prefs;

  // Keys
  static const _kTodayJaps = 'counter.todayJaps';
  static const _kLifetimeJaps = 'counter.lifetimeJaps';
  static const _kLastDate = 'counter.lastDate'; // YYYY-MM-DD

  /// Factory that also enforces daily reset.
  static Future<CounterStore> create() async {
    final prefs = await SharedPreferences.getInstance();
    final store = CounterStore._(prefs);
    await store._resetIfNewDay();
    return store;
  }

  int get todayJaps => _prefs.getInt(_kTodayJaps) ?? 0;
  int get lifetimeJaps => _prefs.getInt(_kLifetimeJaps) ?? 0;

  int get todayMalas => todayJaps ~/ 108;
  int get lifetimeMalas => lifetimeJaps ~/ 108;

  // Batch persistence state
  int _pendingIncrements = 0;
  static const int _batchSize = 10; // Flush every 10 taps
  static const Duration _batchTimeout = Duration(seconds: 2);

  /// Increment today + lifetime by 1 jap (batched for performance).
  /// Flushes immediately if batch size reached or after timeout.
  Future<void> increment() async {
    await _resetIfNewDay();
    _pendingIncrements++;
    
    // Flush if batch size reached
    if (_pendingIncrements >= _batchSize) {
      await _flushPending();
    }
  }

  /// Flush pending increments to storage.
  Future<void> _flushPending() async {
    if (_pendingIncrements == 0) return;
    
    final toAdd = _pendingIncrements;
    _pendingIncrements = 0;
    
    final currentToday = _prefs.getInt(_kTodayJaps) ?? 0;
    final currentLifetime = _prefs.getInt(_kLifetimeJaps) ?? 0;
    
    await _prefs.setInt(_kTodayJaps, currentToday + toAdd);
    await _prefs.setInt(_kLifetimeJaps, currentLifetime + toAdd);
    
    final xp = await XPStore.create();
    await xp.addXP(toAdd);
  }

  /// Force flush any pending increments (call on pause/dispose).
  Future<void> flushPending() => _flushPending();

  /// Clears only today's japs (used on new day).
  Future<void> _resetToday() async {
    await _prefs.setInt(_kTodayJaps, 0);
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
