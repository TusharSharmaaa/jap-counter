import 'dart:async';

import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../core/ad_manager.dart';
import '../core/sound_manager.dart';
import '../data/meditation_store.dart';
import '../l10n/app_localizations.dart';

enum _TimerState { idle, running, paused, completed }

class TimerPage extends StatefulWidget {
  const TimerPage({super.key});

  @override
  State<TimerPage> createState() => _TimerPageState();
}

class _TimerPageState extends State<TimerPage> with WidgetsBindingObserver {
  // ---- minimal stable state ----
  final List<int> _presets = const [2, 5, 10, 15, 20, 30, 45, 60, 90];
  int _selectedMinutes = 5;
  _TimerState _state = _TimerState.idle;
  Duration _total = const Duration(minutes: 5);
  Duration _remaining = const Duration(minutes: 5);
  Timer? _ticker;
  DateTime? _lastTickAt;

  // ambience placeholder
  String _ambienceId = 'mute';
  bool _visible = false;
  final SoundManager _soundManager = SoundManager.instance;
  final GlobalKey _shareCardKey = GlobalKey();
  bool _shareBusy = false;
  int _todayMinutes = 0;
  int _lifetimeMinutes = 0;

  // ---- lifecycle ----
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    Future.delayed(const Duration(milliseconds: 150), () {
      if (mounted) setState(() => _visible = true);
    });
    unawaited(_initialiseAudio());
    unawaited(_loadMeditationStats());
    unawaited(
      AdManager.instance.preloadPlacement('timer.share_rewarded'),
    );
  }

  Future<void> _initialiseAudio() async {
    await _soundManager.init();
    await _soundManager.setAmbience(_ambienceId);
  }

  Future<void> _loadMeditationStats() async {
    final store = await MeditationStore.create();
    if (!mounted) return;
    setState(() {
      _todayMinutes = store.todayMinutes;
      _lifetimeMinutes = store.lifetimeMinutes;
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ticker?.cancel();
    unawaited(_soundManager.stopAmbience());
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      unawaited(_soundManager.pauseAmbience());
    } else if (state == AppLifecycleState.resumed &&
        _state == _TimerState.running &&
        _ambienceId != 'mute') {
      unawaited(_soundManager.playAmbience());
    }
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

  Future<void> _selectAmbience(String id) async {
    if (_ambienceId == id) return;
    HapticFeedback.selectionClick();
    final safeId = id.toLowerCase();
    setState(() => _ambienceId = safeId);
    if (safeId == 'mute') {
      await _soundManager.stopAmbience();
    } else if (_state == _TimerState.running) {
      await _soundManager.playAmbience(forceId: safeId);
    } else {
      await _soundManager.setAmbience(safeId, preload: true);
    }
  }

  Future<void> _start() async {
    if (_state == _TimerState.running) return;
    HapticFeedback.lightImpact();
    setState(() {
      _total = Duration(minutes: _selectedMinutes);
      _remaining = _total;
      _state = _TimerState.running;
      _lastTickAt = DateTime.now();
    });
    if (_ambienceId != 'mute') {
      await _soundManager.playAmbience(forceId: _ambienceId);
    }
    unawaited(
      AdManager.instance.preloadPlacement('timer.post_session_interstitial'),
    );

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
    unawaited(_soundManager.pauseAmbience());
  }

  Future<void> _resume() async {
    if (_state != _TimerState.paused) return;
    HapticFeedback.lightImpact();
    setState(() {
      _state = _TimerState.running;
      _lastTickAt = DateTime.now();
    });
    if (_ambienceId != 'mute') {
      await _soundManager.playAmbience(forceId: _ambienceId);
    }

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
    unawaited(_soundManager.stopAmbience());
    setState(() {
      _total = Duration(minutes: _selectedMinutes);
      _remaining = _total;
      _state = _TimerState.idle;
    });
  }

  Future<void> _onComplete() async {
    HapticFeedback.mediumImpact();
    await _soundManager.stopAmbience();
    await _soundManager.playBell();
    setState(() {
      _remaining = Duration.zero;
      _state = _TimerState.completed;
    });
    final minutes = _total.inMinutes;
    final medStore = await MeditationStore.create();
    await medStore.addMinutes(minutes);
    if (mounted) {
      setState(() {
        _todayMinutes = medStore.todayMinutes;
        _lifetimeMinutes = medStore.lifetimeMinutes;
      });
    }
    await AdManager.instance.recordEvent(
      'timer.session',
      'complete',
      data: {'minutes': minutes.toDouble()},
    );

    if (!mounted) return;

    final title = context.tr('timer.complete.title');
    final message = context.tr(
      'timer.complete.message',
      args: {'minutes': '$minutes'},
    );
    final okLabel = context.tr('common.ok');

    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) {
        return AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text(okLabel),
            ),
          ],
        );
      },
    );

    if (!mounted) return;
    await AdManager.instance.maybeShowInterstitial(
      'timer.post_session_interstitial',
      timeout: const Duration(milliseconds: 1500),
    );
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

  String get _statusText {
    switch (_state) {
      case _TimerState.running:
        return '🕉️ साधना जारी है...';
      case _TimerState.paused:
        return '⏸️ ध्यान विराम';
      case _TimerState.completed:
        return '🌸 साधना पूर्ण हुई';
      case _TimerState.idle:
      default:
        return '🙏 मन को शांत करें';
    }
  }

  String _formatMinutes(int minutes) {
    final hours = minutes ~/ 60;
    final mins = minutes % 60;
    if (hours > 0) {
      final minPart = mins.toString().padLeft(2, '0');
      return '$hours h ${minPart}m';
    }
    return '$mins m';
  }

  Future<void> _shareMeditation() async {
    if (_shareBusy) return;
    if (!mounted) return;
    setState(() => _shareBusy = true);
    try {
      await AdManager.instance.maybeShowRewarded(
        'timer.share_rewarded',
        timeout: const Duration(milliseconds: 1500),
      );

      await Future.delayed(const Duration(milliseconds: 16));
      final boundary =
          _shareCardKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) {
        throw Exception('Share card not ready');
      }
      final image = await boundary.toImage(pixelRatio: 3.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      final pngBytes = byteData!.buffer.asUint8List();

      final dir = await getTemporaryDirectory();
      final file = File(
        '${dir.path}/timer_share_${DateTime.now().millisecondsSinceEpoch}.png',
      );
      await file.writeAsBytes(pngBytes);

      final shareText = context.tr(
        'timer.share.caption',
        args: {
          'today': _formatMinutes(_todayMinutes),
          'lifetime': _formatMinutes(_lifetimeMinutes),
        },
      );

      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path)],
          text: shareText,
        ),
      );
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('[TimerShare] failed: $e\n$st');
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.tr('timer.share.error'))),
        );
      }
    } finally {
      if (mounted) setState(() => _shareBusy = false);
    }
  }

  Widget _buildShareCard(BuildContext context) {
    final theme = Theme.of(context);
    final todayLabel = context.tr('timer.share.today');
    final lifetimeLabel = context.tr('timer.share.lifetime');
    final title = context.tr('timer.share.cardTitle');
    final subtitle = context.tr('timer.share.subtitle');
    final todayValue = _formatMinutes(_todayMinutes);
    final lifetimeValue = _formatMinutes(_lifetimeMinutes);
    final onPrimary = Colors.white;
    final muted = Colors.white.withOpacity(0.72);

    return RepaintBoundary(
      key: _shareCardKey,
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              theme.colorScheme.primary.withOpacity(0.92),
              theme.colorScheme.secondary.withOpacity(0.75),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: theme.colorScheme.primary.withOpacity(0.25),
              blurRadius: 24,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              title,
              style: theme.textTheme.headlineSmall?.copyWith(
                color: onPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: muted,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: _ShareStatTile(
                    label: todayLabel,
                    value: todayValue,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _ShareStatTile(
                    label: lifetimeLabel,
                    value: lifetimeValue,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Divider(color: onPrimary.withOpacity(0.25), thickness: 1),
            const SizedBox(height: 12),
            Text(
              'Radha Jap Counter',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: onPrimary,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.6,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _ambienceLabel(BuildContext context) {
    return context.tr('timer.ambience.$_ambienceId');
  }

  // ---- UI ----
  @override
  Widget build(BuildContext context) {
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
              child: _HeaderCard(soundLabel: _ambienceLabel(context)),
            ),
            // The rest scrolls if needed (prevents any overflow on small screens)
            Expanded(
              child: SingleChildScrollView(
                physics: const ClampingScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: AnimatedOpacity(
                  opacity: _visible ? 1 : 0,
                  duration: const Duration(milliseconds: 700),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Two-column compact controls: Duration | Ambience
                      LayoutBuilder(
                        builder: (context, c) {
                          final duration = _DurationSection(
                            presets: _presets,
                            selected: _selectedMinutes,
                            onSelect: _selectPreset,
                            enabled: !isRunning,
                          );
                          final sound = _AmbienceSection(
                            selected: _ambienceId,
                            onSelect: _selectAmbience,
                          );
                          return Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(child: duration),
                              const SizedBox(width: 12),
                              Expanded(child: sound),
                            ],
                          );
                        },
                      ),
                      const SizedBox(height: 24),
                      // Big readout + progress
                      _PrimaryTimerCard(
                        readout: _readout,
                        progress: _progress,
                        statusText: _statusText,
                      ),
                      const SizedBox(height: 24),
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
                      const SizedBox(height: 32),
                      _buildShareCard(context),
                      const SizedBox(height: 12),
                      FilledButton.icon(
                        onPressed: _shareBusy ? null : _shareMeditation,
                        icon: _shareBusy
                            ? SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                    Theme.of(context).colorScheme.onPrimary,
                                  ),
                                ),
                              )
                            : const Icon(Icons.ios_share),
                        label: Text(context.tr('timer.share.cta')),
                      ),
                      const SizedBox(height: 48),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// --- small widgets ---
class _PrimaryTimerCard extends StatelessWidget {
  final String readout;
  final double progress;
  final String statusText;

  const _PrimaryTimerCard({
    required this.readout,
    required this.progress,
    required this.statusText,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 20),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: theme.dividerColor.withOpacity(.35)),
        boxShadow: [
          BoxShadow(
            color: theme.colorScheme.shadow.withOpacity(.05),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            readout,
            style: theme.textTheme.displayMedium?.copyWith(
              fontWeight: FontWeight.w600,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 16),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(value: progress, minHeight: 8),
          ),
          const SizedBox(height: 10),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 250),
            child: Text(
              statusText,
              key: ValueKey(statusText),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.primary,
                letterSpacing: .5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HeaderCard extends StatelessWidget {
  final String soundLabel;
  const _HeaderCard({required this.soundLabel});

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
              const Icon(Icons.graphic_eq, size: 18),
              const SizedBox(width: 4),
              Text(soundLabel, style: theme.textTheme.labelLarge),
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
  final bool enabled;
  const _DurationSection({
    required this.presets,
    required this.selected,
    required this.onSelect,
    required this.enabled,
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
      child: DropdownButtonFormField<int>(
        value: selected,
        icon: const Icon(Icons.expand_more),
        decoration: InputDecoration(
          labelText: 'Select time',
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: theme.dividerColor.withOpacity(.6)),
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 14,
          ),
        ),
        items: presets
            .map((m) => DropdownMenuItem(value: m, child: Text('$m minutes')))
            .toList(),
        onChanged: !enabled
            ? null
            : (value) {
                if (value != null) onSelect(value);
              },
      ),
    );
  }
}

typedef AmbienceSelectCallback = Future<void> Function(String id);

class _AmbienceSection extends StatelessWidget {
  final String selected;
  final AmbienceSelectCallback onSelect;
  const _AmbienceSection({required this.selected, required this.onSelect});

  static const _options = ['mute', 'om', 'flute', 'birds', 'water'];

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
      child: DropdownButtonFormField<String>(
        value: selected,
        icon: const Icon(Icons.expand_more),
        decoration: InputDecoration(
          labelText: context.tr('timer.ambience.label'),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: theme.dividerColor.withOpacity(.6)),
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 14,
          ),
        ),
        items: _options
            .map(
              (id) => DropdownMenuItem(
                value: id,
                child: Text(context.tr('timer.ambience.$id')),
              ),
            )
            .toList(),
        onChanged: (value) {
          if (value != null) {
            unawaited(onSelect(value));
          }
        },
      ),
    );
  }
}

class _ShareStatTile extends StatelessWidget {
  final String label;
  final String value;

  const _ShareStatTile({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: Colors.white70,
                fontWeight: FontWeight.w500,
              ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
        ),
      ],
    );
  }
}
