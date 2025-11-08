import 'package:shared_preferences/shared_preferences.dart';

/// Stores a short user dedication/note shown on the Stats page.
/// Offline-only (SharedPreferences). Keep it tiny: <= 200 chars recommended.
class DedicationStore {
  static const _kKey = 'dedication.note';

  DedicationStore._(this._prefs);

  final SharedPreferences _prefs;

  static Future<DedicationStore> create() async {
    final prefs = await SharedPreferences.getInstance();
    return DedicationStore._(prefs);
  }

  String get note => _prefs.getString(_kKey) ?? '';

  Future<void> setNote(String value) async {
    final trimmed = value.trim();
    final capped = trimmed.length > 200 ? trimmed.substring(0, 200) : trimmed;
    await _prefs.setString(_kKey, capped);
  }

  Future<void> clear() async => _prefs.remove(_kKey);
}
