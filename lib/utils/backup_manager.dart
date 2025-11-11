import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../data/activity_store.dart';
import '../data/counter_store.dart';
import '../data/dedication_store.dart';
import '../data/insight_store.dart';

class BackupManager {
  static Future<String> exportBackup() async {
    final c = await CounterStore.create();
    final d = await DedicationStore.create();
    final i = await InsightStore.create();

    final data = {
      'date': DateTime.now().toIso8601String(),
      'streakDays': await ActivityStore.currentStreak(),
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
    final file = File('${dir.path}/radha_backup_${DateTime.now().millisecondsSinceEpoch}.json');
    await file.writeAsString(jsonStr);
    return file.path;
  }

  static Future<void> importBackup(File file) async {
    final raw = await file.readAsString();
    final data = jsonDecode(raw);

    final d = await DedicationStore.create();
    await d.setNote(data['dedication'] ?? '');

    final c = await CounterStore.create();
    await c.resetAll();
    await c.increment(); // minimal to trigger daily init
  }
}

