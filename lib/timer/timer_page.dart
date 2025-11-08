import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

enum _TimerState { idle, running, paused, completed }

class TimerPage extends StatefulWidget {
  const TimerPage({super.key});

  @override
  State<TimerPage> createState() => _TimerPageState();
}

class _TimerPageState extends State<TimerPage> {
  // ---- minimal stable state ----
  final List<int> _presets = const [5, 10, 15, 20, 30, 45, 60, 90];
  int _selectedMinutes = 5;
  _TimerState _state = _TimerState.idle;
  Duration _total = const Duration(minutes: 5);
  Duration _remaining = const Duration(minutes: 5);
  Timer? _ticker;
  DateTime? _lastTickAt;

  // ambience placeholder
  String _ambience = 'Om';

  // ---- lifecycle ----
  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  // ---- actions (hooks kept simple; you can re-attach sound/ads later) ----
  void _selectPreset(int m) {
    if (_state == _TimerState.running) return;
    HapticFeedback.selectionClick();
    setState(() {
      _selectedMinutes = m;
      _total = Duration(minutes: m);
      _remaining = _total;
      _state = _TimerState.idle;
    });
  }

  void _selectAmbience(String a) {
    if (_ambience == a) return;
    HapticFeedback.selectionClick();
    setState(() => _ambience = a);
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
        if (mounted) setState(() => _remaining = next);
      }
    });
  }

  void _pause() {
    if (_state != _TimerState.running) return;
    HapticFeedback.selectionClick();
    _ticker?.cancel();
    setState(() => _state = _TimerState.paused);
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
        if (mounted) setState(() => _remaining = next);
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
    setState(() {
      _remaining = Duration.zero;
      _state = _TimerState.completed;
    });
    // TODO: play gentle bell (fade-in), show summary dialog, then native ad
    // Keep this minimal for stability right now.
  }

  // ---- derived ----
  double get _progress {
    if (_total.inMilliseconds == 0) return 0;
    final done = _total.inMilliseconds - _remaining.inMilliseconds;
    return (done / _total.inMilliseconds).clamp(0, 1).toDouble();
  }

  String get _readout {
    final s = _remaining.inSeconds.clamp(0, 24 * 60 * 60);
    final m = (s ~/ 60).toString().padLeft(2, '0');
    final ss = (s % 60).toString().padLeft(2, '0');
    return '$m:$ss';
  }

  // ---- UI ----
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isRunning = _state == _TimerState.running;
    final isPaused = _state == _TimerState.paused;
    final isIdle = _state == _TimerState.idle;

    return Scaffold(
      appBar: AppBar(title: const Text('Timer'), centerTitle: true),
      body: SafeArea(
        child: Column(
          children: [
            // Header card
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: _HeaderCard(ambience: _ambience),
            ),
            // The rest scrolls if needed (prevents any overflow on small screens)
            Expanded(
              child: SingleChildScrollView(
                physics: const ClampingScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Two-column compact controls: Duration | Ambience
                    LayoutBuilder(
                      builder: (context, c) {
                        final isNarrow = c.maxWidth < 520;
                        if (isNarrow) {
                          return Column(
                            children: [
                              _DurationSection(
                                presets: _presets,
                                selected: _selectedMinutes,
                                onSelect: _selectPreset,
                              ),
                              const SizedBox(height: 12),
                              _AmbienceSection(
                                selected: _ambience,
                                onSelect: _selectAmbience,
                              ),
                            ],
                          );
                        }
                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: _DurationSection(
                                presets: _presets,
                                selected: _selectedMinutes,
                                onSelect: _selectPreset,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _AmbienceSection(
                                selected: _ambience,
                                onSelect: _selectAmbience,
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                    const SizedBox(height: 18),
                    // Big readout + progress
                    Container(
                      padding: const EdgeInsets.symmetric(vertical: 20),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: theme.dividerColor.withOpacity(.4),
                        ),
                      ),
                      child: Column(
                        children: [
                          Text(
                            _readout,
                            style: theme.textTheme.displayLarge?.copyWith(
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1.5,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: LinearProgressIndicator(
                              value: _progress,
                              minHeight: 10,
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          const SizedBox(height: 6),
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
                    const SizedBox(height: 16),
                    // Controls
                    Row(
                      children: [
                        Expanded(
                          child: FilledButton(
                            onPressed: isRunning
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
                          child: OutlinedButton(
                            onPressed: (isIdle && _remaining == _total)
                                ? null
                                : _reset,
                            child: const Text('Reset'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: const SizedBox(height: 52), // banner reserve
    );
  }
}

// --- small widgets ---
class _HeaderCard extends StatelessWidget {
  final String ambience;
  const _HeaderCard({required this.ambience});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.dividerColor.withOpacity(.4)),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: theme.colorScheme.primary.withOpacity(.12),
            ),
            child: const Icon(Icons.spa),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Meditation Timer', style: theme.textTheme.titleMedium),
                Text(
                  'भक्ति में ध्यान, ध्यान में शांति।',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.music_note, size: 18),
              const SizedBox(width: 4),
              Text(ambience, style: theme.textTheme.labelLarge),
            ],
          ),
        ],
      ),
    );
  }
}

class _DurationSection extends StatelessWidget {
  final List<int> presets;
  final int selected;
  final ValueChanged<int> onSelect;
  const _DurationSection({
    required this.presets,
    required this.selected,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.dividerColor.withOpacity(.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Duration', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: presets.map((m) {
              final s = m == selected;
              return ChoiceChip(
                label: Text('${m}m'),
                selected: s,
                onSelected: (_) => onSelect(m),
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}

class _AmbienceSection extends StatelessWidget {
  final String selected;
  final ValueChanged<String> onSelect;
  const _AmbienceSection({required this.selected, required this.onSelect});

  static const _items = ['Om', 'Flute', 'Birds', 'Water', 'Bell', 'Silent'];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.dividerColor.withOpacity(.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Ambience', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _items.map((name) {
              final s = name == selected;
              return ChoiceChip(
                label: Text(name),
                selected: s,
                onSelected: (_) => onSelect(name),
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}
