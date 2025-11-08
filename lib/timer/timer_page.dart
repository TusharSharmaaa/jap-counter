import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/brand.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:share_plus/share_plus.dart';
import 'package:lottie/lottie.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:confetti/confetti.dart';

import 'timer_sound_controller.dart';
import 'timer_prefs.dart';
import '../ads/interstitial_timer.dart';
import '../data/meditation_store.dart';
import '../data/dedication_store.dart';

enum _TimerState { idle, running, paused, completed }

class TimerPage extends StatefulWidget {
  const TimerPage({super.key});

  @override
  State<TimerPage> createState() => _TimerPageState();
}

class _TimerPageState extends State<TimerPage> with WidgetsBindingObserver {
  // ---- State & prefs ----
  final List<int> _presets = const [5, 10, 15, 20, 30, 45, 60, 90];
  int _selectedMinutes = 10;

  Duration _total = const Duration(minutes: 10);
  Duration _remaining = const Duration(minutes: 10);
  Timer? _ticker;
  _TimerState _state = _TimerState.idle;

  // Ambience
  final TimerSoundController _sound = TimerSoundController();
  TimerSoundType _selectedSound = TimerSoundType.mute;

  // Ticker drift control
  DateTime? _lastTickAt;

  // Completion UI guards
  bool? _completionShown; // set to false when starting a new session

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    // preload sound (no auto-play)
    _sound.setSound(_selectedSound);

    // Load saved prefs
    final prefs = await TimerPrefs.create();
    final savedMinutes = prefs.minutes;
    final savedSoundIdx = prefs.soundIndex;

    if (!mounted) return;
    setState(() {
      _selectedMinutes = savedMinutes;
      _total = Duration(minutes: savedMinutes);
      _remaining = _total;
      _selectedSound = TimerSoundType.values[
      savedSoundIdx.clamp(0, TimerSoundType.values.length - 1)
      ];
    });

    // Preload the chosen sound asset
    _sound.setSound(_selectedSound);

    // Preload interstitial for post-completion
    TimerInterstitialGate.instance.preload();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    WakelockPlus.disable();   // allow screen sleep
    _sound.dispose();         // stop & release audio
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // ---- UI actions ----
  void _selectPreset(int minutes) {
    if (_state == _TimerState.running) return;
    HapticFeedback.selectionClick();
    setState(() {
      _selectedMinutes = minutes;
      _total = Duration(minutes: minutes);
      _remaining = _total;
      _state = _TimerState.idle;
    });
    // SAVE
    TimerPrefs.create().then((p) => p.setMinutes(minutes));
  }

  void _selectSound(TimerSoundType t) {
    if (_selectedSound == t) return;
    HapticFeedback.selectionClick();
    setState(() => _selectedSound = t);
    _sound.setSound(t); // preload chosen sound
    // SAVE
    TimerPrefs.create().then((p) => p.setSoundIndex(t.index));
  }

  void _start() {
    if (_state == _TimerState.running) return;
    HapticFeedback.lightImpact();

    TimerInterstitialGate.instance.resetSession();
    _completionShown = false; // reset completion guard for new session

    setState(() {
      _total = Duration(minutes: _selectedMinutes);
      _remaining = _total;
      _state = _TimerState.running;
      _lastTickAt = DateTime.now();
    });

    // Keep screen awake
    WakelockPlus.enable();

    // Start ambience if not muted
    _sound.start();

    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(milliseconds: 200), (t) {
      final now = DateTime.now();
      final elapsed = now.difference(_lastTickAt ?? now);
      _lastTickAt = now;

      final next = _remaining - elapsed;
      if (next <= Duration.zero) {
        t.cancel();
        _onComplete();
      } else {
        setState(() {
          _remaining = next;
        });
      }
    });
  }

  void _pause() {
    if (_state != _TimerState.running) return;
    HapticFeedback.selectionClick();
    _ticker?.cancel();

    WakelockPlus.disable(); // allow sleep
    _sound.pause();

    setState(() => _state = _TimerState.paused);
  }

  void _resume() {
    if (_state != _TimerState.paused) return;
    HapticFeedback.lightImpact();
    setState(() {
      _state = _TimerState.running;
      _lastTickAt = DateTime.now();
    });

    WakelockPlus.enable();
    _sound.resume();

    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(milliseconds: 200), (t) {
      final now = DateTime.now();
      final elapsed = now.difference(_lastTickAt ?? now);
      _lastTickAt = now;

      final next = _remaining - elapsed;
      if (next <= Duration.zero) {
        t.cancel();
        _onComplete();
      } else {
        setState(() {
          _remaining = next;
        });
      }
    });
  }

  void _stop() {
    if (_state == _TimerState.idle) return;
    HapticFeedback.selectionClick();
    _ticker?.cancel();

    WakelockPlus.disable();
    _sound.stop();

    setState(() {
      _total = Duration(minutes: _selectedMinutes);
      _remaining = _total;
      _state = _TimerState.idle;
    });
  }

  void _reset() {
    HapticFeedback.selectionClick();
    _ticker?.cancel();

    WakelockPlus.disable();
    _sound.stop();

    setState(() {
      _total = Duration(minutes: _selectedMinutes);
      _remaining = _total;
      _state = _TimerState.idle;
    });
  }

  Future<void> _onComplete() async {
    // haptic
    try { await HapticFeedback.mediumImpact(); } catch (_) {}

    // allow sleep & stop ambience
    WakelockPlus.disable();
    _sound.stop();

    setState(() {
      _remaining = Duration.zero;
      _state = _TimerState.completed;
    });

    // Prevent duplicate completion popups
    _completionShown ??= false;
    if (mounted && _completionShown == false) {
      _completionShown = true;

      // Play a gentle bell on completion (one-shot)
      try {
        final bell = AudioPlayer();
        await bell.play(AssetSource('sounds/bell.mp3'));
      } catch (e) {
        if (kDebugMode) debugPrint('[Timer] Bell sound failed: $e');
      }

      // 1) Gentle Lottie overlay (auto-dismiss ~1.5s)
      final confettiController = ConfettiController(duration: const Duration(seconds: 2));
      confettiController.play();
      final overlayFuture = showGeneralDialog(
        context: context,
        barrierDismissible: false,
        barrierLabel: 'sadhana_complete',
        barrierColor: Colors.black54,
        transitionDuration: const Duration(milliseconds: 250),
        pageBuilder: (context, _, __) {
          return Stack(
            alignment: Alignment.center,
            children: [
              ConfettiWidget(
                confettiController: confettiController,
                blastDirectionality: BlastDirectionality.explosive,
                shouldLoop: false,
                colors: const [Colors.amber, Colors.pink, Colors.deepPurple, Colors.white],
              ),
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 220,
                      height: 220,
                      child: Lottie.network(
                        'https://assets9.lottiefiles.com/packages/lf20_jcikwtux.json',
                        repeat: false,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '🌼 साधना पूर्ण हुई',
                      style: Theme.of(context).textTheme.titleLarge,
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      );
      await Future.delayed(const Duration(milliseconds: 1500));
      if (mounted && Navigator.of(context, rootNavigator: true).canPop()) {
        Navigator.of(context, rootNavigator: true).pop(); // close overlay
      }
      await overlayFuture;
      confettiController.dispose();

      // 2) Summary dialog with Share
      if (mounted) {
        await showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) {
            final minutes = _selectedMinutes;
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: const Text('🌼 साधना पूर्ण हुई', textAlign: TextAlign.center),
              content: Text(
                'आपने $minutes मिनट ध्यान किया।',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyLarge,
              ),
              actionsAlignment: MainAxisAlignment.center,
              actions: [
                TextButton(
                  onPressed: () async {
                    Navigator.pop(context);
                    await SharePlus.instance.share(
                      ShareParams(
                        text: 'साधना पूर्ण हुई — मैंने $minutes मिनट ध्यान किया। Radha Jap Counter के साथ।',
                      ),
                    );
                  },
                  child: const Text('Share Blessing'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Done'),
                ),
              ],
            );
          },
        );
      }
    }

    // Save completed meditation minutes (today + lifetime)
    try {
      final store = await MeditationStore.create();
      await store.addMinutes(_total.inMinutes);
    } catch (_) {}

    try {
      final dstore = await DedicationStore.create();
      if (dstore.note.isEmpty) {
        await dstore.setNote("Radha Radha 🙏");
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[Timer] DedicationStore failed: $e');
    }

    // After dialog: try interstitial once per session
    await TimerInterstitialGate.instance.maybeShow();
  }

  // ---- Derived UI values ----
  double get _progress {
    if (_total.inMilliseconds == 0) return 0;
    final done = _total.inMilliseconds - _remaining.inMilliseconds;
    return (done / _total.inMilliseconds).clamp(0, 1).toDouble();
  }

  String get _readout => _formatDuration(_remaining);

  String get _ambienceLabel {
    switch (_selectedSound) {
      case TimerSoundType.mute:
        return 'Mute';
      case TimerSoundType.om:
        return 'Om';
      case TimerSoundType.birds:
        return 'Birds';
      case TimerSoundType.water:
        return 'Water';
      case TimerSoundType.flute:
        return 'Flute';
      case TimerSoundType.bell:
        return 'Bell';
    }
  }

  static String _formatDuration(Duration d) {
    final totalSeconds = d.inSeconds.clamp(0, 24 * 60 * 60);
    final m = (totalSeconds ~/ 60).toString().padLeft(2, '0');
    final s = (totalSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  // ---- UI ----
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isRunning = _state == _TimerState.running;
    final isPaused = _state == _TimerState.paused;
    final isIdle = _state == _TimerState.idle;

    return PopScope(
      canPop: _state != _TimerState.running,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final confirm = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('साधना चल रही है'),
            content: const Text('क्या आप ध्यान रोककर बाहर जाना चाहेंगे?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('नहीं'),
              ),
              FilledButton(
                onPressed: () {
                  _stop();
                  Navigator.pop(ctx, true);
                },
                child: const Text('हाँ, रोकें'),
              ),
            ],
          ),
        );
        if (confirm == true && mounted) Navigator.of(context).maybePop();
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Timer'),
          centerTitle: true,
        ),
        body: AnimatedContainer(
          duration: const Duration(milliseconds: 600),
          curve: Curves.easeInOut,
          decoration: BrandGradients.timerBackground(context, isRunning: isRunning),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Advanced controls (collapsible)
                  Card(
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(color: theme.dividerColor),
                    ),
                    child: Theme(
                      // keep it subtle in dark and light
                      data: theme.copyWith(dividerColor: Colors.transparent),
                      child: ExpansionTile(
                        tilePadding: const EdgeInsets.symmetric(horizontal: 12),
                        childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                        initiallyExpanded: false,
                        title: Text('Advanced', style: theme.textTheme.titleMedium),
                        subtitle: Text(
                          '$_selectedMinutes min • $_ambienceLabel',
                          style: theme.textTheme.bodySmall,
                        ),
                        children: [
                          const SizedBox(height: 8),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Text('Select Duration', style: theme.textTheme.labelLarge),
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: _presets.map((m) {
                              final selected = m == _selectedMinutes;
                              return ChoiceChip(
                                label: Text('$m min'),
                                selected: selected,
                                onSelected: (_) => _selectPreset(m),
                              );
                            }).toList(),
                          ),
                          const SizedBox(height: 16),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Text('Ambience', style: theme.textTheme.labelLarge),
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              _soundChip('Mute', TimerSoundType.mute),
                              _soundChip('Om', TimerSoundType.om),
                              _soundChip('Birds', TimerSoundType.birds),
                              _soundChip('Water', TimerSoundType.water),
                              _soundChip('Flute', TimerSoundType.flute),
                              _soundChip('Bell', TimerSoundType.bell),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Time readout
                  Expanded(
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _readout,
                            style: theme.textTheme.displayLarge?.copyWith(
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1.5,
                            ),
                          ),
                          const SizedBox(height: 16),
                          LinearProgressIndicator(
                            value: _progress,
                            minHeight: 10,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _state == _TimerState.completed
                                ? 'Completed'
                                : isRunning
                                ? 'Running'
                                : isPaused
                                ? 'Paused'
                                : 'Ready',
                            style: theme.textTheme.labelLarge,
                          ),
                        ],
                      ),
                    ),
                  ),

                  // Controls
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: (isRunning)
                              ? _pause
                              : (isPaused ? _resume : _start),
                          child: Text(
                            isRunning
                                ? 'Pause'
                                : isPaused
                                ? 'Resume'
                                : 'Start',
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton.tonal(
                          onPressed: (isIdle && _remaining == _total) ? null : _reset,
                          child: const Text('Reset'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
        bottomNavigationBar: const SizedBox(height: 52), // reserved for banner
      ),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      if (_state == _TimerState.running) {
        _pause();
        if (kDebugMode) debugPrint('[Timer] Auto-paused on background.');
      }
    }
  }

  // Helper to build a sound ChoiceChip
  Widget _soundChip(String label, TimerSoundType t) {
    final selected = _selectedSound == t;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => _selectSound(t),
    );
  }

}
