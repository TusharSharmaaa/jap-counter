import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'stats/streak_share_preview.dart';
import 'ads/rewarded.dart';
import 'content/content_page.dart';
import 'timer/timer_page.dart';
import 'data/meditation_store.dart';

import 'ads/test_banner.dart';
import 'data/counter_store.dart';


class App extends StatefulWidget {
  const App({super.key});
  @override
  State<App> createState() => _AppState();
}

class _AppState extends State<App> {
  int _index = 0;

  final _pages = const [
    _CounterPage(),
    _StatsPage(),
    _ContentPage(),
    TimerPage(),
    _SettingsPage(),
  ];

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Radha Jap Counter',
      home: Scaffold(
        body: _pages[_index],
        bottomNavigationBar: NavigationBar(
          selectedIndex: _index,
          onDestinationSelected: (i) => setState(() => _index = i),
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

  Future<void> _inc() async {
    final s = _store;
    if (s == null) return;

    final willBe = _today + 1; // value after this tap

    await s.increment();

    if (!mounted) return;

    // Light tap feedback every press
    HapticFeedback.selectionClick();

    // Stronger feedback + toast on completing a mala (108, 216, 324, ...)
    if (willBe % 108 == 0) {
      HapticFeedback.mediumImpact();
      // Trigger pulse animation
      setState(() => _pulse = true);
      Future.delayed(const Duration(milliseconds: 250), () {
        if (mounted) setState(() => _pulse = false);
      });

      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('🎯 Mala completed!'),
            duration: Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
          ),
        );
    }

    setState(() {
      _today = s.todayJaps;
      _lifetime = s.lifetimeJaps;
    });
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
                    border: Border.all(color: Theme.of(context).colorScheme.primary.withOpacity(0.25)),
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
  const _StatsPage();

  @override
  State<_StatsPage> createState() => _StatsPageState();
}

class _StatsPageState extends State<_StatsPage> {
  final RewardedGate _gate = RewardedGate();

  CounterStore? _store;
  bool _loading = true;
  int _today = 0;
  int _lifetime = 0;
  int _todayMin = 0;
  int _lifetimeMin = 0;

  @override
  void initState() {
    super.initState();
    _init();

    // Warm up the rewarded ad in the background
    // ignore: unawaited_futures
    _gate.load();
  }

  Future<void> _refresh() async {
    final s = await CounterStore.create();
    final mstore = await MeditationStore.create();

    if (!mounted) return;
    setState(() {
      _store = s;
      _today = s.todayJaps;
      _lifetime = s.lifetimeJaps;

      _todayMin = mstore.todayMinutes;
      _lifetimeMin = mstore.lifetimeMinutes;
    });
  }

  Future<void> _init() async {
    final s = await CounterStore.create(); // uses same prefs + new-day reset

    // NEW: meditation store
    final mstore = await MeditationStore.create();

    setState(() {
      _store = s;
      _today = s.todayJaps;
      _lifetime = s.lifetimeJaps;
      _loading = false;

      // NEW:
      _todayMin = mstore.todayMinutes;
      _lifetimeMin = mstore.lifetimeMinutes;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Stats')),
        body: const Center(child: CircularProgressIndicator()),
        bottomNavigationBar: const _BannerReserve(), // keep reserved for now
      );
    }

    final todayMalas = _today ~/ 108;
    final lifetimeMalas = _lifetime ~/ 108;

    return Scaffold(
      appBar: AppBar(title: const Text('Stats')),
        body: RefreshIndicator(
          onRefresh: _refresh,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [

              // Top tiles
          Row(
            children: [
              Expanded(child: _StatTile(title: "Today's Japs", value: _today.toString())),
              const SizedBox(width: 8),
              Expanded(child: _StatTile(title: "Today's Malas", value: todayMalas.toString())),
              const SizedBox(width: 8),
              Expanded(child: _StatTile(title: "Lifetime Malas", value: lifetimeMalas.toString())),
            ],
          ),

          const SizedBox(height: 16),

          // Meditation minutes tiles
          Row(
            children: [
              Expanded(child: _StatTile(title: "Today's Meditation (min)", value: _todayMin.toString())),
              const SizedBox(width: 8),
              Expanded(child: _StatTile(title: "Lifetime Meditation (min)", value: _lifetimeMin.toString())),
            ],
          ),

          const SizedBox(height: 16),


          // Dedication note placeholder (read-only for now)
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Theme.of(context).dividerColor),
            ),
            child: Text(
              "Dedication: (coming soon)",
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),

          const SizedBox(height: 16),

          // Share My Streak (no rewarded, no image yet)
          SizedBox(
            height: 48,
            child: FilledButton.icon(
              onPressed: () async {
                final todayMalas = _today ~/ 108;
                final lifetimeMalas = _lifetime ~/ 108;

                // Tiny loading dialog while we try to load the ad
                showDialog(
                  context: context,
                  barrierDismissible: false,
                  builder: (_) => const Center(child: CircularProgressIndicator()),
                );

                // Try to load within 4 seconds
                final loaded = await _gate.load(timeout: const Duration(seconds: 4));

                if (mounted) Navigator.of(context).pop(); // close loader

                // If loaded, try to show; if not, we just skip gracefully
                if (loaded) {
                  await _gate.showIfReady();
                }

                if (!mounted) return;
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => StreakSharePreviewPage(
                      todayJaps: _today,
                      lifetimeMalas: lifetimeMalas,
                      streakDays: 0, // placeholder; real streak calc coming soon
                    ),
                  ),
                );
              },
              icon: const Icon(Icons.ios_share),
              label: const Text("Share My Streak"),
            )


          ),

          const SizedBox(height: 24),

          // Calendar stub block (we'll wire real data/colors later)
          Text("Calendar", style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          const _CalendarStub(),
        ],
      ),
        ),
      bottomNavigationBar: const _BannerReserve(), // reserved; no real ad here yet
    );
  }
}

class _CalendarStub extends StatelessWidget {
  const _CalendarStub();

  @override
  Widget build(BuildContext context) {
    // Simple 7x5 grid placeholder (no real dates/colors yet)
    const rows = 5;
    const cols = 7;
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
          return Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Theme.of(context).dividerColor),
            ),
          );
        },
      ),
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




class _SettingsPage extends StatelessWidget {
  const _SettingsPage();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: const Center(child: Text('Settings UI stub')),
      bottomNavigationBar: const _BannerReserve(),
    );
  }
}
