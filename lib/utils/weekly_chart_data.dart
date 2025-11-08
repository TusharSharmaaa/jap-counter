import 'package:intl/intl.dart';

import '../data/activity_store.dart';
import '../data/counter_store.dart';

class WeeklyChartData {
  static Future<List<Map<String, dynamic>>> build() async {
    final history = await ActivityStore.getDailyHistory();
    final counter = await CounterStore.create();
    final todayMalasLive = counter.todayJaps ~/ 108;
    final today = DateTime.now();
    final out = <Map<String, dynamic>>[];

    for (int i = 6; i >= 0; i--) {
      final date = today.subtract(Duration(days: i));
      final key = DateFormat('yyyy-MM-dd').format(date);
      final entry = history[key];
      var malas = switch (entry) {
        Map<String, dynamic> m => (m['malas'] as num?)?.round() ?? 0,
        _ => 0,
      };
      final isToday =
          date.year == today.year &&
          date.month == today.month &&
          date.day == today.day;
      if (malas == 0 && isToday) {
        malas = todayMalasLive;
      }

      out.add({
        'day': DateFormat('E').format(date),
        'dateLabel': DateFormat('d').format(date),
        'value': malas < 0 ? 0 : malas,
      });
    }

    return out;
  }
}
