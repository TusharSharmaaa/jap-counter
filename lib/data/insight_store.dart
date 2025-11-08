import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

class InsightStore {
  final SharedPreferences _prefs;

  static const _prefix = 'insight_';

  InsightStore._(this._prefs);

  static Future<InsightStore> create() async =>
      InsightStore._(await SharedPreferences.getInstance());

  Future<void> recordJap({required int count, required int malas}) async {
    final today = DateTime.now().toIso8601String().substring(0, 10);

    await _prefs.setInt(
      '${_prefix}japs_$today',
      (_prefs.getInt('${_prefix}japs_$today') ?? 0) + count,
    );

    await _prefs.setInt(
      '${_prefix}malas_$today',
      (_prefs.getInt('${_prefix}malas_$today') ?? 0) + malas,
    );
  }

  int getTodayJaps() {
    final today = DateTime.now().toIso8601String().substring(0, 10);
    return _prefs.getInt('${_prefix}japs_$today') ?? 0;
  }

  int getTodayMalas() {
    final today = DateTime.now().toIso8601String().substring(0, 10);
    return _prefs.getInt('${_prefix}malas_$today') ?? 0;
  }

  String getRandomTip() {
    const tips = [
      'धीरे जपें, मन से जुड़ें।',
      '108 जप = 1 माला — निरंतरता ही साधना।',
      'शब्द से ज़्यादा भावना में शक्ति है।',
      'आज का एक शांत क्षण, कल का आत्मबल।',
      'साधना समय नहीं, अवस्था है।',
    ];
    return tips[Random().nextInt(tips.length)];
  }
}

