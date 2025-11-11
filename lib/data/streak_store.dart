import 'package:hive_flutter/hive_flutter.dart';

class StreakStore {
  static Future<void> init() async {
    await Hive.initFlutter();
  }

  static Future<void> saveStreak(int current, int total) async {
    final box = await Hive.openBox('streakBox');
    await box.put('current', current);
    await box.put('total', total);
  }

  static Future<Map<String, int>> loadStreak() async {
    final box = await Hive.openBox('streakBox');
    return {
      'current': box.get('current', defaultValue: 0) as int,
      'total': box.get('total', defaultValue: 0) as int,
    };
  }
}

