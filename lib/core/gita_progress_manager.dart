import 'package:shared_preferences/shared_preferences.dart';

class GitaProgressManager {
  static const _chapterKey = 'gita_last_chapter';
  static const _shlokKey = 'gita_last_shlok';
  static const _timestampKey = 'gita_last_read_timestamp';

  static Future<void> saveProgress(int chapter, int shlok) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_chapterKey, chapter);
    await prefs.setInt(_shlokKey, shlok);
    await prefs.setInt(_timestampKey, DateTime.now().millisecondsSinceEpoch);
  }

  static Future<(int chapter, int shlok)> loadProgress() async {
    final prefs = await SharedPreferences.getInstance();
    final chapter = prefs.getInt(_chapterKey) ?? 1;
    final shlok = prefs.getInt(_shlokKey) ?? 1;
    return (chapter, shlok);
  }

  static Future<void> clearProgress() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_chapterKey);
    await prefs.remove(_shlokKey);
    await prefs.remove(_timestampKey);
  }
}
