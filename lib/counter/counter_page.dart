import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:confetti/confetti.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

class CounterPage extends StatefulWidget {
  const CounterPage({super.key});

  @override
  State<CounterPage> createState() => _CounterPageState();
}

class _CounterPageState extends State<CounterPage> {
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
    _confettiController = ConfettiController(
      duration: const Duration(seconds: 3),
    );
    _init();
  }

  Future<void> _init() async {
    final store = await CounterStore.create();
    final goalStore = await GoalStore.create();
    final prefs = await SharedPreferences.getInstance();

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
          _bellPlayer ??= AudioPlayer();
          await _bellPlayer!.play(AssetSource('audio/bell_end.mp3'));
        } catch (e) {
          debugPrint('[Counter] Bell play failed: $e');
        }
      }
      _triggerConfetti();
      await ActivityStore.recordDailySummary(_today, _today ~/ 108);
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
    await store.increment();

    try {
      final insights = await InsightStore.create();
      await insights.recordJap(count: 1, malas: willBe % 108 == 0 ? 1 : 0);
    } catch (e) {
      debugPrint('[Insights] Record failed: $e');
    }

    if (wasZero) {
      await ActivityStore.markTodayActive();
      // Check for milestone streaks when starting from zero
      await _handleStreakMilestones(context, showSnackBar: true);
    }

    if (willBe % 108 == 0) {
      // Check for streak milestones when completing a mala
      await _handleStreakMilestones(context, showSnackBar: false);
      try {
        HapticFeedback.mediumImpact();
      } catch (_) {}
      _triggerPulse();
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(context.tr('counter.malaCompleted')),
            duration: const Duration(seconds: 3),
            behavior: SnackBarBehavior.floating,
          ),
        );
      try {
        final sessions = await SessionStore.create();
        await sessions.addSession(type: 'jap', count: willBe);
      } catch (_) {}
    }

    if (!mounted) return;

    final updatedToday = store.todayJaps;
    final remainder = updatedToday % 108;
    final malaCompleted = remainder == 0 && updatedToday > 0;

    setState(() {
      _today = updatedToday;
      _lifetime = store.lifetimeJaps;
      _currentMalaCountDisplay = malaCompleted ? 108 : remainder;
    });

    if (malaCompleted) {
      _scheduleMalaReset();
    }

    await _checkGoalCompletion();

    // Schedule notification reminder (non-blocking, errors handled internally)
    try {
      final ns = NotificationService();
      await ns.scheduleDynamicJapReminder(_today);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[Counter] Notification scheduling failed: $e');
      }
      // Continue execution even if notification fails
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
    final language = AppLocalizationScope.of(context).language;
    final suffix = language == 'hi'
        ? (_dailyGoal == 1 ? '' : 'एँ')
        : (_dailyGoal == 1 ? '' : 's');
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.tr('counter.goal.complete.title')),
        content: Text(
          context.tr(
            'counter.goal.complete.message',
            args: {'count': '$_dailyGoal', 'suffix': suffix},
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(context.tr('counter.goal.complete.button')),
          ),
        ],
      ),
    );
  }

  void _triggerConfetti() {
    if (_confettiShownRecently) return;
    _confettiShownRecently = true;
    _confettiController.play();
    Future.delayed(const Duration(seconds: 3), () {
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
            final bell = AudioPlayer();
            await bell.play(AssetSource('audio/bell_end.mp3'));
          } catch (_) {}
          if (mounted) {
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
        } else {
          // When completing a mala, update dedication note
          try {
            final dedicationStore = await DedicationStore.create();
            await dedicationStore.setNote(
              '🔥 $streak-Day Streak — साधना निरंतर जारी है!',
            );
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
    final result = await showDialog<int>(
      context: context,
      builder: (ctx) {
        int sliderValue = _dailyGoal.clamp(0, 50);
        return StatefulBuilder(
          builder: (context, setLocalState) => AlertDialog(
            title: const Text('Set your daily jap goal (malas)'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  sliderValue == 0
                      ? 'No daily goal'
                      : '$sliderValue mala${sliderValue == 1 ? '' : 's'} per day',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
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
                  'Use the slider to adjust your daily mala goal.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: Theme.of(context).hintColor),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, sliderValue),
                child: const Text('Save'),
              ),
            ],
          ),
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
                numberOfParticles: 24,
                emissionFrequency: 0.04,
                maxBlastForce: 12,
                minBlastForce: 6,
                gravity: 0.2,
                colors: const [
                  Colors.amber,
                  Colors.pink,
                  Colors.purple,
                  Colors.white,
                ],
              ),
            ),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _handleJapTap,
              child: SafeArea(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 16),
                    Padding(
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
                    const SizedBox(height: 24),
                    _GoalSummary(
                      dailyGoal: _dailyGoal,
                      goalProgress: _goalProgress,
                      goalCompletedShown: _goalCompletedShown,
                      malas: _malas,
                      onEditGoal: _editGoal,
                    ),
                    Expanded(
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'Tap to Count',
                              style: theme.textTheme.titleLarge,
                            ),
                            const SizedBox(height: 16),
                            AnimatedScale(
                              scale: _pulse ? 1.08 : 1.0,
                              duration: const Duration(milliseconds: 220),
                              curve: Curves.easeOut,
                              child: Container(
                                height: 240,
                                width: 240,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  gradient: RadialGradient(
                                    colors: [
                                      theme.colorScheme.primary.withOpacity(
                                        0.25,
                                      ),
                                      theme.colorScheme.surface,
                                    ],
                                    radius: 0.85,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: theme.colorScheme.primary
                                          .withOpacity(0.3),
                                      blurRadius: 30,
                                      spreadRadius: 2,
                                    ),
                                  ],
                                ),
                                child: Center(
                                  child: Text(
                                    '$_today',
                                    style: theme.textTheme.displayLarge
                                        ?.copyWith(
                                          fontWeight: FontWeight.bold,
                                          foreground: Paint()
                                            ..shader = GlowTheme.linearGradient(
                                              context,
                                            ),
                                        ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 20),
                            _MalaProgressDisplay(
                              currentMalaCount: _currentMalaCountDisplay,
                              malasCompleted: _malas,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
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
    final progress = normalized / 108.0;
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
    final language = AppLocalizationScope.of(context).language;
    final suffix = language == 'hi'
        ? (dailyGoal == 1 ? '' : 'एँ')
        : (dailyGoal == 1 ? '' : 's');
    final goalLabel = dailyGoal == 0
        ? context.tr('counter.goal.cta')
        : context.tr(
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
    final statusText = context.tr(statusKey, args: statusArgs);

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
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary.withOpacity(0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.flag_rounded,
                    color: theme.colorScheme.primary,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        goalLabel,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(statusText, style: theme.textTheme.bodySmall),
                      const SizedBox(height: 8),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(999),
                        child: LinearProgressIndicator(
                          value: goalProgress,
                          minHeight: 6,
                          backgroundColor: theme.colorScheme.primary
                              .withOpacity(0.08),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Icon(
                  Icons.edit_outlined,
                  color: theme.colorScheme.primary,
                  size: 20,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
