import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:firebase_core/firebase_core.dart';
import 'app.dart';
import 'firebase_options.dart';
import 'data/streak_store.dart';
import 'notifications/notification_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await StreakStore.init();
  await MobileAds.instance.initialize(); // init-only, no requests yet
  await NotificationService.initialize();
  try {
    await NotificationService().scheduleDailyMotivation();
  } catch (e, st) {
    if (kDebugMode) {
      debugPrint('[Notifications] scheduleDailyMotivation failed: $e\n$st');
    }
  }
  runApp(const App());
}
