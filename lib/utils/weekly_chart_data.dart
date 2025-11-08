import 'package:intl/intl.dart';

import '../data/activity_store.dart';

class WeeklyChartData {
  static Future<List<Map<String, dynamic>>> build() async {
    final history = await ActivityStore.getDailyHistory();
    final today = DateTime.now();
    final out = <Map<String, dynamic>>[];

    for (int i = 6; i >= 0; i--) {
      final date = today.subtract(Duration(days: i));
      final key = DateFormat('yyyy-MM-dd').format(date);
      final entry = history[key];
      final malas = switch (entry) {
        Map<String, dynamic> m => (m['malas'] as num?)?.round() ?? 0,
        _ => 0,
      };

      out.add({
        'day': DateFormat('E').format(date),
        'dateLabel': DateFormat('d').format(date),
        'value': malas < 0 ? 0 : malas,
      });
    }

    return out;
  }
}
