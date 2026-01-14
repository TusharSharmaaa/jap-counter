import '../core/prefs_manager.dart';

class GamifyStore {
  static const _kXp = 'gamify.xp';
  static const _kLevel = 'gamify.level';
  static const _kBadges = 'gamify.badges';

  static Future<int> xp() async {
    final prefs = await PrefsManager.instance;
    return prefs.getInt(_kXp) ?? 0;
  }

  static Future<int> level() async {
    final prefs = await PrefsManager.instance;
    return prefs.getInt(_kLevel) ?? 1;
  }

  // Maximum values to prevent integer overflow and performance issues
  static const int _maxLevel = 1000;
  static const int _maxXp = 1000000; // 1 million XP cap

  static int _xpForNext(int level) => 100 + (level - 1) * 50;

  static Future<Map<String, dynamic>> addXp(int delta) async {
    final prefs = await PrefsManager.instance;
    var currentXp = prefs.getInt(_kXp) ?? 0;
    var level = prefs.getInt(_kLevel) ?? 1;
    final previousLevel = level;

    // Cap delta to prevent overflow
    final safeDelta = delta.clamp(0, _maxXp);
    currentXp = (currentXp + safeDelta).clamp(0, _maxXp);
    var leveled = false;

    // Cap level to prevent infinite loops and overflow
    final maxLevel = _maxLevel;
    int iterations = 0;
    const maxIterations = 1000; // Safety limit for loop iterations

    while (currentXp >= _xpForNext(level) && level < maxLevel && iterations < maxIterations) {
      currentXp -= _xpForNext(level);
      level += 1;
      leveled = true;
      iterations++;
    }

    // If we hit max level, cap XP
    if (level >= maxLevel) {
      currentXp = _maxXp;
    }

    await prefs.setInt(_kXp, currentXp);
    await prefs.setInt(_kLevel, level.clamp(1, maxLevel));

    return {
      'xp': currentXp,
      'level': level.clamp(1, maxLevel),
      'leveledUp': leveled,
      'prevLevel': previousLevel,
      'nextThreshold': level >= maxLevel ? _maxXp : _xpForNext(level),
    };
  }

  static Future<void> awardBadge(String id) async {
    final prefs = await PrefsManager.instance;
    final csv = prefs.getString(_kBadges) ?? '';
    final set = <String>{...csv.split(',').where((e) => e.isNotEmpty)};

    if (set.add(id)) {
      await prefs.setString(_kBadges, set.join(','));
    }
  }

  static Future<Set<String>> badges() async {
    final prefs = await PrefsManager.instance;
    final csv = prefs.getString(_kBadges) ?? '';
    return <String>{...csv.split(',').where((e) => e.isNotEmpty)};
  }
}

