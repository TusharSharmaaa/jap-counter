import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

class AppIdentity {
  AppIdentity._();

  static const _kIdentity = 'app.identity.id';

  static Future<String> id() async {
    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getString(_kIdentity);
    if (existing != null && existing.isNotEmpty) {
      return existing;
    }
    final generated = _generateId();
    await prefs.setString(_kIdentity, generated);
    return generated;
  }

  static String _generateId() {
    final random = Random();
    final buffer = StringBuffer();
    for (int i = 0; i < 16; i++) {
      buffer.write(random.nextInt(256).toRadixString(16).padLeft(2, '0'));
    }
    return buffer.toString();
  }
}

