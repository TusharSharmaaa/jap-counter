import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final initStatus = await MobileAds.instance.initialize();
  // Optional: quick sanity log
  // debugPrint('AdMob initialized: ${initStatus.adapterStatuses}');
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Radha Jap Counter',
      home: const Scaffold(
        body: Center(child: Text('AdMob init-only → OK')),
      ),
    );
  }
}
