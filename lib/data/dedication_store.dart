import 'package:shared_preferences/shared_preferences.dart';

import '../core/prefs_manager.dart';

/// Stores a short user dedication/note shown on the Stats page.
/// Offline-only (SharedPreferences). Keep it tiny: <= 200 chars recommended.
class DedicationStore {
  static const _kKey = 'dedication.note';

  DedicationStore._(this._prefs);

  final SharedPreferences _prefs;

  static Future<DedicationStore> create() async {
    final prefs = await PrefsManager.instance;
    return DedicationStore._(prefs);
  }

  String get note => _prefs.getString(_kKey) ?? '';

  Future<void> setNote(String value) async {
    // Sanitize input: remove control characters and limit length
    final sanitized = value
        .replaceAll(RegExp(r'[\x00-\x1F\x7F]'), '') // Remove control chars
        .trim();
    final capped = sanitized.length > 200 ? sanitized.substring(0, 200) : sanitized;
    await _prefs.setString(_kKey, capped);
  }

  Future<void> clear() async => _prefs.remove(_kKey);
}



