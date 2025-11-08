import 'package:shared_preferences/shared_preferences.dart';

class GamifyStore {
  static const _kXp = 'gamify.xp';
  static const _kLevel = 'gamify.level';
  static const _kBadges = 'gamify.badges';

  static Future<int> xp() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_kXp) ?? 0;
  }

  static Future<int> level() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_kLevel) ?? 1;
  }

  static int _xpForNext(int level) => 100 + (level - 1) * 50;

  static Future<Map<String, dynamic>> addXp(int delta) async {
    final prefs = await SharedPreferences.getInstance();
    var currentXp = prefs.getInt(_kXp) ?? 0;
    var level = prefs.getInt(_kLevel) ?? 1;

    currentXp += delta;
    var leveled = false;

    while (currentXp >= _xpForNext(level)) {
      currentXp -= _xpForNext(level);
      level += 1;
      leveled = true;
    }

    await prefs.setInt(_kXp, currentXp);
    await prefs.setInt(_kLevel, level);

    return {
      'xp': currentXp,
      'level': level,
      'leveledUp': leveled,
    };
  }

  static Future<void> awardBadge(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final csv = prefs.getString(_kBadges) ?? '';
    final set = <String>{...csv.split(',').where((e) => e.isNotEmpty)};

    if (set.add(id)) {
      await prefs.setString(_kBadges, set.join(','));
    }
  }

  static Future<Set<String>> badges() async {
    final prefs = await SharedPreferences.getInstance();
    final csv = prefs.getString(_kBadges) ?? '';
    return <String>{...csv.split(',').where((e) => e.isNotEmpty)};
  }
}

