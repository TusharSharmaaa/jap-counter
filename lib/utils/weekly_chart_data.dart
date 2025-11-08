import 'package:intl/intl.dart';

import '../data/counter_store.dart';

class WeeklyChartData {
  static Future<List<Map<String, dynamic>>> build() async {
    final c = await CounterStore.create();
    final today = DateTime.now();
    final List<Map<String, dynamic>> out = [];
    for (int i = 6; i >= 0; i--) {
      final d = today.subtract(Duration(days: i));
      // Simple rolling data mock — you can replace with real per-day store later.
      final count = (c.todayJaps ~/ 108) - i;
      out.add({
        'day': DateFormat('E').format(d),
        'value': count < 0 ? 0 : count,
      });
    }
    return out;
  }
}

