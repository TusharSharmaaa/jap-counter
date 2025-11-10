import 'package:shared_preferences/shared_preferences.dart';

class TimerPrefs {
  static const String lastDurationKey = 'timer_target_secs';
  static const String lastSoundKey = 'timer_sound';

  static const int defaultDurationSecs = 120;

  static Future<int> readDurationSecs() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(lastDurationKey) ?? defaultDurationSecs;
  }

  static Future<void> writeDurationSecs(int seconds) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(lastDurationKey, seconds);
  }

  static Future<String> readSound() async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getString(lastSoundKey) ?? 'mute').toLowerCase();
  }

  static Future<void> writeSound(String soundId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(lastSoundKey, soundId.toLowerCase());
  }
}