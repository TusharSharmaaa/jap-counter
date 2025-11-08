import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:confetti/confetti.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../ads/test_banner.dart';
import '../data/activity_store.dart';
import '../data/counter_store.dart';
import '../data/dedication_store.dart';
import '../data/goal_store.dart';
import '../data/insight_store.dart';
import '../data/session_store.dart';
import '../gamify/gamify_store.dart';
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

  @override
  void initState() {
    super.initState();
    _confettiController = ConfettiController(duration: const Duration(seconds: 3));
    _init();
  }

  Future<void> _init() async {
    final store = await CounterStore.create();
    final goalStore = await GoalStore.create();
    final prefs = await SharedPreferences.getInstance();

    final congratulatedToday = goalStore.lastCongratsDate == GoalStore.todayKey();

    setState(() {
      _store = store;
      _today = store.todayJaps;
      _lifetime = store.lifetimeJaps;
      _dailyGoal = goalStore.dailyMalasGoal;
      _goalCompletedShown = congratulatedToday;
      _soundEnabled = prefs.getBool('settings.soundEnabled') ?? true;
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
          await _bellPlayer!.play(AssetSource('sounds/bell.mp3'));
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

    final wasZero = _today == 0;
    final willBe = _today + 1;
    await store.increment();

    try {
      final insights = await InsightStore.create();
      await insights.recordJap(count: 1, malas: willBe % 108 == 0 ? 1 : 0);
    } catch (e) {
      debugPrint('[Insights] Record failed: $e');
    }

    try {
      final xpRes = await GamifyStore.addXp(1);
      if (xpRes['leveledUp'] == true) {
        try {
          HapticFeedback.mediumImpact();
        } catch (_) {}
        await _showLevelUpDialog(xpRes['level'] as int? ?? 1);
      }
    } catch (_) {}

    if (wasZero) {
      await ActivityStore.markTodayActive();
    }
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

    if (willBe % 108 == 0) {
      try {
        final streak = await ActivityStore.currentStreak();
        if (streak == 7 || streak == 21 || streak == 40) {
          final dedicationStore = await DedicationStore.create();
          await dedicationStore.setNote('🔥 $streak-Day Streak — साधना निरंतर जारी है!');
        }
      } catch (_) {}
      try {
        HapticFeedback.mediumImpact();
      } catch (_) {}
      _triggerPulse();
      try {
        final xpRes = await GamifyStore.addXp(20);
        final next = xpRes['nextThreshold'] as int? ?? 0;
        final xp = xpRes['xp'] as int? ?? 0;
        final level = xpRes['level'] as int? ?? 1;
        if (!mounted) return;
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
          await _showLevelUpDialog(level);
        }
      } catch (_) {}
      try {
        final sessions = await SessionStore.create();
        await sessions.addSession(type: 'jap', count: willBe);
      } catch (_) {}
    }

    if (!mounted) return;

    setState(() {
      _today = store.todayJaps;
      _lifetime = store.lifetimeJaps;
    });

    await _checkGoalCompletion();

    final ns = NotificationService();
    await ns.scheduleDynamicJapReminder(_today);
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
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('🌼 लक्ष्य पूर्ण'),
        content: Text('आपने आज $_dailyGoal माला${_dailyGoal == 1 ? '' : 'एँ'} पूरी कर ली हैं। साधना जारी रखें!'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('राधे राधे')),
        ],
      ),
    );
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

  void _triggerConfetti() {
    if (_confettiShownRecently) return;
    _confettiShownRecently = true;
    _confettiController.play();
    Future.delayed(const Duration(seconds: 3), () {
      _confettiShownRecently = false;
    });
  }

  int get _malas => _today ~/ 108;
  int get _lifetimeMalas => _lifetime ~/ 108;
  double get _goalProgress {
    if (_dailyGoal <= 0) return 0;
    return (_malas / _dailyGoal).clamp(0, 1).toDouble();
  }

  Future<void> _editGoal() async {
    final controller = TextEditingController(text: '$_dailyGoal');
    final result = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Set your daily jap goal (malas)'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'Goal (malas)'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, int.tryParse(controller.text) ?? _dailyGoal),
            child: const Text('Save'),
          ),
        ],
      ),
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
        bottomNavigationBar: const TestBanner(),
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
                          Expanded(child: _StatTile(title: "Today's Japs", value: _today.toString())),
                          const SizedBox(width: 8),
                          Expanded(child: _StatTile(title: "Malas", value: _malas.toString())),
                          const SizedBox(width: 8),
                          Expanded(child: _StatTile(title: "Lifetime Malas", value: _lifetimeMalas.toString())),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    _MalaProgress(todayJaps: _today),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: theme.dividerColor),
                          color: theme.colorScheme.surface.withOpacity(0.9),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  'Goal: $_dailyGoal mala${_dailyGoal == 1 ? '' : 's'}',
                                  style: theme.textTheme.titleMedium,
                                ),
                                IconButton(
                                  icon: const Icon(Icons.edit, size: 18),
                                  onPressed: _editGoal,
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            LinearProgressIndicator(
                              value: _goalProgress,
                              minHeight: 10,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            const SizedBox(height: 6),
                            Builder(
                              builder: (_) {
                                final status = _dailyGoal <= 0
                                    ? 'No daily goal set'
                                    : _goalCompletedShown
                                        ? '✅ Goal met for today'
                                        : 'Progress: $_malas / $_dailyGoal mala${_dailyGoal == 1 ? '' : 's'}';
                                return Text(
                                  status,
                                  style: theme.textTheme.labelMedium,
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text('Tap to Count', style: theme.textTheme.titleLarge),
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
                                  child: Text(
                                    '$_today',
                                    style: theme.textTheme.displayLarge?.copyWith(
                                      fontWeight: FontWeight.bold,
                                      foreground: Paint()..shader = GlowTheme.linearGradient(context),
                                    ),
                                  ),
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
            ),
          ],
        ),
      ),
      bottomNavigationBar: const TestBanner(),
    );
  }

  @override
  void dispose() {
    _confettiController.dispose();
    _bellPlayer?.dispose();
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

