import 'dart:async' show unawaited;

import 'package:flutter/foundation.dart';
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
import 'gamify/gamify_store.dart';
import 'theme/theme.dart';
import 'theme/design_system.dart';
import 'data/language_store.dart';
import 'l10n/app_localizations.dart';
import 'sync/sync_service.dart';
import 'utils/weekly_chart_data.dart';
import 'counter/counter_page.dart';
import 'timer/timer_service.dart';
import 'core/sound_manager.dart';
import 'widgets/widgets.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

class App extends StatefulWidget {
  final ThemeMode initialThemeMode;

  const App({super.key, required this.initialThemeMode});
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

    // Start with the theme passed from splash so we don't flash the system theme
    _themeMode = widget.initialThemeMode;
    _loadThemeMode();
    _loadLanguage();
    _initNotifications(); // fire-and-forget
    unawaited(_showWelcomeSnackbar().catchError((error, stackTrace) {
      if (kDebugMode) {
        debugPrint('[App] Error showing welcome snackbar: $error\n$stackTrace');
      }
    }));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      unawaited(SyncService.syncToday().catchError((error, stackTrace) {
        if (kDebugMode) {
          debugPrint('[App] Error syncing today: $error\n$stackTrace');
        }
      }));
      // Flush pending writes when app goes to background
      unawaited(ActivityStore.flushPendingWrites().catchError((error, stackTrace) {
        if (kDebugMode) {
          debugPrint('[App] Error flushing pending writes: $error\n$stackTrace');
        }
      }));
    } else if (state == AppLifecycleState.detached) {
      // App is being closed - mark it so timer resets on next open
      unawaited(_timerService.markAppClosed().catchError((error, stackTrace) {
        if (kDebugMode) {
          debugPrint('[App] Error marking app closed: $error\n$stackTrace');
        }
      }));
      // Flush pending writes before app closes
      unawaited(ActivityStore.flushPendingWrites().catchError((error, stackTrace) {
        if (kDebugMode) {
          debugPrint('[App] Error flushing pending writes on close: $error\n$stackTrace');
        }
      }));
      // Clean up ActivityStore resources
      ActivityStore.cleanup();
    } else if (state == AppLifecycleState.resumed) {
      unawaited(_timerService.load().catchError((error, stackTrace) {
        if (kDebugMode) {
          debugPrint('[App] Error loading timer service: $error\n$stackTrace');
        }
      }));
    }
  }

  int _index = 0;
  final GlobalKey<_StatsPageState> _statsKey = GlobalKey<_StatsPageState>();
  final GlobalKey<CounterPageState> _counterKey = GlobalKey<CounterPageState>();
  late ThemeMode _themeMode;
  String _language = 'en';

  late final List<Widget> _pages = [
    CounterPage(key: _counterKey),
    _StatsPage(key: _statsKey),
    const _GitaTab(),
    TimerPage(
      onMeditationUpdated: () {
        // Refresh meditation stats when timer updates meditation minutes
        _statsKey.currentState?.refreshMeditationStats();
      },
    ),
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
    
    // Reschedule notifications with new language
    unawaited(_rescheduleNotificationsForLanguage(language).catchError((error, stackTrace) {
      if (kDebugMode) {
        debugPrint('[App] Error rescheduling notifications: $error\n$stackTrace');
      }
    }));
  }
  
  Future<void> _rescheduleNotificationsForLanguage(String language) async {
    try {
      final ns = NotificationService();
      await ns.init();
      final allowed = await ns.areNotificationsAllowed();
      if (allowed) {
        // Reschedule all notifications with the new language
        await ns.scheduleDefaults(language: language);
        await ns.scheduleDailyMotivation(language: language);
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[App] Failed to reschedule notifications for language change: $e');
      }
    }
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
                Theme.of(context)
                    .colorScheme
                    .surface
                    .withValues(alpha: 0.95),
                Theme.of(context)
                    .colorScheme
                    .primary
                    .withValues(alpha: 0.05),
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
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final isNarrow = constraints.maxWidth < 360;
                  final iconSize = isNarrow ? 20.0 : 22.0;
                  final fontSize = isNarrow ? 9.0 : 10.0;
                  final horizontalPadding = isNarrow ? 4.0 : 8.0;
                  final verticalPadding = isNarrow ? 4.0 : 6.0;
                  final isDark = Theme.of(context).brightness == Brightness.dark;
                  
                  return Padding(
                    padding: EdgeInsets.symmetric(horizontal: isNarrow ? 8 : 12, vertical: 8),
                    child: Container(
                      decoration: BoxDecoration(
                        // Light theme: pure white bar
                        // Dark theme: pure black bar
                        color: isDark 
                            ? Colors.black
                            : Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.1),
                            blurRadius: 24,
                            offset: const Offset(0, -4),
                          ),
                        ],
                      ),
                      padding: EdgeInsets.symmetric(horizontal: horizontalPadding, vertical: verticalPadding),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          _navIcon(Icons.touch_app, 0, 'nav.counter', iconSize: iconSize, fontSize: fontSize),
                          _navIcon(Icons.bar_chart, 1, 'nav.stats', iconSize: iconSize, fontSize: fontSize),
                          _navIcon(Icons.menu_book, 2, 'nav.gita', iconSize: iconSize, fontSize: fontSize),
                          _navIcon(Icons.timer, 3, 'nav.timer', iconSize: iconSize, fontSize: fontSize),
                          _navIcon(Icons.settings, 4, 'nav.settings', iconSize: iconSize, fontSize: fontSize),
                        ],
                      ),
                    ),
                  );
                },
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
    unawaited(StatsAmbience.instance.dispose().catchError((error, stackTrace) {
      if (kDebugMode) {
        debugPrint('[App] Error disposing StatsAmbience: $error\n$stackTrace');
      }
    }));
    // Dispose AdManager to clean up timers and ads
    AdManager.instance.dispose();
    super.dispose();
  }

  Widget _navIcon(IconData icon, int idx, String labelKey, {double iconSize = 22.0, double fontSize = 10.0}) {
    final active = _index == idx;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    
    // Light theme: use original theme colors (no changes)
    // Dark theme: use white for all icons and text
    final iconColor = isDark
        ? Colors.white // Dark theme: all icons white
        : (active 
            ? theme.colorScheme.primary // Light theme: active = primary orange
            : theme.colorScheme.onSurfaceVariant); // Light theme: inactive = grey
    
    final textColor = isDark
        ? Colors.white // Dark theme: all text white
        : (active 
            ? theme.colorScheme.onSurface // Light theme: active = dark
            : theme.colorScheme.onSurfaceVariant); // Light theme: inactive = grey
    return Expanded(
      child: GestureDetector(
        onTap: () => _handleNavTap(idx),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: EdgeInsets.symmetric(vertical: 6, horizontal: 4),
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
              Icon(icon, color: iconColor, size: iconSize),
              SizedBox(height: fontSize > 9 ? 2 : 1),
              Flexible(
                child: Text(
                  _translate(labelKey),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: textColor, // Already set above with proper light/dark theme separation
                    fontWeight: active ? FontWeight.w600 : null,
                    fontSize: fontSize,
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
    
    // Refresh counter page goal when navigating to counter tab
    // This ensures goal is always in sync, especially when coming from settings
    if (index == 0) {
      // Navigating to counter page - refresh goal to sync with any changes
      _counterKey.currentState?.refreshGoalFromSettings();
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
        ).catchError((error, stackTrace) {
          if (kDebugMode) {
            debugPrint('[App] Error showing interstitial: $error\n$stackTrace');
          }
        }),
      );
      AdManager.instance.recordEvent('gita.session', 'end');
    }
    setState(() => _index = index);
  }

  Future<void> _pauseTimerForNav() async {
    if (!_timerService.running) return;
    try {
      await _timerService.pause();
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('[App] Error pausing timer: $e\n$st');
      }
    }
    try {
      await SoundManager.instance.pauseAmbience();
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('[App] Error pausing ambience: $e\n$st');
      }
    }
    try {
      await WakelockPlus.disable();
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('[App] Error disabling wakelock: $e\n$st');
      }
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

  bool _loading = true;
  int _lifetime = 0;
  static const _ambienceKey = 'stats.ambience.enabled';
  bool _ambienceEnabled = false;

  // Performance optimization: Use ValueNotifier for frequently updated values
  // This avoids rebuilding the entire widget tree when stats update
  late final ValueNotifier<int> _todayNotifier;
  late final ValueNotifier<int> _todayMinNotifier;
  late final ValueNotifier<int> _lifetimeMinNotifier;

  // Load all stats in one batch to avoid multiple FutureBuilders
  Future<Map<String, dynamic>>? _allStatsFuture;
  
  // Cache last loaded stats to show immediately while loading new data
  Map<String, dynamic>? _cachedStats;

  @override
  bool get wantKeepAlive => true; // Preserve state when hidden

  @override
  void initState() {
    super.initState();
    // Initialize ValueNotifiers for performance optimization
    _todayNotifier = ValueNotifier<int>(0);
    _todayMinNotifier = ValueNotifier<int>(0);
    _lifetimeMinNotifier = ValueNotifier<int>(0);
    
    _confetti = ConfettiController(duration: const Duration(seconds: 3));
    _init();
    unawaited(AdManager.instance.preloadPlacement('stats.share_rewarded').catchError((error, stackTrace) {
      if (kDebugMode) {
        debugPrint('[StatsPage] Error preloading ad: $error\n$stackTrace');
      }
    }));

    _loadAmbiencePref();
    
    // Load all stats once in parallel
    _allStatsFuture = _loadAllStats();
  }
  
  /// Check if a milestone celebration has been shown
  Future<bool> _hasShownCelebration(int streakDays) async {
    final prefs = await PrefsManager.instance;
    return prefs.getBool('streak_${streakDays}_celebration_shown') ?? false;
  }
  
  /// Mark a milestone celebration as shown
  Future<void> _markCelebrationShown(int streakDays) async {
    final prefs = await PrefsManager.instance;
    await prefs.setBool('streak_${streakDays}_celebration_shown', true);
  }
  
  /// Show celebration dialog for milestone streaks
  Future<void> _showCelebrationDialog(int streakDays) async {
    if (!mounted) return;
    
    // Wait for the next frame to ensure widget tree is ready
    await Future.delayed(const Duration(milliseconds: 100));
    if (!mounted) return;
    
    // Check if AppLocalizationScope is available
    final scope = AppLocalizationScope.maybeOf(context);
    if (scope == null) {
      // If scope is not available, try again after a short delay
      await Future.delayed(const Duration(milliseconds: 200));
      if (!mounted) return;
      final retryScope = AppLocalizationScope.maybeOf(context);
      if (retryScope == null) {
        // Still not available, skip showing dialog
        return;
      }
    }
    
    String titleKey;
    String messageKey;
    
    switch (streakDays) {
      case 7:
        titleKey = 'stats.celebration.7.title';
        messageKey = 'stats.celebration.7.message';
        break;
      case 21:
        titleKey = 'stats.celebration.21.title';
        messageKey = 'stats.celebration.21.message';
        break;
      case 40:
        titleKey = 'stats.celebration.40.title';
        messageKey = 'stats.celebration.40.message';
        break;
      default:
        return; // Only show for milestone streaks
    }
    
    // Play confetti
    _confetti.play();
    
    // Show dialog using post-frame callback to ensure context is ready
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final dialogContext = context;
      final dialogScope = AppLocalizationScope.maybeOf(dialogContext);
      if (dialogScope == null) return;
      
      await showDialog(
        context: dialogContext,
        barrierDismissible: true,
        builder: (ctx) {
          final lang = dialogScope.language;
          final title = AppStrings.resolve(lang, titleKey);
          final message = AppStrings.resolve(lang, messageKey);
          final okText = AppStrings.resolve(lang, 'common.ok');
          
          return AlertDialog(
            title: Text(title),
            content: Text(message),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: Text(okText),
              ),
            ],
          );
        },
      );
    });
  }
  
  /// Check and show celebration for milestone streaks (only once)
  Future<void> _checkAndShowCelebration(int streak) async {
    if (streak != 7 && streak != 21 && streak != 40) return;
    
    final hasShown = await _hasShownCelebration(streak);
    if (!hasShown) {
      await _markCelebrationShown(streak);
      await _showCelebrationDialog(streak);
    }
  }
  
  /// Load all stats data in parallel for better performance
  Future<Map<String, dynamic>> _loadAllStats({String? locale}) async {
    final chartLocale = locale ?? 'en';
    // Use eagerError: false to handle individual failures gracefully
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
    ], eagerError: false).then((results) {
      // Handle any individual failures gracefully
      return results;
    }).catchError((error, stackTrace) {
      if (kDebugMode) {
        debugPrint('[StatsPage] Error loading stats: $error\n$stackTrace');
      }
      // Return empty stats on error
      return <dynamic>[
        {'today': 0, 'lifetime': 0, 'todayMalas': 0, 'lifetimeMalas': 0},
        {'streak': 0, 'activeDays': 0},
        0,
        <String>{},
        '',
        <Map<String, dynamic>>[],
      ];
    });
    
    final stats = {
      'counter': results[0] as Map<String, int>,
      'activity': results[1] as Map<String, int>,
      'goal': results[2] as int,
      'badges': results[3] as Set<String>,
      'dedication': results[4] as String,
      'chart': results[5] as List<Map<String, dynamic>>,
    };
    
    return stats;
  }
  
  @override
  void dispose() {
    // Dispose ValueNotifiers and controllers
    _todayNotifier.dispose();
    _todayMinNotifier.dispose();
    _lifetimeMinNotifier.dispose();
    // Dispose confetti controller safely
    try {
      _confetti.dispose();
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[StatsPage] Error disposing confetti: $e');
      }
    }
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
    unawaited(_refreshStatsData().catchError((error, stackTrace) {
      if (kDebugMode) {
        debugPrint('[StatsPage] Error refreshing stats: $error\n$stackTrace');
      }
    }));
    // Check for milestone celebrations when page becomes visible
    unawaited(_checkCelebrationOnVisible().catchError((error, stackTrace) {
      if (kDebugMode) {
        debugPrint('[StatsPage] Error checking celebration: $error\n$stackTrace');
      }
    }));
  }
  
  /// Check for milestone celebrations when page becomes visible
  Future<void> _checkCelebrationOnVisible() async {
    // Wait a bit to ensure widget tree is ready
    await Future.delayed(const Duration(milliseconds: 300));
    if (!mounted) return;
    
    // Load stats to get current streak
    final stats = await _loadAllStats();
    final activity = stats['activity'] as Map<String, int>;
    final streak = activity['streak'] ?? 0;
    await _checkAndShowCelebration(streak);
  }
  
  /// Refresh stats data without full refresh animation (called on visibility)
  Future<void> _refreshStatsData() async {
    // Record current daily summary to ensure stats are up to date
    final s = await CounterStore.create();
    final mstore = await MeditationStore.create();
    await ActivityStore.recordDailySummary(s.todayJaps, s.todayJaps ~/ 108); // TODO: Replace 108 with AppConstants.japsPerMala
    
    if (!mounted) return;
    
    // Invalidate chart cache to ensure fresh data
    WeeklyChartData.invalidateCache();
    
    // Reload all stats with correct locale
    final language = AppLocalizationScope.of(context).language;
    final locale = language == 'hi' ? 'hi' : 'en';
    _allStatsFuture = _loadAllStats(locale: locale);
    
    // Update ValueNotifiers - only rebuilds widgets listening to these values
    _todayNotifier.value = s.todayJaps;
    _todayMinNotifier.value = mstore.todayMinutes;
    _lifetimeMinNotifier.value = mstore.lifetimeMinutes;
    
    // Only update lifetime in setState (rarely changes)
    if (mounted && _lifetime != s.lifetimeJaps) {
      setState(() {
        _lifetime = s.lifetimeJaps;
      });
    }
    
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
    await ActivityStore.recordDailySummary(s.todayJaps, s.todayJaps ~/ 108); // TODO: Replace 108 with AppConstants.japsPerMala

    if (!mounted) return;
    
    // Invalidate chart cache before refreshing
    WeeklyChartData.invalidateCache();
    
    // Reload all stats in one batch with correct locale
    final language = AppLocalizationScope.of(context).language;
    final locale = language == 'hi' ? 'hi' : 'en';
    _allStatsFuture = _loadAllStats(locale: locale);
    
    // Update ValueNotifiers - only rebuilds widgets listening to these values
    _todayNotifier.value = s.todayJaps;
    _todayMinNotifier.value = mstore.todayMinutes;
    _lifetimeMinNotifier.value = mstore.lifetimeMinutes;
    
    // Only update rarely changing values in setState
    setState(() {
      _lifetime = s.lifetimeJaps;
    });
    // Also ensure today is marked active on manual refresh
    if (s.todayJaps > 0) {
      await ActivityStore.markTodayActive();
    }

    // Stats celebration will be checked automatically when stats are reloaded
  }
  
  /// Refresh meditation minutes in stats (called from timer page via callback)
  Future<void> refreshMeditationStats() async {
    final mstore = await MeditationStore.create();
    if (!mounted) return;
    _todayMinNotifier.value = mstore.todayMinutes;
    _lifetimeMinNotifier.value = mstore.lifetimeMinutes;
    if (kDebugMode) {
      debugPrint('[StatsPage] Refreshed meditation stats: Today=${mstore.todayMinutes}, Lifetime=${mstore.lifetimeMinutes}');
    }
  }

  Future<void> _init() async {
    final s = await CounterStore.create(); // uses same prefs + new-day reset
    final mstore = await MeditationStore.create();
    final dstore = await DedicationStore.create();
    await ActivityStore.recordDailySummary(s.todayJaps, s.todayJaps ~/ 108); // TODO: Replace 108 with AppConstants.japsPerMala
    
    // Update ValueNotifiers instead of setState for frequently changing values
    _todayNotifier.value = s.todayJaps;
    _todayMinNotifier.value = mstore.todayMinutes;
    _lifetimeMinNotifier.value = mstore.lifetimeMinutes;
    
    setState(() {
      _lifetime = s.lifetimeJaps;
      _loading = false;
    });
    
    // Populate cache with initial data for instant display
    _allStatsFuture?.then((stats) {
      if (mounted) {
        _cachedStats = stats;
      }
    });
    
    // Ensure today is recorded as active if user already has japs today
    if (s.todayJaps > 0) {
      await ActivityStore.markTodayActive();
    }

    final streak = await ActivityStore.currentStreak();
    await _checkAndShowCelebration(streak);
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

    // Calculate malas from ValueNotifier (used as fallback, FutureBuilder provides main data)
    final todayMalas = _todayNotifier.value ~/ 108; // TODO: Replace with AppConstants.japsPerMala
    final lifetimeMalas = _lifetime ~/ 108; // TODO: Replace with AppConstants.japsPerMala
    // Load goal (synchronously via FutureBuilder below to avoid blocking build)

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(context.tr('stats.title')),
        backgroundColor: Colors.transparent,
        elevation: 0,
        flexibleSpace: Container(
          decoration: BoxDecoration(
            color: Theme.of(context).scaffoldBackgroundColor,
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
      body: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
        ),
        child: Stack(
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
                colors: [
                  DesignSystem.buttonPrimary,
                  DesignSystem.buttonPrimary.withValues(alpha: 0.8),
                  DesignSystem.buttonPrimary.withValues(alpha: 0.6),
                ],
              ),
            ),
          ],
        ),
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
        // Show cached data immediately while loading new data (UX optimization)
        // This makes the app feel instant even when refreshing
        final stats = statsSnapshot.hasData 
            ? statsSnapshot.data! 
            : (_cachedStats ?? {
                'counter': {'today': _todayNotifier.value, 'lifetime': _lifetime, 'todayMalas': 0, 'lifetimeMalas': 0},
                'activity': {'streak': 0, 'activeDays': 0},
                'goal': 0,
                'badges': <String>{},
                'dedication': '',
                'chart': <Map<String, dynamic>>[],
              });
        
        // Update cache when new data arrives
        if (statsSnapshot.hasData) {
          _cachedStats = statsSnapshot.data;
        }
        
        // Show loading indicator only if we have no cached data at all
        if (!statsSnapshot.hasData && _cachedStats == null) {
          return const Center(child: CircularProgressIndicator());
        }
        final counter = stats['counter'] as Map<String, int>;
        final activity = stats['activity'] as Map<String, int>;
        final goal = stats['goal'] as int;
        final badges = stats['badges'] as Set<String>;
        final dedication = stats['dedication'] as String;
        final chart = stats['chart'] as List<Map<String, dynamic>>;
        
        // Use counter data from FutureBuilder for real-time accuracy
        // This ensures stats always reflect the latest counter values
        final todayJapsFromCounter = counter['today'] ?? _todayNotifier.value;
        final lifetimeJapsFromCounter = counter['lifetime'] ?? _lifetime;
        
        // Use malas directly from CounterStore (calculated from completed malas in history)
        // This ensures we only count COMPLETE malas (108 japs = 1 mala)
        final todayMalasFromCounter = counter['todayMalas'] ?? (todayJapsFromCounter ~/ 108); // TODO: Replace 108 with AppConstants.japsPerMala
        final lifetimeMalasFromCounter = counter['lifetimeMalas'] ?? (lifetimeJapsFromCounter ~/ 108); // TODO: Replace 108 with AppConstants.japsPerMala
        
        final streak = activity['streak'] ?? 0;
        final activeDays = activity['activeDays'] ?? 0;
        
        return CustomScrollView(
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  GlassCard(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    borderRadius: 12,
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
                        // Hide badge for 7-day streak
                        if (streak >= 3 && streak != 7)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: StreakBadge(streakDays: streak),
                          ),
                        // Hide streak message for 7-day streak
                        if (streak != 7)
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
                      children: badges
                          .where((badge) => badge != 'streak_7') // Filter out 7-day streak badge
                          .map((badge) {
                        final label = switch (badge) {
                          'streak_7' => context.tr('stats.badge.streak7'),
                          'streak_21' => context.tr('stats.badge.streak21'),
                          'streak_40' => context.tr('stats.badge.streak40'),
                          _ => badge,
                        };
                        return GlassCard(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          borderRadius: 20,
                          child: Text(
                            label,
                            style: Theme.of(context).textTheme.labelLarge,
                          ),
                        );
                      }).toList(),
                    ),
                  ),
              const SizedBox(height: 16),
              LayoutBuilder(
                builder: (context, constraints) {
                  final isNarrow = constraints.maxWidth < 360;
                  final cardSpacing = isNarrow ? DesignSystem.spacingXS : DesignSystem.spacingSM;
                  final cardPadding = isNarrow ? DesignSystem.spacingSM : DesignSystem.spacingMD;
                  final titleSize = isNarrow ? 10.0 : 11.0;
                  final valueSize = isNarrow ? 20.0 : 24.0;
                  
                  return Row(
                    children: [
                      Expanded(
                        child: GlassCard(
                          padding: EdgeInsets.all(cardPadding),
                          borderRadius: DesignSystem.radiusCard,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                context.tr('stats.metric.todayJaps'),
                                style: TextStyle(
                                  fontSize: titleSize,
                                  fontWeight: FontWeight.w600,
                                  color: Theme.of(context).colorScheme.onSurface,
                                  letterSpacing: 0.2,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              SizedBox(height: isNarrow ? 6 : 8),
                              FittedBox(
                                fit: BoxFit.scaleDown,
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  todayJapsFromCounter.toString(),
                                  style: TextStyle(
                                    fontSize: valueSize,
                                    fontWeight: FontWeight.bold,
                                    color: Theme.of(context).colorScheme.onSurface,
                                    letterSpacing: -0.5,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      SizedBox(width: cardSpacing),
                      Expanded(
                        child: GlassCard(
                          padding: EdgeInsets.all(cardPadding),
                          borderRadius: DesignSystem.radiusCard,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                context.tr('stats.metric.todayMalas'),
                                style: TextStyle(
                                  fontSize: titleSize,
                                  fontWeight: FontWeight.w600,
                                  color: Theme.of(context).colorScheme.onSurface,
                                  letterSpacing: 0.2,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              SizedBox(height: isNarrow ? 6 : 8),
                              FittedBox(
                                fit: BoxFit.scaleDown,
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  todayMalasFromCounter.toString(),
                                  style: TextStyle(
                                    fontSize: valueSize,
                                    fontWeight: FontWeight.bold,
                                    color: Theme.of(context).colorScheme.onSurface,
                                    letterSpacing: -0.5,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      SizedBox(width: cardSpacing),
                      Expanded(
                        child: GlassCard(
                          padding: EdgeInsets.all(cardPadding),
                          borderRadius: DesignSystem.radiusCard,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                context.tr('stats.metric.lifetimeMalas'),
                                style: TextStyle(
                                  fontSize: titleSize,
                                  fontWeight: FontWeight.w600,
                                  color: Theme.of(context).colorScheme.onSurface,
                                  letterSpacing: 0.2,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              SizedBox(height: isNarrow ? 6 : 8),
                              FittedBox(
                                fit: BoxFit.scaleDown,
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  lifetimeMalasFromCounter.toString(),
                                  style: TextStyle(
                                    fontSize: valueSize,
                                    fontWeight: FontWeight.bold,
                                    color: Theme.of(context).colorScheme.onSurface,
                                    letterSpacing: -0.5,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 16),
              LayoutBuilder(
                builder: (context, constraints) {
                  final isNarrow = constraints.maxWidth < 360;
                  final cardSpacing = isNarrow ? DesignSystem.spacingXS : DesignSystem.spacingSM;
                  final cardPadding = isNarrow ? DesignSystem.spacingSM : DesignSystem.spacingMD;
                  final titleSize = isNarrow ? 10.0 : 11.0;
                  final valueSize = isNarrow ? 20.0 : 24.0;
                  
                  return Row(
                    children: [
                      Expanded(
                        child: GlassCard(
                          padding: EdgeInsets.all(cardPadding),
                          borderRadius: DesignSystem.radiusCard,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                context.tr('stats.metric.todayMeditation'),
                                style: TextStyle(
                                  fontSize: titleSize,
                                  fontWeight: FontWeight.w600,
                                  color: Theme.of(context).colorScheme.onSurface,
                                  letterSpacing: 0.2,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              SizedBox(height: isNarrow ? 6 : 8),
                              ValueListenableBuilder<int>(
                                valueListenable: _todayMinNotifier,
                                builder: (_, todayMin, __) => FittedBox(
                                  fit: BoxFit.scaleDown,
                                  alignment: Alignment.centerLeft,
                                  child: Text(
                                    todayMin.toString(),
                                    style: TextStyle(
                                      fontSize: valueSize,
                                      fontWeight: FontWeight.bold,
                                      color: Theme.of(context).colorScheme.onSurface,
                                      letterSpacing: -0.5,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      SizedBox(width: cardSpacing),
                      Expanded(
                        child: GlassCard(
                          padding: EdgeInsets.all(cardPadding),
                          borderRadius: DesignSystem.radiusCard,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                context.tr('stats.metric.lifetimeMeditation'),
                                style: TextStyle(
                                  fontSize: titleSize,
                                  fontWeight: FontWeight.w600,
                                  color: Theme.of(context).colorScheme.onSurface,
                                  letterSpacing: 0.2,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              SizedBox(height: isNarrow ? 6 : 8),
                              ValueListenableBuilder<int>(
                                valueListenable: _lifetimeMinNotifier,
                                builder: (_, lifetimeMin, __) => FittedBox(
                                  fit: BoxFit.scaleDown,
                                  alignment: Alignment.centerLeft,
                                  child: Text(
                                    lifetimeMin.toString(),
                                    style: TextStyle(
                                      fontSize: valueSize,
                                      fontWeight: FontWeight.bold,
                                      color: Theme.of(context).colorScheme.onSurface,
                                      letterSpacing: -0.5,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 16),
              Builder(
                builder: (context) {
                  final reached = todayMalasFromCounter >= goal;
                  return GlassCard(
                    padding: const EdgeInsets.all(12),
                    borderRadius: 12,
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
              const SizedBox(height: 8), // Minimal spacing between daily goal and 7-day progress bars
              Builder(
                builder: (context) {
                  if (chart.isEmpty) return const SizedBox.shrink();
                  final theme = Theme.of(context);
                  final maxMalas = chart.fold<int>(0, (prev, element) {
                    final val = element['value'] as int? ?? 0;
                    return val > prev ? val : prev;
                  });
                  final safeMax = maxMalas == 0 ? 1 : maxMalas;

                  return GlassCard(
                    padding: const EdgeInsets.all(12),
                    borderRadius: 12,
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
                                  children: List.generate(chart.length, (index) {
                                    final e = chart[index];
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
                                            color: theme.colorScheme
                                                .surfaceContainerHighest
                                                .withValues(alpha: 0.7),
                                            borderRadius:
                                                BorderRadius.circular(8),
                                          ),
                                          child: Text(
                                            '$val',
                                            style: theme.textTheme.labelSmall?.copyWith(
                                              fontWeight: FontWeight.w700,
                                              fontSize: 11,
                                              color: Theme.of(context).colorScheme.onSurface, // Explicit dark color
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
                                            color: Theme.of(context).colorScheme.onSurface, // Explicit dark color
                                          ),
                                          textAlign: TextAlign.center,
                                        ),
                                        Text(
                                          dateLabel,
                                          style: theme.textTheme.labelSmall?.copyWith(
                                            fontSize: 10,
                                            color: const Color(0xFF666666), // Explicit dark color
                                          ),
                                          textAlign: TextAlign.center,
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              }),
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
                    child: GlassCard(
                      padding: const EdgeInsets.all(12),
                      borderRadius: 12,
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
                            // CRITICAL FIX: Force sync and fetch fresh data from CounterStore to avoid stale cache
                            // This ensures we get the absolute latest value, not from cached FutureBuilder
                            final s = await CounterStore.create();
                            // Force sync any pending writes to ensure we have the latest value
                            await s.forceSyncNow();
                            // Read fresh value from store (after sync, cache should be up-to-date)
                            final int todayJaps = s.todayJaps; // Read from store after ensuring sync
                            final int lifetimeMalasLocal = s.lifetimeMalas; // Fetch fresh from store
                            final int streakDays = streak;
                            debugPrint(
                              '[Stats] Share tapped → todayJaps=$todayJaps (fresh from store after sync) lifetimeMalas=$lifetimeMalasLocal streakDays=$streakDays',
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
                    // CRITICAL FIX: Force sync and fetch fresh data from CounterStore to avoid stale cache
                    // This ensures we get the absolute latest value, not from cached FutureBuilder
                    final s = await CounterStore.create();
                    // Force sync any pending writes to ensure we have the latest value
                    await s.forceSyncNow();
                    // Read fresh value from store (after sync, cache should be up-to-date)
                    final int todayJaps = s.todayJaps; // Read from store after ensuring sync
                    final int lifetimeMalasLocal = s.lifetimeMalas; // Fetch fresh from store
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
              _ActivityCalendar(todayJaps: _todayNotifier.value, todayMalas: todayMalas),
            ]),
          ),
        ),
      ],
    );
      },
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
                                              color: Theme.of(context).colorScheme.onSurface,
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
      base = DesignSystem.buttonPrimary.withValues(alpha: 0.5); // Soothing color
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
    return isCurrentMonth
        ? base
        : base.withValues(alpha: 0.45);
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
                Text(
                  titleLabel,
                  style: theme.textTheme.titleSmall?.copyWith(
                                              color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  context.tr(
                    'stats.calendar.summary',
                    args: {'malas': '${entry.malas}', 'japs': '${entry.japs}'},
                  ),
                  style: theme.textTheme.bodySmall?.copyWith(
                                              color: Theme.of(context).colorScheme.onSurface,
                  ),
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
    super.key,
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
        : theme.dividerColor.withValues(
            alpha: isCurrentMonth ? 1 : 0.4,
          );
    // If malas > 0 (has color fill), use black text. Otherwise use theme color
    final hasColorFill = malas > 0;
    final textColor = hasColorFill
        ? Colors.black // Black text when there's a color fill
        : (isCurrentMonth
            ? theme.colorScheme.onSurface
            : theme.colorScheme.onSurfaceVariant); // Lighter color for other months

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

  const _LegendSwatch({super.key, required this.color, required this.label});

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
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
                                              color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
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

