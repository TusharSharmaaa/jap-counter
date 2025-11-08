import 'package:shared_preferences/shared_preferences.dart';

class LanguageStore {
  static const _key = 'app.language';
  static const supported = ['en', 'hi'];

  static Future<String> current() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_key);
    if (stored != null && supported.contains(stored)) {
      return stored;
    }
    return 'en';
  }

  static Future<void> save(String language) async {
    if (!supported.contains(language)) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, language);
  }
}
