import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';

import 'stats/streak_share_preview.dart';
import 'ads/rewarded.dart';
import 'content/content_page.dart';
import 'timer/timer_page.dart';
import 'data/meditation_store.dart';
import 'ads/rewarded_share.dart';
import 'stats/share_gate.dart';
import 'stats/dedication_store.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'notifications/notification_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'legal/privacy_policy.dart';
import 'legal/terms_conditions.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:share_plus/share_plus.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'data/activity_store.dart';
import 'ads/test_banner.dart';
import 'data/counter_store.dart';


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
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Ensure a rewarded ad is queued when user comes back to the app
      RewardedShareAd().ensureWarm();
    }
  }
  int _index = 0;
  // Theme state (will be wired to Settings toggle next)
  ThemeMode _themeMode = ThemeMode.light;
  static const _themeKey = 'themeMode';


  // Minimal Material 3 themes
  final ThemeData _lightTheme = ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    colorSchemeSeed: const Color(0xFFFF6F00), // saffron accent vibe
  );

  final ThemeData _darkTheme = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorSchemeSeed: const Color(0xFF6A1B9A), // plum/gold vibe base
  );


  final _pages = const [
    _CounterPage(),
    _StatsPage(),
    _ContentPage(),
    TimerPage(),
    _SettingsPage(),
  ];

  Future<void> _loadThemeMode() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_themeKey);
    if (saved == 'dark') {
      setState(() => _themeMode = ThemeMode.dark);
    } else if (saved == 'light') {
      setState(() => _themeMode = ThemeMode.light);
    } else {
      setState(() => _themeMode = ThemeMode.light);
    }
  }

  Future<void> _saveThemeMode(ThemeMode mode) async {
    final prefs = await SharedPreferences.getInstance();
    final value = mode == ThemeMode.dark ? 'dark' : 'light';
    await prefs.setString(_themeKey, value);
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
      theme: _lightTheme,
      darkTheme: _darkTheme,
      themeMode: _themeMode,
      home: Scaffold(
        body: _index == 4
            ? SettingsPage(
          themeMode: _themeMode,
          onThemeModeChanged: (mode) {
            setState(() => _themeMode = mode);
            _saveThemeMode(mode);
          },        )
            : _pages[_index],
        bottomNavigationBar: NavigationBar(
          selectedIndex: _index,
          onDestinationSelected: (i) {
            // If user navigates to Stats tab, preload rewarded ad
            if (i == 1) { // 0=Counter, 1=Stats, 2=Content, 3=Timer, 4=Settings
              RewardedShareAd().preload();

              // DEV ONLY: print remaining cooldown to console for quick checks
              if (kDebugMode) {
                final rem = RewardedShareAd().cooldownRemaining;
                if (rem != null && rem > Duration.zero) {
                  debugPrint('[RewardedShareAd] Cooldown remaining: ${rem.inMinutes}m ${rem.inSeconds % 60}s');
                } else {
                  debugPrint('[RewardedShareAd] No cooldown active.');
                }
              }
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

  Future<void> _inc() async {
    final s = _store;
    if (s == null) return;

    final wasZero = _today == 0;            // track 0 → 1 transition
    final willBe = _today + 1; // value after this tap
    await s.increment();
// If this was the first jap of the day, mark today as active
    if (wasZero) {
      await ActivityStore.markTodayActive();
    }
    // If first jap today, check for streak milestones
    if (wasZero) {
      final streak = await ActivityStore.currentStreak();
      if (mounted && (streak == 7 || streak == 21 || streak == 40)) {
        HapticFeedback.mediumImpact();
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
  bool _shareBusy = false;

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
    // Also ensure today is marked active on manual refresh
    if (s.todayJaps > 0) {
      await ActivityStore.markTodayActive();
    }
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
    // Ensure today is recorded as active if user already has japs today
    if (s.todayJaps > 0) {
      await ActivityStore.markTodayActive();
    }

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
    final cooling = RewardedShareAd().isCoolingDown;
    final rem = RewardedShareAd().cooldownRemaining;
    final remLabel = (rem != null && rem > Duration.zero)
        ? (rem.inMinutes > 0 ? '${rem.inMinutes}m ${rem.inSeconds % 60}s' : '${rem.inSeconds % 60}s')
        : null;

    return Scaffold(
      appBar: AppBar(title: const Text('Stats')),
        body: RefreshIndicator(
          onRefresh: _refresh,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
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
                            style: Theme.of(context)
                                .textTheme
                                .labelLarge
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),

              const SizedBox(height: 16),

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
                        note.isEmpty
                            ? 'Dedication: (tap edit to add)'
                            : 'Dedication: $note',
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

          // Share My Streak (no rewarded, no image yet)
          SizedBox(
            height: 48,
            child: FilledButton.icon(
              onPressed: _shareBusy ? null : () async {
                setState(() => _shareBusy = true);
                try {
                  // Fresh numbers at tap time
                  final counter = await CounterStore.create();
                  final int todayJaps = counter.todayJaps;
                  final int lifetimeMalas = counter.lifetimeMalas;
                  final int streakDays = await ActivityStore.currentStreak();
                  debugPrint('[Stats] Share tapped → todayJaps=$todayJaps lifetimeMalas=$lifetimeMalas streakDays=$streakDays');
                  await openShareMyStreak(
                    context,
                    todayJaps: todayJaps,
                    lifetimeMalas: lifetimeMalas,
                    streakDays: streakDays,
                  );
                } finally {
                  if (mounted) setState(() => _shareBusy = false);
                }
              },
              onLongPress: () async {
                // DEV BYPASS: open preview without ad for debugging UI quickly
                final counter = await CounterStore.create();
                final int todayJaps = counter.todayJaps;
                final int lifetimeMalas = counter.lifetimeMalas;
                final int streakDays = await ActivityStore.currentStreak();
                debugPrint('[Stats][DEV] Long-press bypass → opening preview directly');
                if (!context.mounted) return;
                await Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => StreakSharePreviewPage(
                      todayJaps: todayJaps,
                      lifetimeMalas: lifetimeMalas,
                      streakDays: streakDays,
                    ),
                  ),
                );
              },

              icon: const Icon(Icons.ios_share),
              label: Text(
                _shareBusy
                    ? "Preparing…"
                    : (cooling ? "Wait ${remLabel ?? ''}" : "Share My Streak"),
              ),            )


          ),

          const SizedBox(height: 24),
// Days active count
              FutureBuilder<int>(
                future: ActivityStore.totalActiveDays(),
                builder: (context, snap) {
                  final count = snap.data ?? 0;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      "Days Active: $count",
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                  );
                },
              ),

              FutureBuilder<int>(
                future: ActivityStore.currentStreak(),
                builder: (context, snap) {
                  final streak = snap.data ?? 0;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      streak > 0
                          ? "🔥 Current Streak: $streak day${streak == 1 ? '' : 's'}"
                          : "No active streak yet",
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                  );
                },
              ),

              // Calendar stub block (we'll wire real data/colors later)
// Calendar (last 35 days; colored when active)
              Text("Calendar", style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 6),
              const _CalendarHeader(),
              const SizedBox(height: 6),
              const _WeekdayRow(),
              const SizedBox(height: 6),
              const _ActivityCalendar(days: 35),
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
class _NotificationsToggle extends StatefulWidget {
  const _NotificationsToggle();

  @override
  State<_NotificationsToggle> createState() => _NotificationsToggleState();
}

class _NotificationsToggleState extends State<_NotificationsToggle> {
  bool _enabled = true;
  static const _key = 'notificationsEnabled';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() => _enabled = prefs.getBool(_key) ?? true);
  }

  Future<void> _toggle(bool value) async {
    setState(() => _enabled = value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key, value);

    final ns = NotificationService();
    if (value) {
      await ns.init();
      final allowed = await ns.requestPermission();
      if (allowed) await ns.scheduleDefaults();
    } else {
      // Cancel all scheduled notifications
      final plugin = FlutterLocalNotificationsPlugin();
      await plugin.cancelAll();
    }
  }

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      title: const Text('Daily Reminders'),
      subtitle: const Text('7 AM, 12 PM, and 6 PM devotional alerts'),
      value: _enabled,
      onChanged: _toggle,
    );
  }
}
class _AboutFooter extends StatelessWidget {
  const _AboutFooter();

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodySmall;
    return FutureBuilder<PackageInfo>(
      future: PackageInfo.fromPlatform(),
      builder: (context, snap) {
        final ver = snap.data?.version ?? '';
        final build = snap.data?.buildNumber ?? '';
        final versionLabel = ver.isEmpty ? '' : ' • v$ver+$build';
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Column(
            children: [
              Text('Radha Jap Counter$versionLabel', style: style),
              const SizedBox(height: 4),
              Text('Made with devotion in India', style: style),
            ],
          ),
        );
      },
    );
  }
}
class SettingsPage extends StatelessWidget {
  final ThemeMode themeMode;
  final ValueChanged<ThemeMode> onThemeModeChanged;

  const SettingsPage({
    super.key,
    required this.themeMode,
    required this.onThemeModeChanged,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = themeMode == ThemeMode.dark;

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Appearance section
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 8),
            child: Text('Appearance', style: Theme.of(context).textTheme.labelLarge),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.dark_mode),
            title: const Text('Dark Mode'),
            subtitle: const Text('Use plum & gold theme'),
            value: isDark,
            onChanged: (v) {
              onThemeModeChanged(v ? ThemeMode.dark : ThemeMode.light);
            },
          ),
          const SizedBox(height: 8),
          const Divider(height: 1),

          const SizedBox(height: 16),

          // Reminders section
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 8),
            child: Text('Reminders', style: Theme.of(context).textTheme.labelLarge),
          ),
          _NotificationsToggle(), // toggle already handles scheduling/cancel
          const SizedBox(height: 8),
          const Divider(height: 1),

          const SizedBox(height: 16),

          // About section
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 8),
            child: Text('About', style: Theme.of(context).textTheme.labelLarge),
          ),
          ListTile(
            leading: const Icon(Icons.privacy_tip),
            title: const Text('Privacy Policy'),
            subtitle: const Text('Read our privacy policy'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const PrivacyPolicyPage()),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.gavel),
            title: const Text('Terms & Conditions'),
            subtitle: const Text('View app terms'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const TermsConditionsPage()),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.star_rate),
            title: const Text('Rate on Play Store'),
            subtitle: const Text('“Your one rating will take you towards sadhna”'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () async {
              const pkg = 'com.example.jap_counter'; // current applicationId
              final marketUri = Uri.parse('market://details?id=$pkg');
              final webUri = Uri.parse('https://play.google.com/store/apps/details?id=$pkg');

              if (await canLaunchUrl(marketUri)) {
                await launchUrl(marketUri);
              } else {
                await launchUrl(webUri, mode: LaunchMode.externalApplication);
              }
            },
          ),
          const SizedBox(height: 24),
          const _AboutFooter(),

          ListTile(
            leading: const Icon(Icons.share),
            title: const Text('Share App'),
            subtitle: const Text('“साधना में साथ—दोस्तों को भेजें”'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () async {
              const pkg = 'com.example.jap_counter';
              final link = 'https://play.google.com/store/apps/details?id=$pkg';
              await Share.share('मैं Radha Jap Counter ऐप इस्तेमाल कर रहा/रही हूँ — $link');
            },
          ),
        ],
      ),     bottomNavigationBar: const _BannerReserve(),
    );
  }
}