import 'package:shared_preferences/shared_preferences.dart';

import 'streak_store.dart';

/// Stores which dates the user was "active" (did at least 1 jap).
/// Dates are saved as ISO "yyyy-MM-dd" strings in a StringList.
class ActivityStore {
  static const _key = 'active_days'; // List<String> of yyyy-MM-dd

  /// Marks today as active (idempotent).
  static Future<void> markTodayActive() async {
    final prefs = await SharedPreferences.getInstance();
    final today = _isoDate(DateTime.now());
    final list = prefs.getStringList(_key) ?? <String>[];
    if (!list.contains(today)) {
      list.add(today);
      await prefs.setStringList(_key, list);
    }
  }

  /// Returns a Set of all active date strings.
  static Future<Set<String>> getAll() async {
    final prefs = await SharedPreferences.getInstance();
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
  /// Returns the length of the current consecutive-day streak (ending today).
  static Future<int> currentStreak() async {
    final active = await getAll();
    if (active.isEmpty) {
      await StreakStore.saveStreak(0, 0);
      return 0;
    }

    int streak = 0;
    final today = DateTime.now();
    for (int i = 0; i < 365; i++) {
      final d = DateTime(today.year, today.month, today.day).subtract(Duration(days: i));
      final key = _isoDate(d);
      if (active.contains(key)) {
        streak++;
      } else {
        break; // streak ended
      }
    }
    await StreakStore.saveStreak(streak, active.length);
    return streak;
  }
  static String _isoDate(DateTime d) {
    final y = d.year.toString().padLeft(4, '0');
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '$y-$m-$day';
  }

  static Future<void> resetAll() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
    await StreakStore.saveStreak(0, 0);
  }

  static Future<int> currentStreakDays() => currentStreak();
}
