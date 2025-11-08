import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:confetti/confetti.dart';

import 'stats/streak_share_preview.dart';
import 'ads/rewarded.dart';
import 'content/content_page.dart';
import 'timer/timer_page.dart';
import 'data/meditation_store.dart';
import 'ads/rewarded_share.dart';
import 'stats/share_gate.dart';
import 'stats/dedication_store.dart';
import 'stats/stats_ambience.dart';
import 'settings/settings_page.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'notifications/notification_service.dart';
import 'data/activity_store.dart';
import 'ads/test_banner.dart';
import 'data/counter_store.dart';
import 'theme/neumorph.dart';
import 'gamify/gamify_store.dart';
import 'theme/theme.dart';
import 'package:audioplayers/audioplayers.dart';
import 'ads/interstitial_timer.dart';


class App extends StatefulWidget {
  const App({super.key});
  @override
  State<App> createState() => _AppState();
}

class _AppState extends State<App> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    // Preload the rewarded ad used for "Share My Streak"
    RewardedShareAd().preload();
    // Observe app lifecycle to keep the ad warmed up on resume
    WidgetsBinding.instance.addObserver(this);

    _loadThemeMode();
    _initNotifications(); // fire-and-forget
    WidgetsBinding.instance.addPostFrameCallback((_) {
      for (final page in _pages) {
        if (page is StatefulWidget) {
          final key = page.key;
          if (key is GlobalKey) {
            key.currentState;
          }
        }
      }
      RewardedShareAd().preload();
      TimerInterstitialGate.instance.preload();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Ensure a rewarded ad is queued when user comes back to the app
      RewardedShareAd().ensureWarm();
    }
  }
  int _index = 0;
  final GlobalKey<_StatsPageState> _statsKey = GlobalKey<_StatsPageState>();
  ThemeMode _themeMode = ThemeMode.system;

  late final List<Widget> _pages = [
    const _CounterPage(),
    _StatsPage(key: _statsKey),
    const _ContentPage(),
    const TimerPage(),
  ];

  Future<void> _loadThemeMode() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getInt('themeMode') ?? ThemeMode.system.index;
    final values = ThemeMode.values;
    final mode = (stored >= 0 && stored < values.length) ? values[stored] : ThemeMode.system;
    if (mounted) {
      setState(() => _themeMode = mode);
    } else {
      _themeMode = mode;
    }
  }

  Future<void> _saveThemeMode(ThemeMode mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('themeMode', mode.index);
  }

  Future<void> _initNotifications() async {
    final ns = NotificationService();
    await ns.init();
    final allowed = await ns.requestPermission();
    if (allowed) {
      await ns.scheduleDefaults();
    } else {
      // Optional: You can show a SnackBar later if you add a UI toggle.
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Radha Jap Counter',
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      themeMode: _themeMode,
      home: Scaffold(
        body: AnimatedSwitcher(
          duration: const Duration(milliseconds: 280),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          transitionBuilder: (child, animation) {
            final offset = Tween<Offset>(
              begin: const Offset(0.03, 0.02),
              end: Offset.zero,
            ).animate(animation);
            return FadeTransition(
              opacity: animation,
              child: SlideTransition(position: offset, child: child),
            );
          },
          child: (_index == 4)
              ? SettingsPage(
                  key: const ValueKey('settings'),
                  themeMode: _themeMode,
                  onThemeModeChanged: (mode) {
                    setState(() => _themeMode = mode);
                    _saveThemeMode(mode);
                  },
                )
              : KeyedSubtree(
                  key: ValueKey('tab-$_index'),
                  child: _pages[_index],
                ),
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _index,
          onDestinationSelected: (i) {
            if (i == 1) {
              RewardedShareAd().preload();
              if (kDebugMode) {
                final rem = RewardedShareAd().cooldownRemaining;
                if (rem != null && rem > Duration.zero) {
                  debugPrint('[RewardedShareAd] Cooldown remaining: ${rem.inMinutes}m ${rem.inSeconds % 60}s');
                } else {
                  debugPrint('[RewardedShareAd] No cooldown active.');
                }
              }
              _statsKey.currentState?.onBecameVisible();
            } else {
              _statsKey.currentState?.onBecameHidden();
            }

            setState(() => _index = i);
          },
          destinations: const [

            NavigationDestination(icon: Icon(Icons.touch_app), label: 'Counter'),
            NavigationDestination(icon: Icon(Icons.bar_chart), label: 'Stats'),
            NavigationDestination(icon: Icon(Icons.menu_book), label: 'Content'),
            NavigationDestination(icon: Icon(Icons.timer), label: 'Timer'),
            NavigationDestination(icon: Icon(Icons.settings), label: 'Settings'),
          ],
        ),
      ),
      debugShowCheckedModeBanner: false,
    );
  }
  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}

class _BannerReserve extends StatelessWidget {
  const _BannerReserve();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 52, // reserved space for a standard banner
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(top: BorderSide(width: 0.5, color: Theme.of(context).dividerColor)),
        ),
        child: const Center(child: Text('Ad Banner (reserved)')),
      ),
    );
  }
}


class _CounterPage extends StatefulWidget {
  const _CounterPage();

  @override
  State<_CounterPage> createState() => _CounterPageState();
}

class _CounterPageState extends State<_CounterPage> {
  CounterStore? _store;
  bool _loading = true;
  int _today = 0;
  int _lifetime = 0;
  bool _pulse = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final s = await CounterStore.create(); // enforces daily reset
    setState(() {
      _store = s;
      _today = s.todayJaps;
      _lifetime = s.lifetimeJaps;
      _loading = false;
    });
  }

  Future<void> _showLevelUpDialog(int newLevel) async {
    if (!mounted) return;
    await showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              const Icon(Icons.emoji_events, size: 26),
              const SizedBox(width: 8),
              const Text('Level Up!'),
            ],
          ),
          content: Text('You reached Level $newLevel.\nKeep the साधना flowing ✨'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('जय राधे'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _inc() async {
    final s = _store;
    if (s == null) return;

    final wasZero = _today == 0;            // track 0 → 1 transition
    final willBe = _today + 1; // value after this tap
    await s.increment();

    try {
      final xpRes = await GamifyStore.addXp(1);
      if (xpRes['leveledUp'] == true) {
        try {
          HapticFeedback.mediumImpact();
        } catch (_) {}
        try {
          final bell = AudioPlayer();
          await bell.play(AssetSource('sounds/bell.mp3'));
        } catch (_) {}
        await _showLevelUpDialog(xpRes['level'] as int? ?? 1);
      }
    } catch (_) {}
// If this was the first jap of the day, mark today as active
    if (wasZero) {
      await ActivityStore.markTodayActive();
    }
    // If first jap today, check for streak milestones
    if (wasZero) {
      final streak = await ActivityStore.currentStreak();
      if (!mounted) return;
      if (streak == 7 || streak == 21 || streak == 40) {
        try {
          await GamifyStore.awardBadge('streak_$streak');
          await GamifyStore.addXp(30);
        } catch (_) {}
        try {
          HapticFeedback.mediumImpact();
        } catch (_) {}
        try {
          final bell = AudioPlayer();
          await bell.play(AssetSource('sounds/bell.mp3'));
        } catch (_) {}
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: Text('✨ $streak-day streak! Keep going.'),
              behavior: SnackBarBehavior.floating,
              duration: const Duration(seconds: 3),
            ),
          );
      }
    }
    if (!mounted) return;

    // Light tap feedback every press
    HapticFeedback.selectionClick();

    // Stronger feedback + toast on completing a mala (108, 216, 324, ...)
    if (willBe % 108 == 0) {
      try {
        HapticFeedback.mediumImpact();
      } catch (_) {}
      setState(() => _pulse = true);
      Future.delayed(const Duration(milliseconds: 250), () {
        if (mounted) setState(() => _pulse = false);
      });
      try {
        final xpRes = await GamifyStore.addXp(20);
        final next = xpRes['nextThreshold'] as int? ?? 0;
        final xp = xpRes['xp'] as int? ?? 0;
        final level = xpRes['level'] as int? ?? 1;
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: Text('🎯 Mala completed!  +20 XP  •  Level $level  ($xp/$next)'),
              duration: const Duration(seconds: 3),
              behavior: SnackBarBehavior.floating,
            ),
          );
        if (xpRes['leveledUp'] == true) {
          try {
            final bell = AudioPlayer();
            await bell.play(AssetSource('sounds/bell.mp3'));
          } catch (_) {}
          await _showLevelUpDialog(level);
        }
      } catch (_) {}
    }

    setState(() {
      _today = s.todayJaps;
      _lifetime = s.lifetimeJaps;
    });

    final ns = NotificationService();
    await ns.scheduleDynamicJapReminder(_today);
  }

  int get _malas => _today ~/ 108;
  int get _lifetimeMalas => _lifetime ~/ 108;

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Counter')),
        body: const Center(child: CircularProgressIndicator()),
        bottomNavigationBar: const TestBanner(),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Counter')),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                Expanded(child: _StatTile(title: "Today's Japs", value: _today.toString())),
                const SizedBox(width: 8),
                Expanded(child: _StatTile(title: "Malas", value: _malas.toString())),
                const SizedBox(width: 8),
                Expanded(child: _StatTile(title: "Lifetime Malas", value: _lifetimeMalas.toString())),
              ],
            ),
          ),
          const SizedBox(height: 24),
          const SizedBox(height: 8),
          _MalaProgress(todayJaps: _today),
          const SizedBox(height: 8),
          Expanded(
            child: Center(
              child: GestureDetector(
                onTap: _inc,
                behavior: HitTestBehavior.opaque,
                child: Container(
                  width: double.infinity,
                  margin: const EdgeInsets.symmetric(horizontal: 16),
                  padding: const EdgeInsets.symmetric(vertical: 32),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.25)),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('Tap to Count', style: Theme.of(context).textTheme.titleLarge),
                      const SizedBox(height: 12),
                      AnimatedScale(
                        scale: _pulse ? 1.12 : 1.0,
                        duration: const Duration(milliseconds: 220),
                        curve: Curves.easeOut,
                        child: Text('$_today', style: Theme.of(context).textTheme.displaySmall),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: const TestBanner(),
    );
  }
}

class _StatTile extends StatelessWidget {
  final String title;
  final String value;
  const _StatTile({required this.title, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 68,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.labelMedium),
          const Spacer(),
          Text(value, style: Theme.of(context).textTheme.titleLarge),
        ],
      ),
    );
  }
}

class _NeoTile extends StatelessWidget {
  final String title;
  final String value;

  const _NeoTile({required this.title, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 72,
      decoration: Neo.card(context),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.labelMedium),
          const Spacer(),
          Text(
            value,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

class _MalaProgress extends StatelessWidget {
  final int todayJaps;
  const _MalaProgress({required this.todayJaps});

  @override
  Widget build(BuildContext context) {
    final inThisMala = todayJaps % 108;
    final remaining = 108 - inThisMala;
    final progress = inThisMala / 108.0;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '$remaining more to complete this mala',
            style: Theme.of(context).textTheme.bodyMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(value: progress),
          ),
        ],
      ),
    );
  }
}


class _StatsPage extends StatefulWidget {
  const _StatsPage({super.key});

  @override
  State<_StatsPage> createState() => _StatsPageState();
}

class _StatsPageState extends State<_StatsPage> {
  final RewardedGate _gate = RewardedGate();
  bool _shareBusy = false;
  late final ConfettiController _confetti;
  bool _loading = true;
  int _today = 0;
  int _lifetime = 0;
  int _todayMin = 0;
  int _lifetimeMin = 0;
  static const _ambienceKey = 'stats.ambience.enabled';
  bool _ambienceEnabled = false;

  @override
  void initState() {
    super.initState();
    _confetti = ConfettiController(duration: const Duration(seconds: 3));
    _init();

    // Warm up the rewarded ad in the background
    // ignore: unawaited_futures
    _gate.load();
    _loadAmbiencePref();
  }

  @override
  void dispose() {
    _confetti.dispose();
    StatsAmbience.instance.stop();
    super.dispose();
  }

  Future<void> _loadAmbiencePref() async {
    final p = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() => _ambienceEnabled = p.getBool(_ambienceKey) ?? false);
  }

  Future<void> _saveAmbiencePref(bool v) async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(_ambienceKey, v);
  }

  Future<Map<String, dynamic>> _loadLevelSnapshot() async {
    final xp = await GamifyStore.xp();
    final level = await GamifyStore.level();
    return {'xp': xp, 'level': level};
  }

  void onBecameVisible() {
    if (_ambienceEnabled) {
      StatsAmbience.instance.start();
    }
  }

  void onBecameHidden() {
    StatsAmbience.instance.stop();
  }

  Future<void> _refresh() async {
    final s = await CounterStore.create();
    final mstore = await MeditationStore.create();

    if (!mounted) return;
    setState(() {
      _today = s.todayJaps;
      _lifetime = s.lifetimeJaps;

      _todayMin = mstore.todayMinutes;
      _lifetimeMin = mstore.lifetimeMinutes;
    });
    // Also ensure today is marked active on manual refresh
    if (s.todayJaps > 0) {
      await ActivityStore.markTodayActive();
    }

    final streak = await ActivityStore.currentStreak();
    if ([7, 21, 40].contains(streak)) {
      _confetti.play();
    }
  }

  Future<void> _init() async {
    final s = await CounterStore.create(); // uses same prefs + new-day reset

    // NEW: meditation store
    final mstore = await MeditationStore.create();

    setState(() {
      _today = s.todayJaps;
      _lifetime = s.lifetimeJaps;
      _loading = false;

      // NEW:
      _todayMin = mstore.todayMinutes;
      _lifetimeMin = mstore.lifetimeMinutes;
    });
    // Ensure today is recorded as active if user already has japs today
    if (s.todayJaps > 0) {
      await ActivityStore.markTodayActive();
    }

    final streak = await ActivityStore.currentStreak();
    if ([7, 21, 40].contains(streak)) {
      _confetti.play();
    }

  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Stats')),
        body: const Center(child: CircularProgressIndicator()),
        bottomNavigationBar: const _BannerReserve(),
      );
    }

    final todayMalas = _today ~/ 108;
    final lifetimeMalas = _lifetime ~/ 108;
    final cooling = RewardedShareAd().isCoolingDown;
    final rem = RewardedShareAd().cooldownRemaining;
    final remLabel = (rem != null && rem > Duration.zero)
        ? (rem.inMinutes > 0 ? '${rem.inMinutes}m ${rem.inSeconds % 60}s' : '${rem.inSeconds % 60}s')
        : null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Stats'),
        actions: [
          IconButton(
            tooltip: _ambienceEnabled ? 'Ambience On' : 'Ambience Off',
            icon: Icon(_ambienceEnabled ? Icons.spatial_audio_off : Icons.spatial_audio),
            onPressed: () async {
              final next = !_ambienceEnabled;
              setState(() => _ambienceEnabled = next);
              await _saveAmbiencePref(next);
              if (next) {
                StatsAmbience.instance.start();
              } else {
                StatsAmbience.instance.stop();
              }
            },
          ),
        ],
      ),
      body: Stack(
        children: [
          RefreshIndicator(
            onRefresh: _refresh,
            child: _buildStatsList(context, cooling, remLabel, todayMalas, lifetimeMalas),
          ),
          Align(
            alignment: Alignment.topCenter,
            child: ConfettiWidget(
              confettiController: _confetti,
              blastDirectionality: BlastDirectionality.explosive,
              emissionFrequency: 0.05,
              numberOfParticles: 20,
              colors: const [Colors.orange, Colors.yellow, Colors.pink, Colors.white],
            ),
          ),
        ],
      ),
      bottomNavigationBar: const _BannerReserve(),
    );
  }

  Widget _buildStatsList(
    BuildContext context,
    bool cooling,
    String? remLabel,
    int todayMalas,
    int lifetimeMalas,
  ) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Column(
            children: [
              AnimatedScale(
                duration: const Duration(milliseconds: 1500),
                curve: Curves.easeInOutCubic,
                scale: _ambienceEnabled ? 1.2 : 1.0,
                child: Icon(
                  Icons.self_improvement,
                  size: 64,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                _ambienceEnabled ? "ॐ की ध्वनि गूंज रही है…" : "शांति का अनुभव करें",
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Theme.of(context).dividerColor),
          ),
          child: FutureBuilder<int>(
            future: ActivityStore.currentStreak(),
            builder: (context, snap) {
              final streak = snap.data ?? 0;
              return Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Current Streak',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '🔥 $streak',
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
        FutureBuilder<Map<String, dynamic>>(
          future: _loadLevelSnapshot(),
          builder: (context, snapshot) {
            final xp = (snapshot.data?['xp'] ?? 0) as int;
            final level = (snapshot.data?['level'] ?? 1) as int;
            final next = 100 + (level - 1) * 50;
            final progress = (xp / next).clamp(0.0, 1.0);

            return Container(
              margin: const EdgeInsets.only(top: 12),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: Neo.pill(context),
              child: Row(
                children: [
                  Text('Level $level', style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: LinearProgressIndicator(value: progress, minHeight: 8),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text('$xp/$next', style: Theme.of(context).textTheme.labelMedium),
                ],
              ),
            );
          },
        ),
        FutureBuilder<Set<String>>(
          future: GamifyStore.badges(),
          builder: (context, snapshot) {
            final badges = snapshot.data ?? <String>{};
            if (badges.isEmpty) return const SizedBox.shrink();

            return Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: badges.map((badge) {
                  final label = switch (badge) {
                    'streak_7' => '🔥 7-day Streak',
                    'streak_21' => '🔥 21-day Streak',
                    'streak_40' => '🔥 40-day Streak',
                    _ => badge,
                  };
                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: Neo.pill(context),
                    child: Text(label, style: Theme.of(context).textTheme.labelLarge),
                  );
                }).toList(),
              ),
            );
          },
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(child: _NeoTile(title: "Today's Japs", value: _today.toString())),
            const SizedBox(width: 8),
            Expanded(child: _NeoTile(title: "Today's Malas", value: todayMalas.toString())),
            const SizedBox(width: 8),
            Expanded(child: _NeoTile(title: "Lifetime Malas", value: lifetimeMalas.toString())),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(child: _NeoTile(title: "Today's Meditation (min)", value: _todayMin.toString())),
            const SizedBox(width: 8),
            Expanded(child: _NeoTile(title: "Lifetime Meditation (min)", value: _lifetimeMin.toString())),
          ],
        ),
        const SizedBox(height: 16),
        FutureBuilder<String>(
          future: DedicationStore.get(),
          builder: (context, snap) {
            final note = snap.data ?? '';
            return Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Theme.of(context).dividerColor),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.favorite, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      note.isEmpty ? 'Dedication: (tap edit to add)' : 'Dedication: $note',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ),
                  const SizedBox(width: 8),
                  TextButton.icon(
                    onPressed: () async {
                      final controller = TextEditingController(text: note);
                      final updated = await showDialog<String>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: const Text('Edit Dedication'),
                          content: TextField(
                            controller: controller,
                            maxLines: 3,
                            textInputAction: TextInputAction.done,
                            decoration: const InputDecoration(
                              hintText: 'e.g., माता-पिता के नाम',
                              border: OutlineInputBorder(),
                            ),
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(ctx, null),
                              child: const Text('Cancel'),
                            ),
                            FilledButton(
                              onPressed: () => Navigator.pop(ctx, controller.text.trim()),
                              child: const Text('Save'),
                            ),
                          ],
                        ),
                      );
                      if (updated != null) {
                        await DedicationStore.set(updated);
                        if (context.mounted) setState(() {});
                      }
                    },
                    icon: const Icon(Icons.edit, size: 18),
                    label: const Text('Edit'),
                  ),
                ],
              ),
            );
          },
        ),
        const SizedBox(height: 16),
        SizedBox(
          height: 48,
          child: FilledButton.icon(
            onPressed: _shareBusy
                ? null
                : () async {
                    setState(() => _shareBusy = true);
                    try {
                      final counter = await CounterStore.create();
                      final int todayJaps = counter.todayJaps;
                      final int lifetimeMalasLocal = counter.lifetimeMalas;
                      final int streakDays = await ActivityStore.currentStreak();
                      debugPrint('[Stats] Share tapped → todayJaps=$todayJaps lifetimeMalas=$lifetimeMalasLocal streakDays=$streakDays');
                      await openShareMyStreak(
                        context,
                        todayJaps: todayJaps,
                        lifetimeMalas: lifetimeMalasLocal,
                        streakDays: streakDays,
                      );
                    } finally {
                      if (context.mounted) setState(() => _shareBusy = false);
                    }
                  },
            onLongPress: () async {
              final counter = await CounterStore.create();
              final int todayJaps = counter.todayJaps;
              final int lifetimeMalasLocal = counter.lifetimeMalas;
              final int streakDays = await ActivityStore.currentStreak();
              debugPrint('[Stats][DEV] Long-press bypass → opening preview directly');
              if (!context.mounted) return;
              await Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => StreakSharePreviewPage(
                    todayJaps: todayJaps,
                    lifetimeMalas: lifetimeMalasLocal,
                    streakDays: streakDays,
                  ),
                ),
              );
            },
            icon: const Icon(Icons.ios_share),
            label: Text(
              _shareBusy
                  ? 'Preparing…'
                  : (cooling ? 'Wait ${remLabel ?? ''}' : 'Share My Streak'),
            ),
          ),
        ),
        const SizedBox(height: 24),
        FutureBuilder<int>(
          future: ActivityStore.totalActiveDays(),
          builder: (context, snap) {
            final count = snap.data ?? 0;
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                'Days Active: $count',
                style: Theme.of(context).textTheme.bodyLarge,
              ),
            );
          },
        ),
        Text('Calendar', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 6),
        const _CalendarHeader(),
        const SizedBox(height: 6),
        const _WeekdayRow(),
        const SizedBox(height: 6),
        const _ActivityCalendar(days: 35),
      ],
    );
  }
}

class _ActivityCalendar extends StatefulWidget {
  final int days; // how many days to show (e.g., 35 = 5 rows x 7 cols)
  const _ActivityCalendar({this.days = 35});

  @override
  State<_ActivityCalendar> createState() => _ActivityCalendarState();
}

class _ActivityCalendarState extends State<_ActivityCalendar> {
  Map<String, bool>? _recent; // yyyy-MM-dd -> active?
  Set<String>? _streak;       // dates that are part of the current streak

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final data = await ActivityStore.recentDays(days: widget.days);
    final streakLen = await ActivityStore.currentStreak();

    // Build a set of ISO dates for the last [streakLen] days (today inclusive)
    final now = DateTime.now();
    final streakDates = <String>{};
    for (int i = 0; i < streakLen; i++) {
      final d = DateTime(now.year, now.month, now.day).subtract(Duration(days: i));
      final y = d.year.toString().padLeft(4, '0');
      final m = d.month.toString().padLeft(2, '0');
      final dd = d.day.toString().padLeft(2, '0');
      streakDates.add('$y-$m-$dd');
    }

    if (!mounted) return;
    setState(() {
      _recent = data;
      _streak = streakDates;
    });
  }

  @override
  Widget build(BuildContext context) {
    final recent = _recent;
    if (recent == null) {
      return const SizedBox(height: 120, child: Center(child: CircularProgressIndicator()));
    }

    // Oldest -> newest so the latest day appears at the end.
    final keys = recent.keys.toList().reversed.toList();
    final values = keys.map((k) => recent[k] ?? false).toList();
    final streak = _streak ?? const <String>{};

    const cols = 7;
    final rows = (values.length / cols).ceil();

    return AspectRatio(
      aspectRatio: cols / rows,
      child: GridView.builder(
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: cols,
          mainAxisSpacing: 6,
          crossAxisSpacing: 6,
        ),
        itemCount: rows * cols,
        itemBuilder: (context, i) {
          final active = i < values.length ? values[i] : false;
          final key = i < keys.length ? keys[i] : null;
          final isStreak = key != null && streak.contains(key);

          // Active days are filled; streak days get a stronger fill + thicker border.
          final base = Theme.of(context).colorScheme.primary;
          final fill = active
              ? (isStreak ? base.withValues(alpha: 0.95) : base.withValues(alpha: 0.65))
              : Colors.transparent;
          final borderColor = isStreak
              ? base.withValues(alpha: 0.9)
              : Theme.of(context).dividerColor;
          final borderWidth = isStreak ? 2.0 : 1.0;

          return Container(
            decoration: BoxDecoration(
              color: fill,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: borderColor, width: borderWidth),
            ),
          );
        },
      ),
    );
  }
}
class _CalendarHeader extends StatelessWidget {
  const _CalendarHeader();

  static const _months = [
    'January','February','March','April','May','June',
    'July','August','September','October','November','December'
  ];

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final label = '${_months[now.month - 1]} ${now.year}';
    return Text(label, style: Theme.of(context).textTheme.titleSmall);
  }
}

class _WeekdayRow extends StatelessWidget {
  const _WeekdayRow();

  @override
  Widget build(BuildContext context) {
    const days = ['S','M','T','W','T','F','S'];
    final style = Theme.of(context).textTheme.labelMedium;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: days.map((d) => Expanded(
        child: Center(child: Text(d, style: style)),
      )).toList(),
    );
  }
}
class _ContentPage extends StatelessWidget {
  const _ContentPage();

  @override
  Widget build(BuildContext context) {
    return const ContentPage(); // uses the new tabs screen
  }
}




// Legacy settings classes removed. Latest settings UI lives in lib/settings/settings_page.dart