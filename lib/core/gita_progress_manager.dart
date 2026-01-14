import 'package:shared_preferences/shared_preferences.dart';

class GitaProgressManager {
  static const _chapterKey = 'gita_last_chapter';
  static const _shlokKey = 'gita_last_shlok';
  static const _timestampKey = 'gita_last_read_timestamp';

  static Future<void> saveProgress(int chapter, int shlok) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_chapterKey, chapter);
      await prefs.setInt(_shlokKey, shlok);
      await prefs.setInt(_timestampKey, DateTime.now().millisecondsSinceEpoch);
    } catch (e) {
      // Handle SharedPreferences errors gracefully
      // Could log error in debug mode
    }
  }

  static Future<(int chapter, int shlok)> loadProgress() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final chapter = prefs.getInt(_chapterKey) ?? 1;
      final shlok = prefs.getInt(_shlokKey) ?? 1;
      return (chapter, shlok);
    } catch (e) {
      // Handle SharedPreferences errors gracefully - return defaults
      return (1, 1);
    }
  }

  static Future<void> clearProgress() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_chapterKey);
    await prefs.remove(_shlokKey);
    await prefs.remove(_timestampKey);
  }
}
