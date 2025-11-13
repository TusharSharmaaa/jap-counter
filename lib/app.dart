import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:confetti/confetti.dart';
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:provider/provider.dart';
import 'stats/streak_share_preview.dart';
import 'stats/streak_badge.dart';
import 'core/ad_manager.dart';
import 'content/gita_page.dart';
import 'timer/timer_page.dart';
import 'data/meditation_store.dart';
import 'data/dedication_store.dart';
import 'stats/share_gate.dart';
import 'stats/stats_ambience.dart';
import 'settings/settings_page.dart';
import 'notifications/notification_service.dart';
import 'core/prefs_manager.dart';
import 'data/activity_store.dart';
import 'data/counter_store.dart';
import 'data/goal_store.dart';
import 'theme/neumorph.dart';
import 'gamify/gamify_store.dart';
import 'theme/theme.dart';
import 'data/language_store.dart';
import 'l10n/app_localizations.dart';
import 'sync/sync_service.dart';
import 'utils/weekly_chart_data.dart';
import 'counter/counter_page.dart';
import 'timer/timer_service.dart';
import 'core/sound_manager.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

class App extends StatefulWidget {
  const App({super.key});
  @override
  State<App> createState() => _AppState();
}

class _AppState extends State<App> with WidgetsBindingObserver {
  late final TimerService _timerService;

  @override
  void initState() {
    super.initState();
    // Observe app lifecycle to keep the ad warmed up on resume
    WidgetsBinding.instance.addObserver(this);
    _timerService = TimerService();
    unawaited(_timerService.load());

    _loadThemeMode();
    _loadLanguage();
    _initNotifications(); // fire-and-forget
    unawaited(_showWelcomeSnackbar());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      unawaited(SyncService.syncToday());
    } else if (state == AppLifecycleState.detached) {
      // App is being closed - mark it so timer resets on next open
      unawaited(_timerService.markAppClosed());
    } else if (state == AppLifecycleState.resumed) {
      unawaited(_timerService.load());
    }
  }

  int _index = 0;
  final GlobalKey<_StatsPageState> _statsKey = GlobalKey<_StatsPageState>();
  ThemeMode _themeMode = ThemeMode.system;
  String _language = 'en';

  late final List<Widget> _pages = [
    const CounterPage(),
    _StatsPage(key: _statsKey),
    const _GitaTab(),
    TimerPage(),
  ];

  Future<void> _loadThemeMode() async {
    final prefs = await PrefsManager.instance;
    final stored = prefs.getInt('themeMode') ?? ThemeMode.system.index;
    final values = ThemeMode.values;
    final mode = (stored >= 0 && stored < values.length)
        ? values[stored]
        : ThemeMode.system;
    if (mounted) {
      setState(() => _themeMode = mode);
    } else {
      _themeMode = mode;
    }
  }

  Future<void> _loadLanguage() async {
    final lang = await LanguageStore.current();
    if (mounted) {
      setState(() => _language = lang);
    } else {
      _language = lang;
    }
  }

  Future<void> _setLanguage(String language) async {
    if (language == _language) return;
    await LanguageStore.save(language);
    if (!mounted) return;
    await initializeDateFormatting(language == 'hi' ? 'hi' : 'en');
    setState(() => _language = language);
  }

  String _translate(String key, {Map<String, String>? args}) {
    var value = AppStrings.resolve(_language, key);
    if (args != null) {
      args.forEach((k, v) {
        value = value.replaceAll('{$k}', v);
      });
    }
    return value;
  }

  Future<void> _saveThemeMode(ThemeMode mode) async {
    final prefs = await PrefsManager.instance;
    await prefs.setInt('themeMode', mode.index);
  }

  Future<void> _initNotifications() async {
    final ns = NotificationService();
    await ns.init();
    final allowed = await ns.requestPermission();
    if (allowed) {
      final language = await LanguageStore.current();
      await ns.scheduleDefaults(language: language);
    } else {
      // Optional: You can show a SnackBar later if you add a UI toggle.
    }
  }

  Future<void> _showWelcomeSnackbar() async {
    // Show loading state immediately
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_translate('home.snackbar.loading')),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
    }
    // Load data in background
    unawaited(_loadWelcomeData());
  }

  Future<void> _loadWelcomeData() async {
    await Future.delayed(const Duration(milliseconds: 500));
    if (!mounted) return;
    final counter = await CounterStore.create();
    final today = counter.todayJaps ~/ 108;
    await initializeDateFormatting(_language == 'hi' ? 'hi' : 'en');
    if (!mounted) return;
    final msg = today > 0
        ? _translate('home.snackbar.progress', args: {'count': '$today'})
        : _translate('home.snackbar.start');
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger
      ?..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(msg),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 3),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<TimerService>.value(
      value: _timerService,
      child: MaterialApp(
        title: 'Naam Jap Counter : Sadhna',
        theme: buildTheme(Brightness.light),
        darkTheme: buildTheme(Brightness.dark),
        themeMode: _themeMode,
        builder: (context, child) => AppLocalizationScope(
          language: _language,
          child: child ?? const SizedBox.shrink(),
        ),
        home: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Theme.of(context).colorScheme.surface.withOpacity(0.95),
                Theme.of(context).colorScheme.primary.withOpacity(0.05),
              ],
            ),
          ),
          child: Scaffold(
            backgroundColor: Colors.transparent,
            body: IndexedStack(
              index: _index,
              children: [
                _pages[0], // CounterPage
                _pages[1], // StatsPage
                _pages[2], // GitaTab
                _pages[3], // TimerPage
                SettingsPage(
                  key: const ValueKey('settings'),
                  themeMode: _themeMode,
                  language: _language,
                  onThemeModeChanged: (mode) {
                    setState(() => _themeMode = mode);
                    _saveThemeMode(mode);
                  },
                  onLanguageChanged: _setLanguage,
                ),
              ],
            ),
            bottomNavigationBar: SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Container(
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surface,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.1),
                        offset: const Offset(2, 2),
                        blurRadius: 6,
                      ),
                      BoxShadow(
                        color: Colors.white.withValues(alpha: 0.8),
                        offset: const Offset(-2, -2),
                        blurRadius: 6,
                      ),
                    ],
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _navIcon(Icons.touch_app, 0, 'nav.counter'),
                      _navIcon(Icons.bar_chart, 1, 'nav.stats'),
                      _navIcon(Icons.menu_book, 2, 'nav.gita'),
                      _navIcon(Icons.timer, 3, 'nav.timer'),
                      _navIcon(Icons.settings, 4, 'nav.settings'),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        debugShowCheckedModeBanner: false,
      ),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timerService.dispose();
    // Dispose StatsAmbience singleton
    unawaited(StatsAmbience.instance.dispose());
    super.dispose();
  }

  Widget _navIcon(IconData icon, int idx, String labelKey) {
    final active = _index == idx;
    final theme = Theme.of(context);
    final color = active
        ? theme.colorScheme.primary
        : theme.colorScheme.onSurfaceVariant;
    return Expanded(
      child: GestureDetector(
        onTap: () => _handleNavTap(idx),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
          decoration: BoxDecoration(
            color: active
                ? theme.colorScheme.primary.withValues(alpha: 0.15)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            boxShadow: active
                ? [
                    BoxShadow(
                      color: theme.colorScheme.primary.withValues(alpha: 0.3),
                      blurRadius: 10,
                    ),
                  ]
                : const [],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: color, size: 22),
              const SizedBox(height: 2),
              Flexible(
                child: Text(
                  _translate(labelKey),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: color,
                    fontWeight: active ? FontWeight.w600 : null,
                    fontSize: 10,
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _handleNavTap(int index) {
    if (_index == index) return;
    final leavingTimer = _index == 3 && index != 3;
    if (leavingTimer) {
      unawaited(_pauseTimerForNav());
    }
    if (index == 1) {
      _statsKey.currentState?.onBecameVisible();
    } else if (_index == 1) {
      _statsKey.currentState?.onBecameHidden();
    }
    if (index == 2) {
      AdManager.instance.recordEvent('gita.session', 'start');
    }
    if (_index == 2 && index != 2) {
      unawaited(
        AdManager.instance.maybeShowInterstitial(
          'gita.long_session_interstitial',
        ),
      );
      AdManager.instance.recordEvent('gita.session', 'end');
    }
    setState(() => _index = index);
  }

  Future<void> _pauseTimerForNav() async {
    if (!_timerService.running) return;
    try {
      await _timerService.pause();
    } catch (_) {
      // ignore pause errors
    }
    try {
      await SoundManager.instance.pauseAmbience();
    } catch (_) {
      // ignore audio errors
    }
    try {
      await WakelockPlus.disable();
    } catch (_) {
      // ignore wakelock errors
    }
  }
}

class _StatsPage extends StatefulWidget {
  const _StatsPage({super.key});

  @override
  State<_StatsPage> createState() => _StatsPageState();
}

class _StatsPageState extends State<_StatsPage> with AutomaticKeepAliveClientMixin {
  bool _shareBusy = false;
  late ConfettiController _confetti;

  CounterStore? _store;
  bool _loading = true;
  int _today = 0;
  int _lifetime = 0;
  int _todayMin = 0;
  int _lifetimeMin = 0;
  // NEW: user's dedication text (persisted via DedicationStore)
  String _dedication = '';
  static const _ambienceKey = 'stats.ambience.enabled';
  bool _ambienceEnabled = false;

  // Load all stats in one batch to avoid multiple FutureBuilders
  Future<Map<String, dynamic>>? _allStatsFuture;

  @override
  bool get wantKeepAlive => true; // Preserve state when hidden

  @override
  void initState() {
    super.initState();
    _confetti = ConfettiController(duration: const Duration(seconds: 3));
    _init();
    unawaited(AdManager.instance.preloadPlacement('stats.share_rewarded'));

    _loadAmbiencePref();
    
    // Load all stats once in parallel
    _allStatsFuture = _loadAllStats();
  }
  
  /// Load all stats data in parallel for better performance
  Future<Map<String, dynamic>> _loadAllStats({String? locale}) async {
    final chartLocale = locale ?? 'en';
    final results = await Future.wait([
      // Counter stats - includes lifetime malas calculated from completed malas in history
      CounterStore.create().then((s) => {
        'today': s.todayJaps,
        'lifetime': s.lifetimeJaps,
        'todayMalas': s.todayMalas,
        'lifetimeMalas': s.lifetimeMalas, // This is calculated from completed malas in history
      }),
      // Activity stats
      Future.wait([
        ActivityStore.currentStreak(),
        ActivityStore.totalActiveDays(),
      ]).then((values) => {
        'streak': values[0],
        'activeDays': values[1],
      }),
      // Goal
      GoalStore.create().then((gs) => gs.dailyMalasGoal),
      // Badges
      GamifyStore.badges(),
      // Dedication
      DedicationStore.create().then((s) => s.note),
      // Chart data
      WeeklyChartData.build(locale: chartLocale),
    ]);
    
    return {
      'counter': results[0] as Map<String, int>,
      'activity': results[1] as Map<String, int>,
      'goal': results[2] as int,
      'badges': results[3] as Set<String>,
      'dedication': results[4] as String,
      'chart': results[5] as List<Map<String, dynamic>>,
    };
  }
  
  @override
  void dispose() {
    _confetti.dispose();
    StatsAmbience.instance.stop();
    super.dispose();
  }

  Future<void> _loadAmbiencePref() async {
    final p = await PrefsManager.instance;
    if (!mounted) return;
    setState(() => _ambienceEnabled = p.getBool(_ambienceKey) ?? false);
  }

  Future<void> _saveAmbiencePref(bool v) async {
    final p = await PrefsManager.instance;
    await p.setBool(_ambienceKey, v);
  }

  void onBecameVisible() {
    if (_ambienceEnabled) {
      StatsAmbience.instance.start();
    }
    // Refresh stats data when page becomes visible to show real-time updates
    unawaited(_refreshStatsData());
  }
  
  /// Refresh stats data without full refresh animation (called on visibility)
  Future<void> _refreshStatsData() async {
    // Record current daily summary to ensure stats are up to date
    final s = await CounterStore.create();
    await ActivityStore.recordDailySummary(s.todayJaps, s.todayJaps ~/ 108);
    
    if (!mounted) return;
    
    // Invalidate chart cache to ensure fresh data
    WeeklyChartData.invalidateCache();
    
    // Reload all stats with correct locale
    final language = AppLocalizationScope.of(context).language;
    final locale = language == 'hi' ? 'hi' : 'en';
    _allStatsFuture = _loadAllStats(locale: locale);
    
    // Update local state with latest counter data
    setState(() {
      _today = s.todayJaps;
      _lifetime = s.lifetimeJaps;
    });
    
    // Ensure today is marked active if user has japs today
    if (s.todayJaps > 0) {
      await ActivityStore.markTodayActive();
    }
  }

  void onBecameHidden() {
    StatsAmbience.instance.stop();
  }

  Future<void> _refresh() async {
    final s = await CounterStore.create();
    final mstore = await MeditationStore.create();
    final dstore = await DedicationStore.create();
    await ActivityStore.recordDailySummary(s.todayJaps, s.todayJaps ~/ 108);

    if (!mounted) return;
    
    // Invalidate chart cache before refreshing
    WeeklyChartData.invalidateCache();
    
    // Reload all stats in one batch with correct locale
    final language = AppLocalizationScope.of(context).language;
    final locale = language == 'hi' ? 'hi' : 'en';
    _allStatsFuture = _loadAllStats(locale: locale);
    
    setState(() {
      _today = s.todayJaps;
      _lifetime = s.lifetimeJaps;

      _todayMin = mstore.todayMinutes;
      _lifetimeMin = mstore.lifetimeMinutes;
      _dedication = dstore.note;
    });
    // Also ensure today is marked active on manual refresh
    if (s.todayJaps > 0) {
      await ActivityStore.markTodayActive();
    }

    // Reload stats and check for milestone streaks
    final reloadedStats = await _allStatsFuture;
    if (reloadedStats != null) {
      final activity = reloadedStats['activity'] as Map<String, int>;
      final streak = activity['streak'] ?? 0;
      if ([7, 21, 40].contains(streak)) {
        _confetti.play();
      }
    }
  }

  Future<void> _init() async {
    final s = await CounterStore.create(); // uses same prefs + new-day reset
    final mstore = await MeditationStore.create();
    final dstore = await DedicationStore.create();
    await ActivityStore.recordDailySummary(s.todayJaps, s.todayJaps ~/ 108);
    setState(() {
      _today = s.todayJaps;
      _lifetime = s.lifetimeJaps;
      _loading = false;

      _todayMin = mstore.todayMinutes;
      _lifetimeMin = mstore.lifetimeMinutes;
      _dedication = dstore.note;
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
    super.build(context); // Required for AutomaticKeepAliveClientMixin
    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: Text(context.tr('stats.title'))),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final todayMalas = _today ~/ 108;
    final lifetimeMalas = _lifetime ~/ 108;
    // Load goal (synchronously via FutureBuilder below to avoid blocking build)

    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr('stats.title')),
        backgroundColor: Colors.transparent,
        elevation: 0,
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                Theme.of(context).colorScheme.primary.withOpacity(0.3),
                Colors.transparent,
              ],
            ),
          ),
        ),
        actions: [
          IconButton(
            tooltip: _ambienceEnabled
                ? context.tr('stats.ambience.on')
                : context.tr('stats.ambience.off'),
            icon: Icon(
              _ambienceEnabled ? Icons.spatial_audio_off : Icons.spatial_audio,
            ),
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
            child: _buildStatsList(context, todayMalas, lifetimeMalas),
          ),
          Align(
            alignment: Alignment.topCenter,
            child: ConfettiWidget(
              confettiController: _confetti,
              blastDirectionality: BlastDirectionality.explosive,
              emissionFrequency: 0.05,
              numberOfParticles: 20,
              colors: const [
                Colors.orange,
                Colors.yellow,
                Colors.pink,
                Colors.white,
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatsList(
    BuildContext context,
    int todayMalas,
    int lifetimeMalas,
  ) {
    // Use CustomScrollView for better performance
    return FutureBuilder<Map<String, dynamic>>(
      future: _allStatsFuture,
      builder: (context, statsSnapshot) {
        if (!statsSnapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        
        final stats = statsSnapshot.data!;
        final counter = stats['counter'] as Map<String, int>;
        final activity = stats['activity'] as Map<String, int>;
        final goal = stats['goal'] as int;
        final badges = stats['badges'] as Set<String>;
        final dedication = stats['dedication'] as String;
        final chart = stats['chart'] as List<Map<String, dynamic>>;
        
        // Use counter data from FutureBuilder for real-time accuracy
        // This ensures stats always reflect the latest counter values
        final todayJapsFromCounter = counter['today'] ?? _today;
        final lifetimeJapsFromCounter = counter['lifetime'] ?? _lifetime;
        
        // Use malas directly from CounterStore (calculated from completed malas in history)
        // This ensures we only count COMPLETE malas (108 japs = 1 mala)
        final todayMalasFromCounter = counter['todayMalas'] ?? (todayJapsFromCounter ~/ 108);
        final lifetimeMalasFromCounter = counter['lifetimeMalas'] ?? (lifetimeJapsFromCounter ~/ 108);
        
        final streak = activity['streak'] ?? 0;
        final activeDays = activity['activeDays'] ?? 0;
        
        // Trigger confetti for milestone streaks
        if (streak == 7 || streak == 21 || streak == 40) {
          if (_confetti.state != ConfettiControllerState.playing) {
            _confetti.play();
          }
        }
        
        return CustomScrollView(
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: Theme.of(
                        context,
                      ).colorScheme.primary.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Theme.of(context).dividerColor),
                    ),
                    child: Builder(
                      builder: (context) {
                        final theme = Theme.of(context);
                        String streakMessage;
                        if (streak == 0) {
                          streakMessage = context.tr('stats.noActiveStreak');
                        } else if (streak == 7) {
                          streakMessage = context.tr('stats.streakMessage.7');
                        } else if (streak == 21) {
                          streakMessage = context.tr('stats.streakMessage.21');
                        } else if (streak == 40) {
                          streakMessage = context.tr('stats.streakMessage.40');
                        } else {
                          streakMessage = context.tr(
                            'stats.streakMessage.generic',
                            args: {'days': '$streak'},
                          );
                        }
                        return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              context.tr('stats.currentStreak'),
                              style: theme.textTheme.titleMedium,
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: theme.colorScheme.primary.withValues(
                                  alpha: 0.15,
                                ),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                '🔥 $streak',
                                style: theme.textTheme.labelLarge?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ),
                        if (streak >= 3)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: StreakBadge(streakDays: streak),
                          ),
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            streakMessage,
                            style: theme.textTheme.bodySmall,
                          ),
                        ),
                      ],
                    );
                      },
                    ),
                  ),
                  if (badges.isEmpty) const SizedBox.shrink() else
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: badges.map((badge) {
                        final label = switch (badge) {
                          'streak_7' => context.tr('stats.badge.streak7'),
                          'streak_21' => context.tr('stats.badge.streak21'),
                          'streak_40' => context.tr('stats.badge.streak40'),
                          _ => badge,
                        };
                        return Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          decoration: Neo.pill(context),
                          child: Text(
                            label,
                            style: Theme.of(context).textTheme.labelLarge,
                          ),
                        );
                      }).toList(),
                    ),
                  ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: _NeoTile(
                      title: context.tr('stats.metric.todayJaps'),
                      value: todayJapsFromCounter.toString(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _NeoTile(
                      title: context.tr('stats.metric.todayMalas'),
                      value: todayMalasFromCounter.toString(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _NeoTile(
                      title: context.tr('stats.metric.lifetimeMalas'),
                      value: lifetimeMalasFromCounter.toString(),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: _NeoTile(
                      title: context.tr('stats.metric.todayMeditation'),
                      value: _todayMin.toString(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _NeoTile(
                      title: context.tr('stats.metric.lifetimeMeditation'),
                      value: _lifetimeMin.toString(),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Builder(
                builder: (context) {
                  final reached = todayMalasFromCounter >= goal;
                  return Container(
                    margin: const EdgeInsets.only(top: 8),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Theme.of(context).dividerColor),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          reached ? Icons.check_circle : Icons.flag,
                          color: reached
                              ? Theme.of(context).colorScheme.primary
                              : Theme.of(context).colorScheme.outline,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            context.tr(
                              reached
                                  ? 'stats.dailyGoal.met'
                                  : 'stats.dailyGoal.pending',
                              args: {'todayMalas': '$todayMalasFromCounter', 'goal': '$goal'},
                            ),
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
              Builder(
                builder: (context) {
                  if (chart.isEmpty) return const SizedBox.shrink();
                  final theme = Theme.of(context);
                  final maxMalas = chart.fold<int>(0, (prev, element) {
                    final val = element['value'] as int? ?? 0;
                    return val > prev ? val : prev;
                  });
                  final safeMax = maxMalas == 0 ? 1 : maxMalas;

                  return Container(
                    margin: const EdgeInsets.only(top: 8),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: theme.dividerColor),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          context.tr('stats.progressTitle'),
                          style: theme.textTheme.titleMedium,
                        ),
                        const SizedBox(height: 8),
                        RepaintBoundary(
                          child: LayoutBuilder(
                            builder: (context, constraints) {
                              final availableWidth = constraints.maxWidth;
                              final barCount = chart.length;
                              final barWidth = availableWidth / barCount;
                              
                              return SizedBox(
                                height: 164,
                                width: double.infinity,
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  mainAxisSize: MainAxisSize.max,
                                  children: chart.asMap().entries.map((entry) {
                                    final index = entry.key;
                                    final e = entry.value;
                                    final val = e['value'] as int? ?? 0;
                                    final dayLabel = e['day'] as String? ?? '';
                                    final dateLabel = e['dateLabel'] as String? ?? '';
                                    final normalized = val == 0 ? 0.0 : val / safeMax;
                                    final barHeight = val == 0
                                        ? 6.0
                                        : (normalized * 96).clamp(14.0, 96.0);

                                    return RepaintBoundary(
                                      key: ValueKey('chart-bar-$index'),
                                      child: SizedBox(
                                        width: barWidth,
                                        child: Column(
                                          mainAxisAlignment: MainAxisAlignment.end,
                                          mainAxisSize: MainAxisSize.max,
                                          crossAxisAlignment: CrossAxisAlignment.center,
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 4,
                                            vertical: 2,
                                          ),
                                          decoration: BoxDecoration(
                                            color: theme.colorScheme.surfaceVariant
                                                .withOpacity(0.7),
                                            borderRadius: BorderRadius.circular(8),
                                          ),
                                          child: Text(
                                            '$val',
                                            style: theme.textTheme.labelSmall?.copyWith(
                                              fontWeight: FontWeight.w700,
                                              fontSize: 11,
                                            ),
                                            textAlign: TextAlign.center,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        AnimatedContainer(
                                          duration: const Duration(milliseconds: 220),
                                          curve: Curves.easeOutCubic,
                                          height: barHeight,
                                          width: 14,
                                          decoration: BoxDecoration(
                                            gradient: LinearGradient(
                                              begin: Alignment.bottomCenter,
                                              end: Alignment.topCenter,
                                              colors: [
                                                theme.colorScheme.primary,
                                                theme.colorScheme.primaryContainer,
                                              ],
                                            ),
                                            borderRadius: BorderRadius.circular(6),
                                            boxShadow: [
                                              BoxShadow(
                                                color: theme.colorScheme.primary
                                                    .withOpacity(0.2),
                                                blurRadius: 4,
                                                offset: const Offset(0, 3),
                                              ),
                                            ],
                                          ),
                                          alignment: Alignment.topCenter,
                                          child: val > 0
                                              ? Icon(
                                                  Icons.energy_savings_leaf,
                                                  size: 12,
                                                  color: theme.colorScheme.onPrimary,
                                                )
                                              : null,
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          dayLabel,
                                          style: theme.textTheme.labelSmall?.copyWith(
                                            fontWeight: FontWeight.w600,
                                            fontSize: 11,
                                          ),
                                          textAlign: TextAlign.center,
                                        ),
                                        Text(
                                          dateLabel,
                                          style: theme.textTheme.labelSmall?.copyWith(
                                            fontSize: 10,
                                          ),
                                          textAlign: TextAlign.center,
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              }).toList(),
                            ),
                          );
                            },
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
              const SizedBox(height: 16),
              Builder(
                builder: (context) {
                  final dedicationText = dedication.isEmpty
                      ? context.tr('stats.dedication.empty')
                      : context.tr('stats.dedication.title', args: {'note': dedication});
                  return InkWell(
                    onTap: () async {
                      final controller = TextEditingController(text: dedication);
                      final updated = await showDialog<String>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: Text(context.tr('stats.dedication.editTitle')),
                          content: TextField(
                            controller: controller,
                            maxLines: 3,
                            textInputAction: TextInputAction.done,
                            decoration: InputDecoration(
                              hintText: context.tr('stats.dedication.hint'),
                              border: const OutlineInputBorder(),
                            ),
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(ctx, null),
                              child: Text(context.tr('common.cancel')),
                            ),
                            FilledButton(
                              onPressed: () =>
                                  Navigator.pop(ctx, controller.text.trim()),
                              child: Text(context.tr('common.save')),
                            ),
                          ],
                        ),
                      );
                      if (updated != null && context.mounted) {
                        final ds = await DedicationStore.create();
                        await ds.setNote(updated);
                        // Reload stats to update FutureBuilder in real-time
                        final language = AppLocalizationScope.of(context).language;
                        final locale = language == 'hi' ? 'hi' : 'en';
                        setState(() {
                          _allStatsFuture = _loadAllStats(locale: locale);
                        });
                      }
                    },
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
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
                              dedicationText,
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Icon(
                            Icons.edit,
                            size: 18,
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                        ],
                      ),
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
                            final int todayJaps = todayJapsFromCounter;
                            final int lifetimeMalasLocal = lifetimeMalasFromCounter;
                            final int streakDays = streak;
                            debugPrint(
                              '[Stats] Share tapped → todayJaps=$todayJaps lifetimeMalas=$lifetimeMalasLocal streakDays=$streakDays',
                            );
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
                    final int todayJaps = todayJapsFromCounter;
                    final int lifetimeMalasLocal = lifetimeMalasFromCounter;
                    final int streakDays = streak;
                    debugPrint(
                      '[Stats][DEV] Long-press bypass → opening preview directly',
                    );
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
                        ? context.tr('stats.sharePreparing')
                        : context.tr('stats.shareButton'),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  context.tr('stats.daysActive', args: {'count': '$activeDays'}),
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
              ),
              Text(
                context.tr('stats.calendar'),
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 6),
              _ActivityCalendar(todayJaps: _today, todayMalas: todayMalas),
            ]),
          ),
        ),
      ],
    );
      },
    );
  }

  Widget _metricTile(String label, String value) {
    return Column(
      children: [
        Text(
          value,
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 6),
        Text(label, style: const TextStyle(fontSize: 13)),
      ],
    );
  }
}

// --- Re-add missing _NeoTile widget (used in StatsPage) ---
class _NeoTile extends StatelessWidget {
  final String title;
  final String value;
  const _NeoTile({required this.title, required this.value});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: theme.colorScheme.surface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            offset: const Offset(3, 3),
            blurRadius: 6,
          ),
          BoxShadow(
            color: Colors.white.withOpacity(0.6),
            offset: const Offset(-3, -3),
            blurRadius: 6,
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              title,
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSurface.withOpacity(0.6),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              value,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActivityCalendar extends StatefulWidget {
  final int todayJaps;
  final int todayMalas;

  const _ActivityCalendar({super.key, this.todayJaps = 0, this.todayMalas = 0});

  @override
  State<_ActivityCalendar> createState() => _ActivityCalendarState();
}

class _ActivityCalendarState extends State<_ActivityCalendar> {
  Map<String, _DailyHistoryEntry>? _history;
  DateTime _visibleMonth = DateTime(DateTime.now().year, DateTime.now().month);
  DateTime? _selectedDate = DateTime.now();
  bool _dateFormattingInitialized = false;

  @override
  void initState() {
    super.initState();
    // Initialize with default locale immediately to avoid errors
    _initializeDateFormatting(preferredLocale: 'en');
    _loadHistory();
  }

  Future<void> _initializeDateFormatting({BuildContext? ctx, String? preferredLocale, bool force = false}) async {
    if (_dateFormattingInitialized && !force) return;
    
    try {
      String localeCode = preferredLocale ?? 'en';
      if (ctx != null && preferredLocale == null) {
        try {
          final lang = AppLocalizationScope.of(ctx).language;
          localeCode = lang == 'hi' ? 'hi' : 'en';
        } catch (_) {
          // Context not available, use default
        }
      }
      await initializeDateFormatting(localeCode);
      if (mounted) {
        setState(() => _dateFormattingInitialized = true);
      }
    } catch (e) {
      // Fallback to English if initialization fails
      try {
        await initializeDateFormatting('en');
        if (mounted) {
          setState(() => _dateFormattingInitialized = true);
        }
      } catch (_) {
        // If even English fails, mark as initialized anyway to avoid infinite loading
        if (mounted) {
          setState(() => _dateFormattingInitialized = true);
        }
      }
    }
  }

  @override
  void didUpdateWidget(covariant _ActivityCalendar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.todayJaps != widget.todayJaps ||
        oldWidget.todayMalas != widget.todayMalas) {
      _loadHistory();
    }
  }

  Future<void> _loadHistory() async {
    final raw = await ActivityStore.getDailyHistory();
    final parsed = <String, _DailyHistoryEntry>{};

    for (final entry in raw.entries) {
      final value = entry.value;
      if (value is Map<String, dynamic>) {
        final japs = (value['japs'] as num?)?.round() ?? 0;
        final malas = (value['malas'] as num?)?.round() ?? 0;
        parsed[entry.key] = _DailyHistoryEntry(japs: japs, malas: malas);
      }
    }

    if (!mounted) return;
    setState(() => _history = parsed);
  }

  void _changeMonth(int offset) {
    final target = DateTime(_visibleMonth.year, _visibleMonth.month + offset);
    final now = DateTime.now();
    final currentMonth = DateTime(now.year, now.month);
    if (target.isAfter(currentMonth)) return;
    setState(() {
      _visibleMonth = target;
      _selectedDate = DateTime(target.year, target.month, 1);
    });
  }

  @override
  Widget build(BuildContext context) {
    final history = _history;
    
    // Initialize or re-initialize with correct locale from context
    WidgetsBinding.instance.addPostFrameCallback((_) {
      try {
        final lang = AppLocalizationScope.of(context).language;
        final localeCode = lang == 'hi' ? 'hi' : 'en';
        // Re-initialize if locale is different from default (force re-initialization)
        if (!_dateFormattingInitialized || localeCode != 'en') {
          _initializeDateFormatting(ctx: context, preferredLocale: localeCode, force: true);
        }
      } catch (_) {
        // If context not available, ensure at least English is initialized
        if (!_dateFormattingInitialized) {
          _initializeDateFormatting(preferredLocale: 'en');
        }
      }
    });
    
    if (history == null || !_dateFormattingInitialized) {
      return const SizedBox(
        height: 180,
        child: Center(child: CircularProgressIndicator()),
      );
    }

    final theme = Theme.of(context);
    final now = DateTime.now();
    final currentMonth = DateTime(now.year, now.month);
    final monthStart = DateTime(_visibleMonth.year, _visibleMonth.month, 1);
    final startOffset = monthStart.weekday % 7; // Sunday-first grid
    final startDate = monthStart.subtract(Duration(days: startOffset));
    const totalCells = 42; // 6 rows
    final dates = List.generate(
      totalCells,
      (i) => startDate.add(Duration(days: i)),
    );
    final canGoForward = _visibleMonth.isBefore(currentMonth);

    final selected = _selectedDate;
    final selectedEntry = selected == null
        ? const _DailyHistoryEntry(japs: 0, malas: 0)
        : _entryFor(selected);

    // Get language for date formatting
    final lang = AppLocalizationScope.of(context).language;
    final localeCode = lang == 'hi' ? 'hi' : 'en';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            IconButton(
              icon: const Icon(Icons.chevron_left),
              onPressed: () => _changeMonth(-1),
            ),
            Expanded(
              child: Center(
                child: Text(
                  DateFormat('MMMM yyyy', localeCode).format(_visibleMonth),
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.chevron_right),
              onPressed: canGoForward ? () => _changeMonth(1) : null,
            ),
          ],
        ),
        const SizedBox(height: 4),
        Row(
          children: ['S', 'M', 'T', 'W', 'T', 'F', 'S']
              .map(
                (d) => Expanded(
                  child: Center(
                    child: Text(
                      d,
                      style: theme.textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              )
              .toList(),
        ),
        const SizedBox(height: 8),
        AspectRatio(
          aspectRatio: 7 / 6,
          child: GridView.builder(
            padding: EdgeInsets.zero,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
              mainAxisSpacing: 6,
              crossAxisSpacing: 6,
            ),
            itemCount: dates.length,
            itemBuilder: (context, index) {
              final date = dates[index];
              final entry = _entryFor(date);
              final isFutureDate = date.isAfter(
                DateTime(now.year, now.month, now.day),
              );
              return RepaintBoundary(
                key: ValueKey('calendar-cell-${date.year}-${date.month}-${date.day}'),
                child: _CalendarCell(
                  date: date,
                  entry: entry,
                  now: now,
                  visibleMonth: _visibleMonth,
                  selected: selected,
                  theme: theme,
                  onTap: isFutureDate
                      ? null
                      : () {
                          setState(() => _selectedDate = date);
                        },
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 12),
        _buildLegend(context),
        if (selected != null) ...[
          const SizedBox(height: 12),
          _buildSelectionSummary(context, selected, selectedEntry),
        ],
      ],
    );
  }

  _DailyHistoryEntry _entryFor(DateTime date) {
    final history = _history;
    if (history == null) return const _DailyHistoryEntry(japs: 0, malas: 0);
    if (DateUtils.isSameDay(date, DateTime.now())) {
      return _DailyHistoryEntry(
        japs: widget.todayJaps,
        malas: widget.todayMalas,
      );
    }
    return history[_dateKey(date)] ??
        const _DailyHistoryEntry(japs: 0, malas: 0);
  }

  String _dateKey(DateTime date) {
    // Use manual formatting for ISO date keys to avoid locale initialization requirement
    final year = date.year.toString().padLeft(4, '0');
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '$year-$month-$day';
  }

  static Color _colorForMalas(int malas, ThemeData theme, bool isCurrentMonth) {
    Color base;
    if (malas >= 15) {
      base = Colors.deepOrange.shade200;
    } else if (malas >= 8) {
      base = Colors.teal.shade200;
    } else if (malas >= 5) {
      base = Colors.green.shade200;
    } else if (malas >= 1) {
      base = Colors.amber.shade100;
    } else {
      base = theme.brightness == Brightness.dark
          ? theme.colorScheme.surface
          : Colors.white;
    }
    return isCurrentMonth ? base : base.withOpacity(0.45);
  }

  Widget _buildLegend(BuildContext context) {
    final theme = Theme.of(context);
    final zero = _colorForMalas(0, theme, true);
    final few = _colorForMalas(1, theme, true);
    final some = _colorForMalas(5, theme, true);
    final plenty = _colorForMalas(8, theme, true);
    final intense = _colorForMalas(15, theme, true);
    return Wrap(
      spacing: 16,
      runSpacing: 8,
      children: [
        _LegendSwatch(color: zero, label: context.tr('stats.legend.zero')),
        _LegendSwatch(color: few, label: context.tr('stats.legend.few')),
        _LegendSwatch(color: some, label: context.tr('stats.legend.some')),
        _LegendSwatch(color: plenty, label: context.tr('stats.legend.plenty')),
        _LegendSwatch(
          color: intense,
          label: context.tr('stats.legend.intense'),
        ),
      ],
    );
  }

  Widget _buildSelectionSummary(
    BuildContext context,
    DateTime date,
    _DailyHistoryEntry entry,
  ) {
    final theme = Theme.of(context);
    final lang = AppLocalizationScope.of(context).language;
    final localeCode = lang == 'hi' ? 'hi' : 'en';
    final formattedDate = DateFormat(
      'EEE, d MMM yyyy',
      localeCode,
    ).format(date);
    final now = DateTime.now();
    final titleLabel = DateUtils.isSameDay(date, now)
        ? '${context.tr('stats.calendar.today')} • $formattedDate'
        : formattedDate;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.dividerColor),
      ),
      child: Row(
        children: [
          Icon(Icons.calendar_month, color: theme.colorScheme.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(titleLabel, style: theme.textTheme.titleSmall),
                const SizedBox(height: 4),
                Text(
                  context.tr(
                    'stats.calendar.summary',
                    args: {'malas': '${entry.malas}', 'japs': '${entry.japs}'},
                  ),
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// Separate widget for calendar cell to optimize rebuilds
class _CalendarCell extends StatelessWidget {
  final DateTime date;
  final _DailyHistoryEntry entry;
  final DateTime now;
  final DateTime visibleMonth;
  final DateTime? selected;
  final ThemeData theme;
  final VoidCallback? onTap;

  const _CalendarCell({
    required this.date,
    required this.entry,
    required this.now,
    required this.visibleMonth,
    required this.selected,
    required this.theme,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final malas = entry.malas;
    final isCurrentMonth =
        date.month == visibleMonth.month &&
        date.year == visibleMonth.year;
    final isSelected =
        selected != null && DateUtils.isSameDay(selected!, date);
    final isToday = DateUtils.isSameDay(date, now);

    final fill = _ActivityCalendarState._colorForMalas(malas, theme, isCurrentMonth);
    final borderColor = isSelected
        ? theme.colorScheme.primary
        : theme.dividerColor.withOpacity(isCurrentMonth ? 1 : 0.4);
    final textColor = isCurrentMonth
        ? theme.colorScheme.onSurface
        : theme.colorScheme.onSurface.withOpacity(0.4);

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
        decoration: BoxDecoration(
          color: fill,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: borderColor,
            width: isSelected ? 2 : 1,
          ),
        ),
        alignment: Alignment.center,
        child: Text(
          '${date.day}',
          style: theme.textTheme.labelSmall?.copyWith(
            fontWeight: isToday ? FontWeight.w700 : FontWeight.w500,
            color: textColor,
          ),
        ),
      ),
    );
  }
}

class _DailyHistoryEntry {
  final int japs;
  final int malas;

  const _DailyHistoryEntry({required this.japs, required this.malas});
}

class _LegendSwatch extends StatelessWidget {
  final Color color;
  final String label;

  const _LegendSwatch({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 16,
          height: 16,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: theme.dividerColor),
          ),
        ),
        const SizedBox(width: 6),
        Text(label, style: theme.textTheme.labelSmall),
      ],
    );
  }
}

class _GitaTab extends StatelessWidget {
  const _GitaTab();

  @override
  Widget build(BuildContext context) {
    return const GitaPage();
  }
}

// Legacy settings classes removed. Latest settings UI lives in lib/settings/settings_page.dart
