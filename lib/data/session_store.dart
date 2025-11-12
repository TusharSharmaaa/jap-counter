import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class SessionStore {
  static const _kSessions = 'sessions.json';
  static const _maxSessions = 10;

  final SharedPreferences _prefs;

  SessionStore._(this._prefs);

  static Future<SessionStore> create() async =>
      SessionStore._(await SharedPreferences.getInstance());

  Future<List<Map<String, dynamic>>> getSessions() async {
    final raw = _prefs.getString(_kSessions);
    if (raw == null) return [];
    try {
      return List<Map<String, dynamic>>.from(jsonDecode(raw));
    } catch (_) {
      return [];
    }
  }

  Future<void> addSession({
    required String type, // "jap" or "meditation"
    required int count, // japs or minutes
  }) async {
    // Validate input bounds
    if (count < 0 || count > 1000000) {
      return; // Ignore invalid counts
    }
    if (type != 'jap' && type != 'meditation') {
      return; // Ignore invalid types
    }
    
    final list = await getSessions();
    final entry = {
      'type': type,
      'count': count,
      'date': DateTime.now().toIso8601String(),
    };
    list.insert(0, entry);
    if (list.length > _maxSessions) list.removeRange(_maxSessions, list.length);
    await _prefs.setString(_kSessions, jsonEncode(list));
  }

  Future<void> clear() async => _prefs.remove(_kSessions);
}

