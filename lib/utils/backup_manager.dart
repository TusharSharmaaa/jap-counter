import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../data/activity_store.dart';
import '../data/counter_store.dart';
import '../data/dedication_store.dart';
import '../data/insight_store.dart';

class BackupManager {
  static Future<String> exportBackup() async {
    try {
      final c = await CounterStore.create();
      final d = await DedicationStore.create();
      final i = await InsightStore.create();

      final streakDays = await ActivityStore.currentStreak();

      final data = {
        'date': DateTime.now().toIso8601String(),
        'streakDays': streakDays,
        'lifetimeMalas': c.lifetimeMalas,
        'lifetimeJaps': c.lifetimeJaps,
        'dedication': d.note,
        'todayJaps': c.todayJaps,
        'todayMalas': c.todayMalas,
        'insightJaps': i.getTodayJaps(),
        'insightMalas': i.getTodayMalas(),
      };

      final jsonStr = const JsonEncoder.withIndent('  ').convert(data);
      final dir = await getTemporaryDirectory();
      final file = File(
        '${dir.path}/radha_backup_${DateTime.now().millisecondsSinceEpoch}.json',
      );
      await file.writeAsString(jsonStr);
      return file.path;
    } catch (e, stackTrace) {
      if (kDebugMode) {
        // ignore: avoid_print
        print('[BackupManager] exportBackup failed: $e\n$stackTrace');
      }
      rethrow;
    }
  }

  static Future<void> importBackup(File file) async {
    try {
      final raw = await file.readAsString();
      final data = jsonDecode(raw);

      final d = await DedicationStore.create();
      await d.setNote(data['dedication'] ?? '');

      final c = await CounterStore.create();
      await c.resetAll();
      await c.increment(); // minimal to trigger daily init
    } catch (e, stackTrace) {
      if (kDebugMode) {
        // ignore: avoid_print
        print('[BackupManager] importBackup failed: $e\n$stackTrace');
      }
      rethrow;
    }
  }
}

