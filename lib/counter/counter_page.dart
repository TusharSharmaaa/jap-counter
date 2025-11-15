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
  State<CounterPage> createState() => _CounterPageState();
}

class _CounterPageState extends State<CounterPage> with WidgetsBindingObserver {
  CounterStore? _store;
  bool _loading = true;
  int _today = 0;
  int _lifetime = 0;
  int _lifetimeMalas = 0; // Store lifetime malas separately (calculated from completed malas)
  bool _pulse = false;
  int _dailyGoal = 0;
  bool _goalCompletedShown = false;
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
    }
  }

  Future<void> _initFeedbackController() async {
    final settings = await TapFeedbackSettings.load();
    await TapFeedbackController.instance.initialize(settings);
  }

  Future<void> _init() async {
    final store = await CounterStore.create();
    final goalStore = await GoalStore.create();

    final congratulatedToday =
        goalStore.lastCongratsDate == GoalStore.todayKey();

    setState(() {
      _store = store;
      _today = store.todayJaps;
      _lifetime = store.lifetimeJaps;
      _lifetimeMalas = store.lifetimeMalas; // Use lifetime malas from store (calculated from completed malas)
      _dailyGoal = goalStore.dailyMalasGoal;
      _goalCompletedShown = congratulatedToday;
      _currentMalaCountDisplay = _calculateCurrentMalaDisplay(store.todayJaps);
      _loading = false;
    });
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
      _lifetimeMalas = store.lifetimeMalas; // Update lifetime malas from store (calculated from completed malas)
      _currentMalaCountDisplay = malaCompleted ? 108 : remainder;
    });

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
          setState(() {
            _lifetimeMalas = store.lifetimeMalas;
          });
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
              currentCount: _today,
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
                style: const TextStyle(color: Color(0xFF1A1A1A)), // Black text color
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
                          color: const Color(0xFF1A1A1A), // Black text color
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
                        ?.copyWith(color: const Color(0xFF666666)), // Dark gray instead of hint color
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
        backgroundColor: DesignSystem.backgroundLight,
        body: Container(
          decoration: const BoxDecoration(
            gradient: DesignSystem.backgroundGradient,
          ),
          child: const Center(
            child: CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(DesignSystem.primary),
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: DesignSystem.backgroundLight,
      body: Container(
        decoration: const BoxDecoration(
          color: DesignSystem.backgroundLight, // Uniform light orange/cream color
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
                    Colors.white.withValues(alpha: 0.22),
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
                        color: DesignSystem.primary.withValues(alpha: 0.04),
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
                  colors: const [
                    DesignSystem.primary,
                    DesignSystem.accentGlow,
                    DesignSystem.primaryDark,
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
                    final isSmallScreen = screenHeight < 600;
                    
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SizedBox(height: isSmallScreen ? 8 : 16),
                        // Stats row with Glass Cards
                        RepaintBoundary(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: DesignSystem.spacingMD,
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: _StatCard(
                                    title: context.tr('counter.stat.todayJaps'),
                                    value: _today.toString(),
                                  ),
                                ),
                                const SizedBox(width: DesignSystem.spacingSM),
                                Expanded(
                                  child: _StatCard(
                                    title: context.tr('counter.stat.malas'),
                                    value: _malas.toString(),
                                  ),
                                ),
                                const SizedBox(width: DesignSystem.spacingSM),
                                Expanded(
                                  child: _StatCard(
                                    title: context.tr('counter.stat.lifetimeMalas'),
                                    value: _lifetimeMalas.toString(),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        SizedBox(height: isSmallScreen ? 12 : 20),
                        // Goal summary with Progress Ring
                        RepaintBoundary(
                          child: _GoalSummary(
                            dailyGoal: _dailyGoal,
                            goalProgress: _goalProgress,
                            goalCompletedShown: _goalCompletedShown,
                            malas: _malas,
                            onEditGoal: _editGoal,
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
                                  Text(
                                    context.tr('counter.tapToCount'),
                                    style: TextStyle(
                                      fontSize: isSmallScreen ? 15 : 17,
                                      fontWeight: FontWeight.w600,
                                      color: const Color(0xFF333333),
                                      letterSpacing: 0.3,
                                    ),
                                  ),
                                  SizedBox(height: isSmallScreen ? 16 : 24),
                                  RepaintBoundary(
                                    child: _CounterButton(
                                      today: _today,
                                      pulse: _pulse,
                                      currentMalaCount: _currentMalaCountDisplay,
                                      malasCompleted: _malas,
                                      isSmallScreen: isSmallScreen,
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
  const _StatCard({required this.title, required this.value});

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.all(DesignSystem.spacingMD),
      borderRadius: DesignSystem.radiusCard,
      useBackdropBlur: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: Color(0xFF666666),
              letterSpacing: 0.2,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 8),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Color(0xFF1A1A1A),
                letterSpacing: -0.5,
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
              final maxSize = constraints.maxWidth < constraints.maxHeight
                  ? constraints.maxWidth * 0.65
                  : constraints.maxHeight * 0.45;
              final circleSize = (maxSize.clamp(200.0, 280.0));
              
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
                      strokeWidth: 6,
                      progressColor: DesignSystem.primary.withValues(alpha: 0.55), // More vibrant but not complete
                      backgroundColor: const Color(0xFFFFE4CC), // Light orange background for ring
                      backgroundFillColor: const Color(0xFFFFE4CC), // Light orange fill for whole ring area
                      showGlow: false, // No glow to avoid blur
                    ),
                    // Inner filled circle - light orange uniform color
                    Container(
                      width: circleSize * 0.68,
                      height: circleSize * 0.68,
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFE4CC), // Light orange uniform color
                        shape: BoxShape.circle,
                      ),
                    ),
                    // Main counter number - less vibrant and smaller
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Padding(
                        padding: const EdgeInsets.all(24.0),
                        child: Text(
                          '$today',
                          style: TextStyle(
                            fontSize: circleSize * 0.28,
                            fontWeight: FontWeight.w600,
                            color: const Color(0xFF666666), // Less vibrant gray
                            letterSpacing: 0,
                            height: 1.2,
                          ),
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
    final normalized = currentMalaCount.clamp(0, 108).toInt();

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '$normalized / 108',
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.5,
            color: Color(0xFF333333),
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 6),
        Text(
          context.tr(
            'counter.malaProgress.completed',
            args: {'count': '$malasCompleted'},
          ),
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: Color(0xFF666666),
          ),
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
      padding: const EdgeInsets.symmetric(
        horizontal: DesignSystem.spacingMD,
        vertical: 8,
      ),
      child: GlassCard(
        padding: const EdgeInsets.all(DesignSystem.spacingMD),
        borderRadius: DesignSystem.radiusCard,
        onTap: onEditGoal,
        useBackdropBlur: true,
        child: Row(
          children: [
            // Goal icon with progress ring
            SizedBox(
              width: 60,
              height: 60,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  if (dailyGoal > 0)
                    ProgressRing(
                      progress: goalProgress.clamp(0.0, 1.0),
                      size: 60,
                      strokeWidth: 4,
                      progressColor: goalCompletedShown 
                          ? DesignSystem.primary // Vibrant when completed
                          : DesignSystem.primary.withValues(alpha: 0.7), // Vibrant but elegant
                      backgroundColor: const Color(0xFFFFE4CC), // Clear light orange background - no blur
                      backgroundFillColor: const Color(0xFFFFE4CC), // Light orange fill
                      showGlow: false, // No glow to avoid blur
                    ),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.white, // Solid white for better visibility
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
                          ? DesignSystem.primaryDark // More vibrant when completed
                          : DesignSystem.primary, // Vibrant orange
                      size: 26,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: DesignSystem.spacingMD),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    goalLabel,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF1A1A1A),
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    statusText,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFF666666),
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              Icons.edit_outlined,
              color: const Color(0xFF999999),
              size: 22,
            ),
          ],
        ),
      ),
    );
  }
}
