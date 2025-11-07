import 'package:shared_preferences/shared_preferences.dart';

enum TimerPrefKeys { minutes, sound }

class TimerPrefs {
  static const _kMinutes = 'timer_minutes';
  static const _kSound = 'timer_sound'; // enum index

  final SharedPreferences _prefs;
  TimerPrefs._(this._prefs);

  static Future<TimerPrefs> create() async {
    final p = await SharedPreferences.getInstance();
    return TimerPrefs._(p);
  }

  int get minutes => _prefs.getInt(_kMinutes) ?? 10;
  Future<void> setMinutes(int m) => _prefs.setInt(_kMinutes, m);

  int get soundIndex => _prefs.getInt(_kSound) ?? 0; // 0 = mute
  Future<void> setSoundIndex(int i) => _prefs.setInt(_kSound, i);
}