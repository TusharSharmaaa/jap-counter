import 'package:shared_preferences/shared_preferences.dart';

/// Tracks meditation minutes: today + lifetime, with daily reset.
class MeditationStore {
  static const _kTodayMinutes = 'med_today_minutes';
  static const _kLifetimeMinutes = 'med_lifetime_minutes';
  static const _kLastDate = 'med_last_date'; // yyyymmdd

  final SharedPreferences _prefs;

  MeditationStore._(this._prefs);

  static Future<MeditationStore> create() async {
    final prefs = await SharedPreferences.getInstance();
    final store = MeditationStore._(prefs);
    await store._ensureToday();
    return store;
  }

  /// Add minutes to today and lifetime.
  Future<void> addMinutes(int minutes) async {
    await _ensureToday();
    final today = _prefs.getInt(_kTodayMinutes) ?? 0;
    final life = _prefs.getInt(_kLifetimeMinutes) ?? 0;
    await _prefs.setInt(_kTodayMinutes, today + minutes);
    await _prefs.setInt(_kLifetimeMinutes, life + minutes);
  }

  int get todayMinutes {
    _ensureTodaySync();
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
}
