import 'package:shared_preferences/shared_preferences.dart';

import '../core/prefs_manager.dart';

class XPStore {
  static const _kXP = 'xp.total';

  final SharedPreferences _prefs;

  XPStore._(this._prefs);

  static Future<XPStore> create() async {
    final prefs = await PrefsManager.instance;
    return XPStore._(prefs);
  }

  int get totalXP => _prefs.getInt(_kXP) ?? 0;

  Future<void> addXP(int amount) async {
    if (amount <= 0) return;
    final newXP = totalXP + amount;
    await _prefs.setInt(_kXP, newXP);
  }

  int get level {
    // Add bounds checking to prevent overflow
    const maxXP = 1000000; // Cap at 1 million XP
    final cappedXP = totalXP.clamp(0, maxXP);
    final calculatedLevel = (cappedXP / 100).floor() + 1;
    const maxLevel = 10000; // Cap level at 10,000
    return calculatedLevel.clamp(1, maxLevel);
  }
}
