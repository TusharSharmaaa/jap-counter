import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:firebase_core/firebase_core.dart';
import 'app.dart';
import 'core/ad_manager.dart';
import 'firebase_options.dart';
import 'data/streak_store.dart';
import 'notifications/notification_service.dart';
import 'splash/splash_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await StreakStore.init();
  await MobileAds.instance.initialize(); // init-only, no requests yet
  final requestConfig = RequestConfiguration(
    testDeviceIds: ['TEST_DEVICE_ID'],
  );
  await MobileAds.instance.updateRequestConfiguration(requestConfig);
  debugPrint('[AdInit] AdMob initialized');
  await AdManager.ensureInitialized();
  AdManager.instance.preloadAll();
  await NotificationService.initialize();
  try {
    await NotificationService().scheduleDailyMotivation();
  } catch (e, st) {
    if (kDebugMode) {
      debugPrint('[Notifications] scheduleDailyMotivation failed: $e\n$st');
    }
  }
  runApp(const RootApp());
}

class RootApp extends StatefulWidget {
  const RootApp({super.key});

  @override
  State<RootApp> createState() => _RootAppState();
}

class _RootAppState extends State<RootApp> {
  bool _done = false;

  @override
  Widget build(BuildContext context) {
    if (_done) {
      return const App();
    }
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: SplashPage(onComplete: () => setState(() => _done = true)),
    );
  }
}
