import '../data/activity_store.dart';
import '../data/counter_store.dart';
import '../data/meditation_store.dart';

class LocalSummary {
  final int totalJaps;
  final int totalMalas;
  final int totalMinutes;
  final int streakDays;

  LocalSummary({
    required this.totalJaps,
    required this.totalMalas,
    required this.totalMinutes,
    required this.streakDays,
  });

  static Future<LocalSummary> load() async {
    final counter = await CounterStore.create();
    final meditation = await MeditationStore.create();
    final streakDays = await ActivityStore.currentStreakDays();

    return LocalSummary(
      totalJaps: counter.lifetimeJaps,
      totalMalas: counter.lifetimeJaps ~/ 108,
      totalMinutes: meditation.lifetimeMinutes,
      streakDays: streakDays,
    );
  }
}

