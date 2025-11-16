import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'activity_store.dart';
import 'counter_store.dart';
import 'dedication_store.dart';
import 'goal_store.dart';
import 'meditation_store.dart';
import 'session_store.dart';

class BackupService {
  static Future<Map<String, dynamic>> _collectAll() async {
    final counter = await CounterStore.create();
    final meditation = await MeditationStore.create();
    final sessions = await SessionStore.create();
    final goal = await GoalStore.create();
    final dedication = await DedicationStore.create();

    final streakDays = await ActivityStore.currentStreak();

    return {
      'timestamp': DateTime.now().toIso8601String(),
      'counter': {
        'todayJaps': counter.todayJaps,
        'lifetimeJaps': counter.lifetimeJaps,
      },
      'activity': {'streakDays': streakDays},
      'meditation': {
        'todayMinutes': meditation.todayMinutes,
        'lifetimeMinutes': meditation.lifetimeMinutes,
      },
      'sessions': await sessions.getSessions(),
      'goal': goal.dailyMalasGoal,
      'dedication': dedication.note,
    };
  }

  static Future<void> exportToJson() async {
    try {
      final data = await _collectAll();
      final encoded = const JsonEncoder.withIndent('  ').convert(data);
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/radha_jap_backup.json');
      await file.writeAsString(encoded);
      await Share.shareXFiles(
        [XFile(file.path)],
        text: '🌸 Radha Jap Backup',
      );
    } catch (e, stackTrace) {
      // Handle errors gracefully - log in debug, avoid crashing on bad storage/network conditions
      if (kDebugMode) {
        // ignore: avoid_print
        print('[BackupService] exportToJson failed: $e\n$stackTrace');
      }
      // Intentionally do NOT rethrow here so the app never crashes during backup export.
    }
  }
}

