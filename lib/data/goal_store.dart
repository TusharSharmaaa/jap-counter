import 'package:shared_preferences/shared_preferences.dart';

import '../core/app_constants.dart';
import '../core/prefs_manager.dart';

/// Stores user's daily mala goal (e.g., 1–10 malas).
/// Also caches the last-completed date to avoid repetitive nudges.
class GoalStore {
  static const _kDailyMalasGoal = 'goal.daily_malas';
  static const _kLastCongrats = 'goal.last_congrats_date'; // yyyy-MM-dd

  final SharedPreferences _prefs;

  GoalStore._(this._prefs);

  static Future<GoalStore> create() async =>
      GoalStore._(await PrefsManager.instance);

  int get dailyMalasGoal => _prefs.getInt(_kDailyMalasGoal) ?? 0;

  Future<void> setDailyMalasGoal(int malas) async {
    // Validate and clamp goal value
    final validated = malas.clamp(AppConstants.minGoalValue, AppConstants.maxGoalValue);
    await _prefs.setInt(_kDailyMalasGoal, validated);
  }

  String? get lastCongratsDate => _prefs.getString(_kLastCongrats);

  /// Shared helper method for date formatting (YYYY-MM-DD)
  static String _formatDate(DateTime date) {
    return '${date.year.toString().padLeft(4, '0')}-'
        '${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}';
  }

  Future<void> setLastCongratsToday() async {
    final d = _formatDate(DateTime.now());
    await _prefs.setString(_kLastCongrats, d);
  }
  
  /// Clear the last congrats date (useful when goal is increased)
  Future<void> clearLastCongrats() async {
    await _prefs.remove(_kLastCongrats);
  }

  static String todayKey() {
    return _formatDate(DateTime.now());
  }
}

