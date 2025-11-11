import 'package:shared_preferences/shared_preferences.dart';

class DedicationStore {
  static const _key = 'stats.dedication_note';

  static Future<String> get() async {
    final p = await SharedPreferences.getInstance();
    return p.getString(_key) ?? '';
  }

  static Future<void> set(String note) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_key, note.trim());
  }

  static Future<void> clear() async {
    final p = await SharedPreferences.getInstance();
    await p.remove(_key);
  }
}
