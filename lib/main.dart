import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'app.dart';
import 'bootstrap/app_bootstrapper.dart';
import 'data/streak_store.dart';
import 'firebase_options.dart';
import 'notifications/notification_service.dart';
import 'theme/theme.dart';

const _bootLog = '[BOOT]';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const SplashApp());
}

class SplashApp extends StatelessWidget {
  const SplashApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Radha Jap Counter',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      themeMode: ThemeMode.system,
      home: const SplashScaffold(),
    );
  }
}

class SplashScaffold extends StatefulWidget {
  const SplashScaffold({super.key});

  @override
  State<SplashScaffold> createState() => _SplashScaffoldState();
}

class _SplashScaffoldState extends State<SplashScaffold> {
  bool _navigated = false;

  @override
  void initState() {
    super.initState();
    _startBootstrap();
  }

  void _startBootstrap() {
    final bootstrapper = AppBootstrapper();
    final bootstrapFuture = () async {
      try {
        final result = await bootstrapper.run();
        debugPrint('$_bootLog bootstrap result → $result');
      } catch (error, stackTrace) {
        debugPrint('$_bootLog bootstrap failed: $error');
        if (kDebugMode) {
          debugPrint('$_bootLog bootstrap stack: $stackTrace');
        }
      }
    }();

    Future.any<void>([
      bootstrapFuture,
      Future<void>.delayed(const Duration(seconds: 3)),
    ]).then((_) => _openHome());

    _kickOffSecondaryTasks();
  }

  void _kickOffSecondaryTasks() {
    unawaited(_initializeFirebase());
    unawaited(_warmStreakStore());
    unawaited(_prepareNotifications());
  }

  Future<void> _initializeFirebase() async {
    try {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      ).timeout(const Duration(seconds: 3));
      debugPrint('$_bootLog Firebase initialized');
    } on TimeoutException {
      debugPrint('$_bootLog Firebase init timeout');
    } catch (error, stackTrace) {
      debugPrint('$_bootLog Firebase init failed: $error');
      if (kDebugMode) debugPrint('$_bootLog Firebase stack: $stackTrace');
    }
  }

  Future<void> _warmStreakStore() async {
    try {
      await StreakStore.init().timeout(const Duration(seconds: 2));
      debugPrint('$_bootLog StreakStore ready');
    } on TimeoutException {
      debugPrint('$_bootLog StreakStore init timeout');
    } catch (error, stackTrace) {
      debugPrint('$_bootLog StreakStore init failed: $error');
      if (kDebugMode) debugPrint('$_bootLog StreakStore stack: $stackTrace');
    }
  }

  Future<void> _prepareNotifications() async {
    try {
      await NotificationService.initialize()
          .timeout(const Duration(seconds: 2));
      await NotificationService()
          .scheduleDailyMotivation()
          .timeout(const Duration(seconds: 2));
      debugPrint('$_bootLog notifications primed');
    } on TimeoutException {
      debugPrint('$_bootLog notifications prep timeout');
    } catch (error, stackTrace) {
      debugPrint('$_bootLog notifications prep failed: $error');
      if (kDebugMode) debugPrint('$_bootLog notifications stack: $stackTrace');
    }
  }

  void _openHome() {
    if (!mounted || _navigated) return;
    _navigated = true;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const RootScaffold()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(
              'Starting...',
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: Colors.black87),
            ),
          ],
        ),
      ),
    );
  }
}

class RootScaffold extends StatelessWidget {
  const RootScaffold({super.key});

  @override
  Widget build(BuildContext context) {
    return const App();
  }
}
