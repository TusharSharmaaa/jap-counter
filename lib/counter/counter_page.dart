import 'dart:async' show unawaited, Timer;
import 'dart:ui' as ui;

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
import '../theme/design_system.dart';
import '../utils/weekly_chart_data.dart';
import '../widgets/widgets.dart';
import 'tap_feedback_controller.dart';
import '../data/tap_feedback_settings.dart';

class CounterPage extends StatefulWidget {
  const CounterPage({super.key});

  @override
  State<CounterPage> createState() => CounterPageState();
}

class CounterPageState extends State<CounterPage> with WidgetsBindingObserver {
  CounterStore? _store;
  bool _loading = true;
  int _lifetime = 0;
  bool _pulse = false;
  int _dailyGoal = 0;
  bool _goalCompletedShown = false;
  late final ConfettiController _confettiController;
  bool _confettiShownRecently = false;
  bool _glowActive = false;
  Timer? _malaResetTimer;
  DateTime? _lastGoalRefresh;
  
  // Performance optimization: Use ValueNotifier for frequently updated values
  // This avoids rebuilding the entire widget tree on every tap
  late final ValueNotifier<int> _todayNotifier;
  late final ValueNotifier<int> _lifetimeMalasNotifier;
  late final ValueNotifier<int> _currentMalaCountNotifier;

  @override
  void initState() {
    super.initState();
    // Initialize ValueNotifiers for performance optimization
    _todayNotifier = ValueNotifier<int>(0);
    _lifetimeMalasNotifier = ValueNotifier<int>(0);
    _currentMalaCountNotifier = ValueNotifier<int>(0);
    
    // Listen for app going to background
    WidgetsBinding.instance.addObserver(this);
    _confettiController = ConfettiController(
      duration: const Duration(seconds: 3),
    );
    // Initialize tap feedback controller
    unawaited(_initFeedbackController());
    // Pause ad preloading during counter session
    AdManager.instance.onCounterSessionStart();
    _init();
  }
  
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      // App going to background - force sync and flush pending writes
      _store?.forceSyncNow();
      unawaited(ActivityStore.flushPendingWrites());
    } else if (state == AppLifecycleState.resumed) {
      // App resumed - refresh goal to sync with any changes from settings
      unawaited(_refreshGoal());
    }
  }
  
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Refresh goal when page becomes visible (e.g., navigating back from settings)
    // This ensures goal is always in sync with settings
    // Throttle refreshes to avoid excessive calls
    final now = DateTime.now();
    if (_lastGoalRefresh == null || 
        now.difference(_lastGoalRefresh!) > const Duration(seconds: 1)) {
      _lastGoalRefresh = now;
      unawaited(_refreshGoal());
    }
  }

  Future<void> _initFeedbackController() async {
    final settings = await TapFeedbackSettings.load();
    await TapFeedbackController.instance.initialize(settings);
  }

  Future<void> _init() async {
    final store = await CounterStore.create();
    final goalStore = await GoalStore.create();

    // Update ValueNotifiers instead of setState for frequently changing values
    _todayNotifier.value = store.todayJaps;
    _lifetimeMalasNotifier.value = store.lifetimeMalas;
    _currentMalaCountNotifier.value = _calculateCurrentMalaDisplay(store.todayJaps);
    
    setState(() {
      _store = store;
      _lifetime = store.lifetimeJaps;
      _dailyGoal = goalStore.dailyMalasGoal;
      _loading = false;
    });
    
    // Recalculate goal completion status after setting goal
    await _refreshGoalStatus();
  }
  
  /// Public method to refresh goal when returning from settings
  /// This is called from app.dart when navigating back from settings tab
  Future<void> refreshGoalFromSettings() async {
    // Force refresh without throttling when coming from settings
    _lastGoalRefresh = null;
    await _refreshGoal();
  }
  
  /// Refresh goal from store and recalculate completion status
  /// This ensures goal is always in sync with settings
  Future<void> _refreshGoal() async {
    if (_store == null) return;
    
    final goalStore = await GoalStore.create();
    final currentGoal = goalStore.dailyMalasGoal;
    final oldGoal = _dailyGoal;
    
    if (mounted && _dailyGoal != currentGoal) {
      setState(() {
        _dailyGoal = currentGoal;
      });
      
      // If goal is increased and user hasn't met the new goal yet,
      // clear the congrats date so status recalculates correctly
      // This ensures "goal met" status is cleared when goal increases beyond current progress
      if (currentGoal > oldGoal && oldGoal > 0) {
        final currentMalas = _malas;
        if (currentMalas < currentGoal) {
          // User hasn't met the new goal yet, so clear congrats date
          // This will reset the "goal met" status until they meet the new goal
          await goalStore.clearLastCongrats();
        }
      }
      
      // Recalculate goal completion status when goal changes
      await _refreshGoalStatus();
    } else if (mounted) {
      // Even if goal hasn't changed, refresh status to ensure it's accurate
      await _refreshGoalStatus();
    }
  }
  
  /// Recalculate goal completion status based on current malas and goal
  /// This ensures the status is accurate even when goal is updated
  Future<void> _refreshGoalStatus() async {
    if (_store == null) return;
    
    final goalStore = await GoalStore.create();
    final currentMalas = _malas;
    final currentGoal = _dailyGoal;
    
    // Check if goal was already congratulated today
    final congratulatedToday =
        goalStore.lastCongratsDate == GoalStore.todayKey();
    
    // CRITICAL: Recalculate goal completion status correctly
    // Goal is met ONLY if:
    // 1. Goal is set (> 0)
    // 2. Current malas >= current goal (not the old goal)
    // 3. We have already congratulated today (meaning we showed the dialog)
    // 
    // If goal is updated to a higher value and user hasn't met the new goal yet,
    // we should NOT show "goal met" even if they met the old goal
    final goalMet = currentGoal > 0 && currentMalas >= currentGoal;
    final shouldShowCompleted = goalMet && congratulatedToday;
    
    if (mounted && _goalCompletedShown != shouldShowCompleted) {
      setState(() {
        _goalCompletedShown = shouldShowCompleted;
      });
    }
  }

  Future<void> _handleJapTap() async {
    if (_loading || _store == null) return;
    
    // Trigger pulse and glow immediately for responsiveness
    _triggerPulse();
    setState(() => _glowActive = true);
    Future.delayed(const Duration(milliseconds: 300), () {
      if (mounted) setState(() => _glowActive = false);
    });
    
    await _incrementJap();
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
    final wasZero = _todayNotifier.value == 0;
    final willBe = _todayNotifier.value + 1;
    
    // Critical: Update counter immediately
    await store.increment();

    // Invalidate chart cache when counter increments
    unawaited(_invalidateChartCache());

    // Update UI immediately for responsiveness using ValueNotifiers
    // This avoids rebuilding the entire widget tree
    final updatedToday = store.todayJaps;
    final remainder = updatedToday % 108;
    final malaCompleted = remainder == 0 && updatedToday > 0;

    // Update ValueNotifiers - only rebuilds widgets listening to these values
    _todayNotifier.value = updatedToday;
    _lifetimeMalasNotifier.value = store.lifetimeMalas;
    _currentMalaCountNotifier.value = malaCompleted ? 108 : remainder;
    
    // Only update lifetime in setState (rarely changes)
    if (mounted && _lifetime != store.lifetimeJaps) {
      setState(() {
        _lifetime = store.lifetimeJaps;
      });
    }

    // Trigger feedback via controller (handles debouncing and settings)
    unawaited(TapFeedbackController.instance.handleTap(
      currentCount: updatedToday,
      isMalaComplete: malaCompleted,
    ));

    // Non-critical operations: Fire and forget
    unawaited(_recordInsight(willBe));
    
    // Record daily summary - batched/deferred for performance
    // OPTIMIZATION: This now batches writes instead of writing on every tap
    unawaited(ActivityStore.recordDailySummary(updatedToday, updatedToday ~/ 108));
    
    // OPTIMIZATION: Don't refresh lifetime malas on every tap - it's cached and updated automatically
    // Only refresh when a mala is completed (when lifetime malas might change)
    if (malaCompleted) {
      unawaited(store.refreshLifetimeMalas().then((_) {
        if (mounted) {
          _lifetimeMalasNotifier.value = store.lifetimeMalas;
        }
      }));
    }
    
    if (wasZero) {
      unawaited(ActivityStore.markTodayActive());
      unawaited(_handleStreakMilestones(context, showSnackBar: true));
    }

    if (malaCompleted) {
      _scheduleMalaReset();
      // Check for streak milestones when completing a mala
      unawaited(_handleStreakMilestones(context, showSnackBar: false));
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
      _triggerConfetti();
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
      await ns.scheduleDynamicJapReminder(_todayNotifier.value, language: language);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[Counter] Notification scheduling failed: $e');
      }
    }
  }

  Future<void> _checkGoalCompletion() async {
    // First refresh goal to ensure we have the latest value
    await _refreshGoal();
    
    final goalStore = await GoalStore.create();
    final currentMalas = _malas;
    final currentGoal = _dailyGoal;
    
    // Check if goal is met and we haven't shown the dialog yet
    if (!_goalCompletedShown && currentGoal > 0 && currentMalas >= currentGoal) {
      await goalStore.setLastCongratsToday();
      if (!mounted) return;
      
      setState(() {
        _goalCompletedShown = true;
      });
      
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
          backgroundColor: Theme.of(ctx).colorScheme.surface,
          title: Text(
            dialogSafeTr('counter.goal.complete.title'),
            style: TextStyle(
              color: Theme.of(ctx).colorScheme.onSurface,
              fontWeight: FontWeight.bold,
            ),
          ),
          content: Text(
            dialogSafeTr(
              'counter.goal.complete.message',
              args: {'count': '$_dailyGoal', 'suffix': suffix},
            ),
            style: TextStyle(
              color: Theme.of(ctx).colorScheme.onSurface,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(
                dialogSafeTr('common.ok'),
                style: TextStyle(
                  color: Theme.of(ctx).colorScheme.onSurface,
                ),
              ),
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
      _currentMalaCountNotifier.value = 0;
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

  // Getter for malas - uses ValueNotifier value
  int get _malas => _todayNotifier.value ~/ 108;
  // Use stored lifetime malas (calculated from completed malas in history)
  // This ensures we only count COMPLETE malas (108 japs = 1 mala)
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
            // Use feedback controller for haptic/sound
            unawaited(TapFeedbackController.instance.handleTap(
              currentCount: _todayNotifier.value,
              isMalaComplete: false,
            ));
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
              title: Text(
                safeTr('counter.goal.dialog.title'),
                style: TextStyle(color: Theme.of(dialogContext).colorScheme.onSurface),
              ),
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
                        ?.copyWith(
                          color: Theme.of(dialogContext).brightness == Brightness.dark
                              ? Colors.white.withValues(alpha: 0.7) // Less white for visibility
                              : const Color(0xFF666666),
                        ),
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
      final goalStore = await GoalStore.create();
      final oldGoal = _dailyGoal;
      final currentMalas = _malas;
      
      await goalStore.setDailyMalasGoal(sanitized);
      
      // Update local state
      setState(() {
        _dailyGoal = sanitized;
      });
      
      // If goal is increased and user hasn't met the new goal yet,
      // clear the congrats date so status recalculates correctly
      if (sanitized > oldGoal && oldGoal > 0 && currentMalas < sanitized) {
        await goalStore.clearLastCongrats();
      }
      
      // If goal is set to 0, clear congrats to reset the status
      if (sanitized == 0) {
        await goalStore.clearLastCongrats();
        if (mounted) {
          setState(() {
            _goalCompletedShown = false;
          });
        }
      }
      
      // Recalculate goal completion status after updating goal
      await _refreshGoalStatus();
    }
  }

  @override
  Widget build(BuildContext context) {
    // Refresh goal when page is built (throttled to avoid excessive calls)
    // This ensures goal is synced when navigating back from settings
    final now = DateTime.now();
    if (!_loading && _store != null && 
        (_lastGoalRefresh == null || 
         now.difference(_lastGoalRefresh!) > const Duration(seconds: 2))) {
      _lastGoalRefresh = now;
      unawaited(_refreshGoal());
    }
    
    if (_loading) {
      return Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        body: Container(
          decoration: BoxDecoration(
            color: Theme.of(context).scaffoldBackgroundColor,
          ),
          child: const Center(
            child: CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(DesignSystem.buttonPrimary),
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
        ),
        child: Stack(
          children: [
            // Subtle top highlight for premium feel
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.center,
                  colors: [
                    Theme.of(context).brightness == Brightness.dark
                        ? Colors.white.withValues(alpha: 0.05)
                        : Colors.white.withValues(alpha: 0.22),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
            // Background decorative text - reduced opacity for clarity
            Positioned.fill(
              child: IgnorePointer(
                child: Center(
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 400),
                    opacity: _glowActive ? 0.03 : 0.02,
                    child: Text(
                      'राधे राधे',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 120,
                        fontWeight: FontWeight.w800,
                        color: DesignSystem.buttonPrimary.withValues(alpha: 0.04),
                        fontFamily: 'Noto Sans Devanagari',
                      ),
                    ),
                  ),
                ),
              ),
            ),
            // Confetti overlay - only render when confetti is active (performance optimization)
            if (_confettiShownRecently)
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
                  colors: [
                    DesignSystem.buttonPrimary,
                    DesignSystem.buttonPrimary.withValues(alpha: 0.8),
                    DesignSystem.buttonPrimary.withValues(alpha: 0.6),
                  ],
                ),
              ),
            // Main content
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _handleJapTap,
              child: SafeArea(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final screenHeight = constraints.maxHeight;
                    final screenWidth = constraints.maxWidth;
                    final isSmallScreen = screenHeight < 600;
                    final isNarrowScreen = screenWidth < 360;
                    final isWideScreen = screenWidth > 600;
                    
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SizedBox(height: isSmallScreen ? 8 : 16),
                        // Stats row with Glass Cards - responsive layout
                        RepaintBoundary(
                          child: Padding(
                            padding: EdgeInsets.symmetric(
                              horizontal: isNarrowScreen ? DesignSystem.spacingSM : DesignSystem.spacingMD,
                            ),
                            child: LayoutBuilder(
                              builder: (context, cardConstraints) {
                                // On very narrow screens, use smaller spacing
                                final cardSpacing = isNarrowScreen ? DesignSystem.spacingXS : DesignSystem.spacingSM;
                                
                                return Row(
                                  children: [
                                    Expanded(
                                      flex: 1,
                                      child: ValueListenableBuilder<int>(
                                        valueListenable: _todayNotifier,
                                        builder: (_, today, __) => _StatCard(
                                          title: context.tr('counter.stat.todayJaps'),
                                          value: today.toString(),
                                          isCompact: isNarrowScreen,
                                        ),
                                      ),
                                    ),
                                    SizedBox(width: cardSpacing),
                                    Expanded(
                                      flex: 1,
                                      child: ValueListenableBuilder<int>(
                                        valueListenable: _todayNotifier,
                                        builder: (_, today, __) => _StatCard(
                                          title: context.tr('counter.stat.malas'),
                                          value: (today ~/ 108).toString(),
                                          isCompact: isNarrowScreen,
                                        ),
                                      ),
                                    ),
                                    SizedBox(width: cardSpacing),
                                    Expanded(
                                      flex: 1,
                                      child: ValueListenableBuilder<int>(
                                        valueListenable: _lifetimeMalasNotifier,
                                        builder: (_, lifetimeMalas, __) => _StatCard(
                                          title: context.tr('counter.stat.lifetimeMalas'),
                                          value: lifetimeMalas.toString(),
                                          isCompact: isNarrowScreen,
                                        ),
                                      ),
                                    ),
                                  ],
                                );
                              },
                            ),
                          ),
                        ),
                        SizedBox(height: isSmallScreen ? 12 : 20),
                        // Goal summary with Progress Ring
                        RepaintBoundary(
                          child: Padding(
                            padding: EdgeInsets.symmetric(
                              horizontal: isNarrowScreen ? DesignSystem.spacingSM : DesignSystem.spacingMD,
                            ),
                            child: ValueListenableBuilder<int>(
                              valueListenable: _todayNotifier,
                              builder: (_, today, __) {
                                final malas = today ~/ 108;
                                final goalProgress = _dailyGoal <= 0 
                                    ? 0.0 
                                    : (malas / _dailyGoal).clamp(0, 1).toDouble();
                                return _GoalSummary(
                                  dailyGoal: _dailyGoal,
                                  goalProgress: goalProgress,
                                  goalCompletedShown: _goalCompletedShown,
                                  malas: malas,
                                  onEditGoal: _editGoal,
                                  isNarrowScreen: isNarrowScreen,
                                );
                              },
                            ),
                          ),
                        ),
                        // Main counter area
                        Expanded(
                          child: Center(
                            child: SingleChildScrollView(
                              physics: const NeverScrollableScrollPhysics(),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Padding(
                                    padding: EdgeInsets.symmetric(
                                      horizontal: isNarrowScreen ? 8.0 : 16.0,
                                    ),
                                    child: Text(
                                      context.tr('counter.tapToCount'),
                                      style: TextStyle(
                                        fontSize: isNarrowScreen ? 14 : (isSmallScreen ? 15 : 17),
                                        fontWeight: FontWeight.w600,
                                        color: Theme.of(context).colorScheme.onSurface,
                                        letterSpacing: 0.3,
                                      ),
                                      textAlign: TextAlign.center,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  SizedBox(height: isSmallScreen ? 16 : 24),
                                  RepaintBoundary(
                                    child: ValueListenableBuilder<int>(
                                      valueListenable: _todayNotifier,
                                      builder: (_, today, __) {
                                        return ValueListenableBuilder<int>(
                                          valueListenable: _currentMalaCountNotifier,
                                          builder: (_, currentMalaCount, ___) {
                                            return _CounterButton(
                                              today: today,
                                              pulse: _pulse,
                                              currentMalaCount: currentMalaCount,
                                              malasCompleted: today ~/ 108,
                                              isSmallScreen: isSmallScreen,
                                              isNarrowScreen: isNarrowScreen,
                                              screenWidth: screenWidth,
                                              screenHeight: screenHeight,
                                            );
                                          },
                                        );
                                      },
                                    ),
                                  ),
                                  SizedBox(
                                    height: MediaQuery.of(context).padding.bottom + 16,
                                  ),
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
    // Dispose ValueNotifiers
    _todayNotifier.dispose();
    _lifetimeMalasNotifier.dispose();
    _currentMalaCountNotifier.dispose();
    // Force sync before disposal
    _store?.forceSyncNow();
    // Flush any pending daily summary writes
    unawaited(ActivityStore.flushPendingWrites());
    // Resume ad preloading when counter session ends
    AdManager.instance.onCounterSessionEnd();
    _confettiController.dispose();
    _cancelMalaResetTimer();
    super.dispose();
  }
}

class _StatCard extends StatelessWidget {
  final String title;
  final String value;
  final bool isCompact;
  const _StatCard({
    required this.title, 
    required this.value,
    this.isCompact = false,
  });

  @override
  Widget build(BuildContext context) {
    final padding = isCompact 
        ? const EdgeInsets.all(DesignSystem.spacingSM) 
        : const EdgeInsets.all(DesignSystem.spacingMD);
    final titleSize = isCompact ? 10.0 : 11.0;
    final valueSize = isCompact ? 20.0 : 24.0;
    
    return GlassCard(
      padding: padding,
      borderRadius: DesignSystem.radiusCard,
      useBackdropBlur: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: titleSize,
              fontWeight: FontWeight.w600,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              letterSpacing: 0.2,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          SizedBox(height: isCompact ? 6 : 8),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
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
    );
  }
}

class _CounterButton extends StatelessWidget {
  final int today;
  final bool pulse;
  final int currentMalaCount;
  final int malasCompleted;
  final bool isSmallScreen;
  final bool isNarrowScreen;
  final double screenWidth;
  final double screenHeight;

  const _CounterButton({
    required this.today,
    required this.pulse,
    required this.currentMalaCount,
    required this.malasCompleted,
    required this.isSmallScreen,
    this.isNarrowScreen = false,
    required this.screenWidth,
    required this.screenHeight,
  });

  @override
  Widget build(BuildContext context) {
    final malaProgress = (currentMalaCount / 108).clamp(0.0, 1.0);
    
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedScale(
          scale: pulse ? 1.08 : 1.0,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
          child: LayoutBuilder(
            builder: (context, constraints) {
              // Calculate responsive circle size based on available space
              final availableWidth = constraints.maxWidth;
              final availableHeight = constraints.maxHeight;
              final minSize = isNarrowScreen ? 160.0 : 200.0;
              final maxSize = isNarrowScreen ? 240.0 : 280.0;
              
              // Use the smaller dimension to ensure it fits
              final baseSize = availableWidth < availableHeight
                  ? availableWidth * (isNarrowScreen ? 0.7 : 0.65)
                  : availableHeight * (isNarrowScreen ? 0.4 : 0.45);
              
              final circleSize = baseSize.clamp(minSize, maxSize);
              
              return Container(
                height: circleSize,
                width: circleSize,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.transparent,
                ),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // Progress ring for mala progress - more vibrant
                    ProgressRing(
                      progress: malaProgress,
                      size: circleSize,
                      strokeWidth: isNarrowScreen ? 5 : 6,
                      progressColor: DesignSystem.buttonPrimary.withValues(alpha: 0.55), // Soothing color
                      backgroundColor: Theme.of(context).brightness == Brightness.dark 
                          ? const Color(0xFF2C2C2C) 
                          : const Color(0xFFFFE4CC), // Theme-aware background
                      backgroundFillColor: Theme.of(context).brightness == Brightness.dark 
                          ? const Color(0xFF2C2C2C) 
                          : const Color(0xFFFFE4CC), // Theme-aware fill
                      showGlow: false, // No glow to avoid blur
                    ),
                    // Inner filled circle - theme-aware color
                    Container(
                      width: circleSize * 0.68,
                      height: circleSize * 0.68,
                      decoration: BoxDecoration(
                        color: Theme.of(context).brightness == Brightness.dark 
                            ? const Color(0xFF2C2C2C) 
                            : const Color(0xFFFFE4CC), // Theme-aware color
                        shape: BoxShape.circle,
                      ),
                    ),
                    // Main counter number - less vibrant and smaller
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Padding(
                        padding: EdgeInsets.all(isNarrowScreen ? 16.0 : 24.0),
                        child: Text(
                          '$today',
                          style: TextStyle(
                            fontSize: circleSize * 0.28,
                            fontWeight: FontWeight.w600,
                            color: Theme.of(context).colorScheme.onSurface, // Theme-aware color
                            letterSpacing: 0,
                            height: 1.2,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
        SizedBox(height: isSmallScreen ? 16 : 24),
        Padding(
          padding: EdgeInsets.symmetric(
            horizontal: isNarrowScreen ? 8.0 : 16.0,
          ),
          child: _MalaProgressDisplay(
            currentMalaCount: currentMalaCount,
            malasCompleted: malasCompleted,
            isNarrowScreen: isNarrowScreen,
          ),
        ),
      ],
    );
  }
}

class _MalaProgressDisplay extends StatelessWidget {
  final int currentMalaCount;
  final int malasCompleted;
  final bool isNarrowScreen;
  const _MalaProgressDisplay({
    required this.currentMalaCount,
    required this.malasCompleted,
    this.isNarrowScreen = false,
  });

  @override
  Widget build(BuildContext context) {
    final normalized = currentMalaCount.clamp(0, 108).toInt();

    final fontSize = isNarrowScreen ? 18.0 : 20.0;
    final subtitleSize = isNarrowScreen ? 12.0 : 13.0;
    
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '$normalized / 108',
          style: TextStyle(
            fontSize: fontSize,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.5,
            color: Theme.of(context).colorScheme.onSurface,
          ),
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        SizedBox(height: isNarrowScreen ? 4 : 6),
        Text(
          context.tr(
            'counter.malaProgress.completed',
            args: {'count': '$malasCompleted'},
          ),
          style: TextStyle(
            fontSize: subtitleSize,
            fontWeight: FontWeight.w500,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
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
  final bool isNarrowScreen;

  const _GoalSummary({
    required this.dailyGoal,
    required this.goalProgress,
    required this.goalCompletedShown,
    required this.malas,
    required this.onEditGoal,
    this.isNarrowScreen = false,
  });

  @override
  Widget build(BuildContext context) {
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

    final iconSize = isNarrowScreen ? 50.0 : 60.0;
    final iconInnerSize = isNarrowScreen ? 22.0 : 26.0;
    final titleSize = isNarrowScreen ? 14.0 : 16.0;
    final subtitleSize = isNarrowScreen ? 12.0 : 13.0;
    
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: 0,
        vertical: 8,
      ),
      child: GlassCard(
        padding: EdgeInsets.all(isNarrowScreen ? DesignSystem.spacingSM : DesignSystem.spacingMD),
        borderRadius: DesignSystem.radiusCard,
        onTap: onEditGoal,
        useBackdropBlur: true,
        child: Row(
          children: [
            // Goal icon with progress ring
            SizedBox(
              width: iconSize,
              height: iconSize,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  if (dailyGoal > 0)
                    ProgressRing(
                      progress: goalProgress.clamp(0.0, 1.0),
                      size: iconSize,
                      strokeWidth: isNarrowScreen ? 3 : 4,
                      progressColor: goalCompletedShown 
                          ? DesignSystem.buttonPrimary // Soothing color when completed
                          : DesignSystem.buttonPrimary.withValues(alpha: 0.7), // Soothing color
                      backgroundColor: Theme.of(context).brightness == Brightness.dark 
                          ? const Color(0xFF2C2C2C) 
                          : const Color(0xFFFFE4CC), // Theme-aware background
                      backgroundFillColor: Theme.of(context).brightness == Brightness.dark 
                          ? const Color(0xFF2C2C2C) 
                          : const Color(0xFFFFE4CC), // Theme-aware fill
                      showGlow: false, // No glow to avoid blur
                    ),
                  // Thin white circle outside the flag
                  Container(
                    width: iconSize * 0.9,
                    height: iconSize * 0.9,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Theme.of(context).brightness == Brightness.dark
                            ? Colors.white.withValues(alpha: 0.3)
                            : Colors.white.withValues(alpha: 0.5),
                        width: 1.0, // Very thin
                      ),
                    ),
                  ),
                  Container(
                    padding: EdgeInsets.all(isNarrowScreen ? 8 : 10),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surface, // Theme-aware color
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.08),
                          blurRadius: 2, // Subtle shadow, no blur
                          offset: const Offset(0, 1),
                        ),
                      ],
                    ),
                    child: Icon(
                      Icons.flag_rounded,
                      color: goalCompletedShown 
                          ? DesignSystem.buttonPrimary // Soothing color when completed
                          : DesignSystem.buttonPrimary, // Soothing color
                      size: iconInnerSize,
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(width: isNarrowScreen ? DesignSystem.spacingSM : DesignSystem.spacingMD),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    goalLabel,
                    style: TextStyle(
                      fontSize: titleSize,
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  SizedBox(height: isNarrowScreen ? 2 : 4),
                  Text(
                    statusText,
                    style: TextStyle(
                      fontSize: subtitleSize,
                      fontWeight: FontWeight.w500,
                      color: Theme.of(context).brightness == Brightness.dark
                          ? Colors.white.withValues(alpha: 0.7) // Less white for visibility
                          : const Color(0xFF666666),
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            SizedBox(width: isNarrowScreen ? 4 : 8),
            Icon(
              Icons.edit_outlined,
              color: const Color(0xFF999999),
              size: isNarrowScreen ? 18 : 22,
            ),
          ],
        ),
      ),
    );
  }
}
