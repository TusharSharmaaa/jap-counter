import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // for light haptics on taps (optional)
import 'timer_sound_controller.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../ads/interstitial_timer.dart';

enum _TimerState { idle, running, paused, completed }

class TimerPage extends StatefulWidget {
  const TimerPage({super.key});

  @override
  State<TimerPage> createState() => _TimerPageState();
}

class _TimerPageState extends State<TimerPage> with TickerProviderStateMixin {
  final List<int> _presets = const [5, 10, 15, 20, 30, 45, 60, 90]; // minutes
  int _selectedMinutes = 10;

  Duration _total = const Duration(minutes: 10);
  Duration _remaining = const Duration(minutes: 10);
  Timer? _ticker;
  _TimerState _state = _TimerState.idle;

  // 🔊 Sound controller + current ambience selection
  final TimerSoundController _sound = TimerSoundController();
  TimerSoundType _selectedSound = TimerSoundType.mute;

  // Keep last tick time for drift-free countdown
  DateTime? _lastTickAt;

  @override
  void initState() {
    super.initState();
    _sound.setSound(_selectedSound); // already there
    // preload interstitial for post-completion
    TimerInterstitialGate.instance.preload();
  }


  @override
  void dispose() {
    _ticker?.cancel();
    WakelockPlus.disable();      // ensure screen can sleep
    _sound.dispose();            // stop & release audio
    super.dispose();
  }

  void _selectPreset(int minutes) {
    if (_state == _TimerState.running) return;
    HapticFeedback.selectionClick();
    setState(() {
      _selectedMinutes = minutes;
      _total = Duration(minutes: minutes);
      _remaining = _total;
      _state = _TimerState.idle;
    });
  }

  void _selectSound(TimerSoundType t) {
    if (_selectedSound == t) return;
    HapticFeedback.selectionClick();
    setState(() => _selectedSound = t);
    // Preload the chosen sound; no auto-play
    _sound.setSound(t);
  }

  void _start() {
    if (_state == _TimerState.running) return;
    HapticFeedback.lightImpact();

    setState(() {
      _total = Duration(minutes: _selectedMinutes);
      _remaining = _total;
      _state = _TimerState.running;
      _lastTickAt = DateTime.now();
    });

    // Keep the screen awake while running
    WakelockPlus.enable();

    // 🔊 start ambience if not muted
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

    // Allow screen to sleep when paused
    WakelockPlus.disable();

    // 🔊 pause sound
    _sound.pause();
    setState(() {
      _state = _TimerState.paused;
    });
  }

  void _resume() {
    if (_state != _TimerState.paused) return;
    HapticFeedback.lightImpact();
    setState(() {
      _state = _TimerState.running;
      _lastTickAt = DateTime.now();
    });

    // Keep screen awake again
    WakelockPlus.enable();

    // 🔊 resume sound
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

  void _reset() {
    HapticFeedback.selectionClick();
    _ticker?.cancel();

    // Allow screen to sleep on reset
    WakelockPlus.disable();

    // 🔊 stop sound
    _sound.stop();
    setState(() {
      _total = Duration(minutes: _selectedMinutes);
      _remaining = _total;
      _state = _TimerState.idle;
    });
  }

  Future<void> _onComplete() async {
    HapticFeedback.mediumImpact();

    // Allow screen to sleep after completion
    WakelockPlus.disable();

    // 🔊 stop sound on completion
    _sound.stop();

    setState(() {
      _remaining = Duration.zero;
      _state = _TimerState.completed;
    });

    if (mounted) {
      await showDialog<void>(
        context: context,
        barrierDismissible: true,
        builder: (context) {
          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: const Text('साधना पूर्ण हुई'),
            content: Text(
              'आपने ${_formatDuration(_total)} ध्यान पूर्ण किया।',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).maybePop(),
                child: const Text('ठीक है'),
              ),
            ],
          );
        },
      );
    }

    // After dialog: try interstitial once per session
    await TimerInterstitialGate.instance.maybeShow();


}

  double get _progress {
    if (_total.inMilliseconds == 0) return 0;
    final done = _total.inMilliseconds - _remaining.inMilliseconds;
    return (done / _total.inMilliseconds).clamp(0, 1).toDouble();
  }

  String get _readout => _formatDuration(_remaining);

  static String _formatDuration(Duration d) {
    final totalSeconds = d.inSeconds.clamp(0, 24 * 60 * 60);
    final m = (totalSeconds ~/ 60).toString().padLeft(2, '0');
    final s = (totalSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isRunning = _state == _TimerState.running;
    final isPaused = _state == _TimerState.paused;
    final isIdle = _state == _TimerState.idle;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Timer'),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Preset selector
              Text('Select Duration', style: theme.textTheme.titleMedium),
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

              // 🔊 Ambience selector (Mute / Om / Birds / Water / Flute / Bell)
              Text('Ambience', style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _soundChip('Mute',  TimerSoundType.mute),
                  _soundChip('Om',    TimerSoundType.om),
                  _soundChip('Birds', TimerSoundType.birds),
                  _soundChip('Water', TimerSoundType.water),
                  _soundChip('Flute', TimerSoundType.flute),
                  _soundChip('Bell',  TimerSoundType.bell),
                ],
              ),

              const SizedBox(height: 24),

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
    );
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
