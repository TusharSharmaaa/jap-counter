import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // for light haptics on taps (optional)

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

  // Keep last tick time for drift-free countdown
  DateTime? _lastTickAt;

  @override
  void dispose() {
    _ticker?.cancel();
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

  void _start() {
    if (_state == _TimerState.running) return;
    HapticFeedback.lightImpact();

    setState(() {
      _total = Duration(minutes: _selectedMinutes);
      _remaining = _total;
      _state = _TimerState.running;
      _lastTickAt = DateTime.now();
    });

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
    setState(() {
      _total = Duration(minutes: _selectedMinutes);
      _remaining = _total;
      _state = _TimerState.idle;
    });
  }

  Future<void> _onComplete() async {
    HapticFeedback.mediumImpact();
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

    // ✅ Interstitial hook (to be wired in Step 3D when ads are finalized for Timer)
    // TODO: call your centralized Ad service here (e.g., AdService.instance.maybeShowTimerInterstitial());
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
                      onPressed: (_state == _TimerState.running) ? _pause : (_state == _TimerState.paused ? _resume : _start),
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
}
