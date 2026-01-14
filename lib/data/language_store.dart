import '../core/prefs_manager.dart';

class LanguageStore {
  static const _key = 'app.language';
  static const supported = ['en', 'hi'];

  static Future<String> current() async {
    final prefs = await PrefsManager.instance;
    final stored = prefs.getString(_key);
    if (stored != null && supported.contains(stored)) {
      return stored;
    }
    return 'en';
  }

  static Future<void> save(String language) async {
    if (!supported.contains(language)) return;
    final prefs = await PrefsManager.instance;
    await prefs.setString(_key, language);
  }
}
