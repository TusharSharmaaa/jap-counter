import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';

import '../data/insight_store.dart';

class SyncService {
  static Future<void> syncToday() async {
    await Firebase.initializeApp();
    final db = FirebaseFirestore.instance;
    final insights = await InsightStore.create();
    final today = DateTime.now().toIso8601String().substring(0, 10);

    await db.collection('insights').doc(today).set(
      {
        'date': today,
        'japs': insights.getTodayJaps(),
        'malas': insights.getTodayMalas(),
        'updatedAt': DateTime.now(),
      },
      SetOptions(merge: true),
    );
  }
}

