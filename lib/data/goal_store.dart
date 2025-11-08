import 'package:shared_preferences/shared_preferences.dart';

/// Stores user's daily mala goal (e.g., 1–10 malas).
/// Also caches the last-completed date to avoid repetitive nudges.
class GoalStore {
  static const _kDailyMalasGoal = 'goal.daily_malas';
  static const _kLastCongrats = 'goal.last_congrats_date'; // yyyy-MM-dd

  final SharedPreferences _prefs;

  GoalStore._(this._prefs);

  static Future<GoalStore> create() async =>
      GoalStore._(await SharedPreferences.getInstance());

  int get dailyMalasGoal => _prefs.getInt(_kDailyMalasGoal) ?? 0;

  Future<void> setDailyMalasGoal(int malas) async =>
      _prefs.setInt(_kDailyMalasGoal, malas.clamp(0, 50));

  String? get lastCongratsDate => _prefs.getString(_kLastCongrats);

  Future<void> setLastCongratsToday() async {
    final now = DateTime.now();
    final d =
        '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    await _prefs.setString(_kLastCongrats, d);
  }

  static String todayKey() {
    final now = DateTime.now();
    return '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }
}

