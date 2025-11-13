import 'dart:async' show unawaited, Timer;

import 'package:audioplayers/audioplayers.dart';
import 'package:confetti/confetti.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/ad_manager.dart';
import '../core/prefs_manager.dart';
import '../data/activity_store.dart';
import '../data/counter_store.dart';
import '../data/dedication_store.dart';
import '../data/goal_store.dart';
import '../data/insight_store.dart';
import '../data/session_store.dart';
import '../gamify/gamify_store.dart';
import '../l10n/app_localizations.dart';
import '../notifications/notification_service.dart';
import '../theme/glow_theme.dart';
import '../utils/weekly_chart_data.dart';

class CounterPage extends StatefulWidget {
  const CounterPage({super.key});

  @override
  State<CounterPage> createState() => _CounterPageState();
}

class _CounterPageState extends State<CounterPage> with WidgetsBindingObserver {
  CounterStore? _store;
  bool _loading = true;
  int _today = 0;
  int _lifetime = 0;
  bool _pulse = false;
  int _dailyGoal = 0;
  bool _goalCompletedShown = false;
  DateTime _lastTapTime = DateTime.fromMillisecondsSinceEpoch(0);
  bool _soundEnabled = true;
  AudioPlayer? _bellPlayer;
  late final ConfettiController _confettiController;
  bool _confettiShownRecently = false;
  bool _glowActive = false;
  int _currentMalaCountDisplay = 0;
  Timer? _malaResetTimer;

  @override
  void initState() {
    super.initState();
    // Listen for app going to background
    WidgetsBinding.instance.addObserver(this);
    _confettiController = ConfettiController(
      duration: const Duration(seconds: 3),
    );
    // Create AudioPlayer once for reuse
    _bellPlayer = AudioPlayer();
    // Pause ad preloading during counter session
    AdManager.instance.onCounterSessionStart();
    _init();
  }
  
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      // App going to background - force sync
      _store?.forceSyncNow();
    }
  }

  Future<void> _init() async {
    final store = await CounterStore.create();
    final goalStore = await GoalStore.create();
    final prefs = await PrefsManager.instance;

    final congratulatedToday =
        goalStore.lastCongratsDate == GoalStore.todayKey();

    setState(() {
      _store = store;
      _today = store.todayJaps;
      _lifetime = store.lifetimeJaps;
      _dailyGoal = goalStore.dailyMalasGoal;
      _goalCompletedShown = congratulatedToday;
      _soundEnabled = prefs.getBool('settings.soundEnabled') ?? true;
      _currentMalaCountDisplay = _calculateCurrentMalaDisplay(store.todayJaps);
      _loading = false;
    });
  }

  Future<void> _handleJapTap() async {
    if (_loading || _store == null) return;
    final now = DateTime.now();
    if (now.difference(_lastTapTime) < const Duration(milliseconds: 200)) {
      return;
    }
    _lastTapTime = now;
    try {
      await HapticFeedback.lightImpact();
    } catch (_) {}
    _triggerPulse();
    setState(() => _glowActive = true);
    Future.delayed(const Duration(milliseconds: 300), () {
      if (mounted) setState(() => _glowActive = false);
    });
    await _incrementJap();

    if (_today > 0 && _today % 108 == 0) {
      if (_soundEnabled) {
        try {
          await _bellPlayer!.play(AssetSource('audio/bell_end.mp3'));
        } catch (e) {
          debugPrint('[Counter] Bell play failed: $e');
        }
      }
      _triggerConfetti();
      await ActivityStore.recordDailySummary(_today, _today ~/ 108);
      // Invalidate chart cache when counter increments
      unawaited(_invalidateChartCache());
    }
  }

  void _triggerPulse() {
    setState(() => _pulse = true);
    Future.delayed(const Duration(milliseconds: 220), () {
      if (mounted) setState(() => _pulse = false);
    });
  }

  Future<void> _incrementJap() async {
    final store = _store;
    if (store == null) return;

    _cancelMalaResetTimer();
    final wasZero = _today == 0;
    final willBe = _today + 1;
    
    // Critical: Update counter immediately
    await store.increment();

    // Invalidate chart cache when counter increments
    unawaited(_invalidateChartCache());

    // Update UI immediately for responsiveness
    final updatedToday = store.todayJaps;
    final remainder = updatedToday % 108;
    final malaCompleted = remainder == 0 && updatedToday > 0;

    if (!mounted) return;
    setState(() {
      _today = updatedToday;
      _lifetime = store.lifetimeJaps;
      _currentMalaCountDisplay = malaCompleted ? 108 : remainder;
    });

    // Non-critical operations: Fire and forget
    unawaited(_recordInsight(willBe));
    
    if (wasZero) {
      unawaited(ActivityStore.markTodayActive());
      unawaited(_handleStreakMilestones(context, showSnackBar: true));
    }

    if (malaCompleted) {
      _scheduleMalaReset();
      // Check for streak milestones when completing a mala
      unawaited(_handleStreakMilestones(context, showSnackBar: false));
      try {
        HapticFeedback.mediumImpact();
      } catch (_) {}
      _triggerPulse();
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: Text(context.tr('counter.malaCompleted')),
              duration: const Duration(seconds: 3),
              behavior: SnackBarBehavior.floating,
            ),
          );
      }
      unawaited(_recordSession(willBe));
    }

    // Check goal completion (can be async but should complete)
    unawaited(_checkGoalCompletion());

    // Schedule notification reminder (non-blocking)
    unawaited(_scheduleNotification());
  }
  
  Future<void> _invalidateChartCache() async {
    // Invalidate chart cache when counter increments
    WeeklyChartData.invalidateCache();
  }

  Future<void> _recordInsight(int willBe) async {
    try {
      final insights = await InsightStore.create();
      await insights.recordJap(count: 1, malas: willBe % 108 == 0 ? 1 : 0);
    } catch (e) {
      debugPrint('[Insights] Record failed: $e');
    }
  }

  Future<void> _recordSession(int count) async {
    try {
      final sessions = await SessionStore.create();
      await sessions.addSession(type: 'jap', count: count);
    } catch (_) {}
  }

  Future<void> _scheduleNotification() async {
    try {
      final ns = NotificationService();
      final scope = AppLocalizationScope.maybeOf(context);
      final language = scope?.language ?? 'en';
      await ns.scheduleDynamicJapReminder(_today, language: language);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[Counter] Notification scheduling failed: $e');
      }
    }
  }

  Future<void> _checkGoalCompletion() async {
    final goalStore = await GoalStore.create();
    if (!_goalCompletedShown && _dailyGoal > 0 && _malas >= _dailyGoal) {
      _goalCompletedShown = true;
      await goalStore.setLastCongratsToday();
      if (!mounted) return;
      await _showGoalCompleteDialog();
    }
  }

  Future<void> _showGoalCompleteDialog() async {
    if (!mounted) return;
    final scope = AppLocalizationScope.maybeOf(context);
    final language = scope?.language ?? 'en';
    final suffix = language == 'hi'
        ? (_dailyGoal == 1 ? '' : 'एँ')
        : (_dailyGoal == 1 ? '' : 's');
    
    // Safe translation helper
    String safeTr(String key, {Map<String, String>? args}) {
      if (scope != null) {
        return context.tr(key, args: args);
      }
      var value = AppStrings.resolve(language, key);
      if (args != null) {
        args.forEach((k, v) {
          value = value.replaceAll('{$k}', v);
        });
      }
      return value;
    }
    
    await showDialog(
      context: context,
      builder: (ctx) {
        final dialogScope = AppLocalizationScope.maybeOf(ctx);
        final dialogLanguage = dialogScope?.language ?? language;
        
        String dialogSafeTr(String key, {Map<String, String>? args}) {
          if (dialogScope != null) {
            return ctx.tr(key, args: args);
          }
          var value = AppStrings.resolve(dialogLanguage, key);
          if (args != null) {
            args.forEach((k, v) {
              value = value.replaceAll('{$k}', v);
            });
          }
          return value;
        }
        
        return AlertDialog(
          title: Text(dialogSafeTr('counter.goal.complete.title')),
          content: Text(
            dialogSafeTr(
              'counter.goal.complete.message',
              args: {'count': '$_dailyGoal', 'suffix': suffix},
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(dialogSafeTr('common.ok')),
            ),
          ],
        );
      },
    );
  }

  void _triggerConfetti() {
    if (_confettiShownRecently) return;
    _confettiShownRecently = true;
    _confettiController.play();
    Future.delayed(const Duration(milliseconds: 1500), () {
      if (mounted) _confettiController.stop();
      _confettiShownRecently = false;
    });
  }

  void _scheduleMalaReset() {
    _cancelMalaResetTimer();
    _malaResetTimer = Timer(const Duration(milliseconds: 900), () {
      if (!mounted) return;
      setState(() {
        _currentMalaCountDisplay = 0;
      });
    });
  }

  void _cancelMalaResetTimer() {
    _malaResetTimer?.cancel();
    _malaResetTimer = null;
  }

  int _calculateCurrentMalaDisplay(int todayJaps) {
    final remainder = todayJaps % 108;
    if (remainder == 0 && todayJaps > 0) {
      return 0;
    }
    return remainder;
  }

  int get _malas => _today ~/ 108;
  int get _lifetimeMalas => _lifetime ~/ 108;
  double get _goalProgress {
    if (_dailyGoal <= 0) return 0;
    return (_malas / _dailyGoal).clamp(0, 1).toDouble();
  }

  /// Handles streak milestone checks and celebrations.
  /// Extracted to avoid code duplication.
  Future<void> _handleStreakMilestones(
    BuildContext context, {
    required bool showSnackBar,
  }) async {
    try {
      final streak = await ActivityStore.currentStreak();
      if (!mounted) return;
      
      if (streak == 7 || streak == 21 || streak == 40) {
        try {
          await GamifyStore.awardBadge('streak_$streak');
        } catch (_) {}
        
        if (showSnackBar) {
          try {
            HapticFeedback.mediumImpact();
          } catch (_) {}
          try {
            // _bellPlayer is already initialized in initState
            await _bellPlayer!.play(AssetSource('audio/bell_end.mp3'));
          } catch (_) {}
          if (mounted) {
            ScaffoldMessenger.of(context)
              ..hideCurrentSnackBar()
              ..showSnackBar(
                SnackBar(
                  content: Text(context.tr('counter.streak.milestone', args: {'days': '$streak'})),
                  behavior: SnackBarBehavior.floating,
                  duration: const Duration(seconds: 3),
                ),
              );
          }
        } else {
          // When completing a mala, update dedication note
          try {
            final dedicationStore = await DedicationStore.create();
            final scope = AppLocalizationScope.maybeOf(context);
            final language = scope?.language ?? 'en';
            final note = AppStrings.resolve(language, 'counter.streak.dedication')
                .replaceAll('{days}', '$streak');
            await dedicationStore.setNote(note);
          } catch (_) {}
        }
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[Counter] Streak milestone check failed: $e');
      }
    }
  }

  Future<void> _editGoal() async {
    // Get language from outer context before showing dialog
    final scope = AppLocalizationScope.maybeOf(context);
    final language = scope?.language ?? 'en';
    
    final result = await showDialog<int>(
      context: context,
      builder: (ctx) {
        int sliderValue = _dailyGoal.clamp(0, 50);
        return StatefulBuilder(
          builder: (dialogContext, setLocalState) {
            // Use outer context's language or fallback
            final dialogScope = AppLocalizationScope.maybeOf(dialogContext);
            final dialogLanguage = dialogScope?.language ?? language;
            final suffix = dialogLanguage == 'hi'
                ? (sliderValue == 1 ? '' : 'एँ')
                : (sliderValue == 1 ? '' : 's');
            
            // Safe translation helper
            String safeTr(String key, {Map<String, String>? args}) {
              if (dialogScope != null) {
                return dialogContext.tr(key, args: args);
              }
              var value = AppStrings.resolve(dialogLanguage, key);
              if (args != null) {
                args.forEach((k, v) {
                  value = value.replaceAll('{$k}', v);
                });
              }
              return value;
            }
            
            final goalText = sliderValue == 0
                ? safeTr('counter.goal.dialog.noGoal')
                : safeTr('counter.goal.dialog.goalText', args: {'count': '$sliderValue', 'suffix': suffix});
            
            return AlertDialog(
              title: Text(safeTr('counter.goal.dialog.title')),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    goalText,
                    textAlign: TextAlign.center,
                    style: Theme.of(dialogContext).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                  const SizedBox(height: 12),
                  Slider(
                    value: sliderValue.toDouble(),
                    min: 0,
                    max: 50,
                    divisions: 50,
                    label: sliderValue.toString(),
                    onChanged: (value) {
                      setLocalState(() => sliderValue = value.round());
                    },
                  ),
                  const SizedBox(height: 6),
                  Text(
                    safeTr('counter.goal.dialog.hint'),
                    textAlign: TextAlign.center,
                    style: Theme.of(dialogContext)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: Theme.of(dialogContext).hintColor),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: Text(safeTr('common.cancel')),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(ctx, sliderValue),
                  child: Text(safeTr('common.save')),
                ),
              ],
            );
          },
        );
      },
    );
    if (result != null) {
      final sanitized = result.clamp(0, 50);
      setState(() {
        _dailyGoal = sanitized;
        _goalCompletedShown = _dailyGoal > 0 && _malas >= _dailyGoal;
      });
      final goalStore = await GoalStore.create();
      await goalStore.setDailyMalasGoal(sanitized);
      if (_dailyGoal == 0) {
        await goalStore.setLastCongratsToday();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Counter'),
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
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final theme = Theme.of(context);
    final isLight = theme.brightness == Brightness.light;
    final gradientColors = isLight
        ? [Colors.pink.shade50, Colors.white]
        : [Colors.deepPurple.shade900, Colors.amber.shade100];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Counter'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                theme.colorScheme.primary.withOpacity(0.3),
                Colors.transparent,
              ],
            ),
          ),
        ),
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: gradientColors,
          ),
        ),
        child: Stack(
          children: [
            Positioned.fill(
              child: IgnorePointer(
                child: Center(
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 400),
                    opacity: _glowActive ? 0.1 : 0.05,
                    child: Text(
                      'राधे राधे',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 120,
                        fontWeight: FontWeight.w800,
                        color: theme.colorScheme.primary.withOpacity(0.06),
                        fontFamily: 'Noto Sans Devanagari',
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Align(
              alignment: Alignment.topCenter,
              child: ConfettiWidget(
                confettiController: _confettiController,
                blastDirectionality: BlastDirectionality.explosive,
                particleDrag: 0.05,
                emissionFrequency: 0.05,
                numberOfParticles: 15,
                maxBlastForce: 10,
                minBlastForce: 5,
                gravity: 0.3,
                shouldLoop: false,
                colors: const [
                  Colors.orange,
                  Colors.pink,
                  Colors.purple,
                ],
              ),
            ),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _handleJapTap,
              child: SafeArea(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final screenHeight = constraints.maxHeight;
                    final isSmallScreen = screenHeight < 600;
                    
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const SizedBox(height: 16),
                        RepaintBoundary(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            child: Row(
                              children: [
                                Expanded(
                                  child: _StatTile(
                                    title: "Today's Japs",
                                    value: _today.toString(),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: _StatTile(
                                    title: "Malas",
                                    value: _malas.toString(),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: _StatTile(
                                    title: "Lifetime Malas",
                                    value: _lifetimeMalas.toString(),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        SizedBox(height: isSmallScreen ? 12 : 24),
                        RepaintBoundary(
                          child: _GoalSummary(
                            dailyGoal: _dailyGoal,
                            goalProgress: _goalProgress,
                            goalCompletedShown: _goalCompletedShown,
                            malas: _malas,
                            onEditGoal: _editGoal,
                          ),
                        ),
                        Expanded(
                          child: Center(
                            child: SingleChildScrollView(
                              physics: const NeverScrollableScrollPhysics(),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Text(
                                    'Tap to Count',
                                    style: TextStyle(fontSize: 18),
                                  ),
                                  SizedBox(height: isSmallScreen ? 12 : 16), // Cannot be const due to conditional
                                  RepaintBoundary(
                                    child: _CounterButton(
                                      today: _today,
                                      pulse: _pulse,
                                      currentMalaCount: _currentMalaCountDisplay,
                                      malasCompleted: _malas,
                                      isSmallScreen: isSmallScreen,
                                    ),
                                  ),
                                  SizedBox(height: MediaQuery.of(context).padding.bottom + 16),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    // Force sync before disposal
    _store?.forceSyncNow();
    // Resume ad preloading when counter session ends
    AdManager.instance.onCounterSessionEnd();
    _confettiController.dispose();
    _bellPlayer?.dispose();
    _cancelMalaResetTimer();
    super.dispose();
  }
}

class _StatTile extends StatelessWidget {
  final String title;
  final String value;
  const _StatTile({required this.title, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 60, maxHeight: 68),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(
              title,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                fontSize: 10,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const Spacer(),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CounterButton extends StatelessWidget {
  final int today;
  final bool pulse;
  final int currentMalaCount;
  final int malasCompleted;
  final bool isSmallScreen;

  const _CounterButton({
    required this.today,
    required this.pulse,
    required this.currentMalaCount,
    required this.malasCompleted,
    required this.isSmallScreen,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedScale(
          scale: pulse ? 1.08 : 1.0,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final maxSize = constraints.maxWidth < constraints.maxHeight
                  ? constraints.maxWidth * 0.6
                  : constraints.maxHeight * 0.4;
              final circleSize = (maxSize.clamp(180.0, 240.0));
              
              return Container(
                height: circleSize,
                width: circleSize,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      theme.colorScheme.primary.withOpacity(0.25),
                      theme.colorScheme.surface,
                    ],
                    radius: 0.85,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: theme.colorScheme.primary.withOpacity(0.3),
                      blurRadius: 30,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: Center(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Text(
                        '$today',
                        style: theme.textTheme.displayLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                          foreground: Paint()
                            ..shader = GlowTheme.linearGradient(context),
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        SizedBox(height: isSmallScreen ? 12 : 20), // Cannot be const due to conditional
        _MalaProgressDisplay(
          currentMalaCount: currentMalaCount,
          malasCompleted: malasCompleted,
        ),
      ],
    );
  }
}

class _MalaProgressDisplay extends StatelessWidget {
  final int currentMalaCount;
  final int malasCompleted;
  const _MalaProgressDisplay({
    required this.currentMalaCount,
    required this.malasCompleted,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final normalized = currentMalaCount.clamp(0, 108).toInt();
    final primaryLabelStyle = theme.textTheme.titleSmall?.copyWith(
      fontWeight: FontWeight.w700,
      letterSpacing: 0.2,
    );
    final captionStyle = theme.textTheme.bodySmall?.copyWith(
      color: theme.textTheme.bodySmall?.color?.withOpacity(0.6),
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '$normalized / 108',
          style: primaryLabelStyle,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 4),
        Text(
          'Malas completed: $malasCompleted',
          style: captionStyle ?? theme.textTheme.bodySmall,
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

class _GoalSummary extends StatelessWidget {
  final int dailyGoal;
  final double goalProgress;
  final bool goalCompletedShown;
  final int malas;
  final VoidCallback onEditGoal;

  const _GoalSummary({
    required this.dailyGoal,
    required this.goalProgress,
    required this.goalCompletedShown,
    required this.malas,
    required this.onEditGoal,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scope = AppLocalizationScope.maybeOf(context);
    // Use default language if scope is not available (shouldn't happen normally)
    final language = scope?.language ?? 'en';
    final suffix = language == 'hi'
        ? (dailyGoal == 1 ? '' : 'एँ')
        : (dailyGoal == 1 ? '' : 's');
    
    // Helper function to safely resolve translations
    String safeTr(String key, {Map<String, String>? args}) {
      if (scope != null) {
        return context.tr(key, args: args);
      }
      var value = AppStrings.resolve(language, key);
      if (args != null) {
        args.forEach((k, v) {
          value = value.replaceAll('{$k}', v);
        });
      }
      return value;
    }
    
    final goalLabel = dailyGoal == 0
        ? safeTr('counter.goal.cta')
        : safeTr(
            'counter.goal.label',
            args: {'count': '$dailyGoal', 'suffix': suffix},
          );

    String statusKey;
    Map<String, String>? statusArgs;
    if (dailyGoal <= 0) {
      statusKey = 'counter.goal.status.none';
    } else if (goalCompletedShown) {
      statusKey = 'counter.goal.status.met';
    } else {
      statusKey = 'counter.goal.status.progress';
      statusArgs = {'malas': '$malas', 'goal': '$dailyGoal', 'suffix': suffix};
    }
    final statusText = safeTr(statusKey, args: statusArgs);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Material(
        color: theme.colorScheme.surface.withOpacity(0.95),
        elevation: 1,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onEditGoal,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary.withOpacity(0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.flag_rounded,
                    color: theme.colorScheme.primary,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: Text(
                          goalLabel,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Flexible(
                        child: Text(
                          statusText,
                          style: theme.textTheme.bodySmall?.copyWith(fontSize: 11),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(height: 6),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(999),
                        child: LinearProgressIndicator(
                          value: goalProgress,
                          minHeight: 5,
                          backgroundColor: theme.colorScheme.primary
                              .withOpacity(0.08),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  Icons.edit_outlined,
                  color: theme.colorScheme.primary,
                  size: 18,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
