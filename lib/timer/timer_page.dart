import 'dart:async';

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../core/ad_manager.dart';
import '../core/sound_manager.dart';
import '../data/meditation_store.dart';
import '../l10n/app_localizations.dart';
import 'timer_service.dart';

class TimerPage extends StatefulWidget {
  const TimerPage({super.key});

  @override
  State<TimerPage> createState() => _TimerPageState();
}

class _TimerPageState extends State<TimerPage>
    with AutomaticKeepAliveClientMixin, WidgetsBindingObserver {
  // ---- minimal stable state ----
  final List<int> _presets = const [2, 5, 10, 15, 20, 30, 45, 60, 90];
  int _selectedMinutes = TimerService.defaultTarget.inMinutes;
  late final TimerService _timerService;
  String? _activeRunId;
  bool _wasRunning = false;

  // ambience placeholder
  String _ambienceId = 'mute';
  bool _visible = false;
  final SoundManager _soundManager = SoundManager.instance;
  bool _shareBusy = false;
  int _todayMinutes = 0;
  int _lifetimeMinutes = 0;

  @override
  bool get wantKeepAlive => true;

  // ---- lifecycle ----
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _timerService = TimerService();
    _timerService.addListener(_handleServiceUpdate);
    Future.microtask(_bootstrap);
  }

  Future<void> _bootstrap() async {
    await _timerService.load();
    await _soundManager.init();
    _ambienceId = _timerService.sound;
    if (_ambienceId != 'mute') {
      await _soundManager.setAmbience(_ambienceId, preload: true);
      if (_timerService.running) {
        await _soundManager.playAmbience(forceId: _ambienceId);
      }
    } else {
      await _soundManager.setAmbience(_ambienceId);
    }
    _selectedMinutes = _timerService.target.inMinutes;
    _wasRunning = _timerService.running;
    _activeRunId = _timerService.runId.isEmpty ? null : _timerService.runId;

    if (mounted) {
      Future.delayed(const Duration(milliseconds: 150), () {
        if (mounted) setState(() => _visible = true);
      });
    }

    unawaited(_loadMeditationStats());
    unawaited(AdManager.instance.preloadPlacement('timer.share_rewarded'));
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
    _timerService.removeListener(_handleServiceUpdate);
    _timerService.dispose();
    unawaited(_soundManager.stopAmbience());
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      unawaited(_soundManager.pauseAmbience());
    } else if (state == AppLifecycleState.resumed) {
      if (_timerService.running && _ambienceId != 'mute') {
        unawaited(_soundManager.playAmbience(forceId: _ambienceId));
      }
      _timerService.refresh();
    }
  }

  Duration get _remaining => _timerService.remaining;

  Duration get _target => _timerService.target;

  bool get _isRunning => _timerService.running;

  bool get _isIdle => !_timerService.running && _remaining == _target;

  bool get _isCompleted =>
      !_timerService.running && _remaining == Duration.zero;

  bool get _isPaused =>
      !_timerService.running && !_isIdle && !_isCompleted && !_timerService.isPristine;

  bool get _isPristine => _timerService.isPristine;

  void _handleServiceUpdate() {
    final svc = _timerService;
    final nowRunning = svc.running;
    final newMinutes = svc.target.inMinutes;
    final newSound = svc.sound;

    if (_activeRunId != null && svc.consumeCompletion(_activeRunId!)) {
      _activeRunId = null;
      unawaited(_onComplete());
    }

    if (_ambienceId != newSound) {
      if (newSound == 'mute') {
        unawaited(_soundManager.stopAmbience());
      } else if (nowRunning) {
        unawaited(_soundManager.playAmbience(forceId: newSound));
      } else {
        unawaited(_soundManager.setAmbience(newSound, preload: true));
      }
    } else if (!_wasRunning && nowRunning && newSound != 'mute') {
      unawaited(_soundManager.playAmbience(forceId: newSound));
    } else if (_wasRunning && !nowRunning && newSound != 'mute') {
      unawaited(_soundManager.pauseAmbience());
    }

    if (mounted) {
      setState(() {
        _selectedMinutes = newMinutes;
        _ambienceId = newSound;
      });
    }

    _wasRunning = nowRunning;
  }

  // ---- actions (hooks kept simple; you can re-attach sound/ads later) ----
  void _selectPreset(int m) {
    if (_timerService.running) return;
    HapticFeedback.selectionClick();
    _activeRunId = null;
    _selectedMinutes = m;
    unawaited(_timerService.selectDuration(Duration(minutes: m)));
    if (mounted) setState(() {});
  }

  Future<void> _selectAmbience(String id) async {
    if (_timerService.running) return;
    final safeId = id.toLowerCase();
    if (_ambienceId == safeId) return;
    HapticFeedback.selectionClick();
    _ambienceId = safeId;
    if (mounted) setState(() {});
    await _timerService.selectSound(safeId);
  }

  Future<void> _start() async {
    if (_timerService.running) return;
    HapticFeedback.lightImpact();
    final isFreshRun = _timerService.remaining == _timerService.target ||
        _activeRunId == null ||
        _timerService.remaining == Duration.zero;
    if (isFreshRun || (_activeRunId ?? '').isEmpty) {
      _activeRunId = DateTime.now().microsecondsSinceEpoch.toString();
    }
    await _timerService.start(runId: _activeRunId);
    if (_ambienceId != 'mute') {
      await _soundManager.playAmbience(forceId: _ambienceId);
    }
    unawaited(
      AdManager.instance.preloadPlacement('timer.post_session_interstitial'),
    );
    if (mounted) setState(() {});
  }

  Future<void> _pause() async {
    if (!_timerService.running) return;
    HapticFeedback.selectionClick();
    await _timerService.pause();
    await _soundManager.pauseAmbience();
    if (mounted) setState(() {});
  }

  Future<void> _resume() async {
    if (_timerService.running || _timerService.remaining == Duration.zero) {
      return;
    }
    return _start();
  }

  Future<void> _reset() async {
    HapticFeedback.selectionClick();
    _activeRunId = null;
    await _timerService.reset();
    await _soundManager.stopAmbience();
    if (mounted) setState(() {});
  }

  Future<void> _onComplete() async {
    HapticFeedback.mediumImpact();
    await _soundManager.stopAmbience();
    await _soundManager.playBell();
    final minutes = _timerService.target.inMinutes;
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

    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Meditation complete'),
          content: const Text('Your session has finished.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('OK'),
            ),
          ],
        );
      },
    );

    if (!mounted) return;
    _activeRunId = null;
    await AdManager.instance.maybeShowInterstitial(
      'timer.post_session_interstitial',
    );
  }

  // ---- derived ----
  double get _progress => _timerService.progress;

  String get _readout {
    final s = _remaining.inSeconds.clamp(0, 24 * 60 * 60);
    final m = (s ~/ 60).toString().padLeft(2, '0');
    final ss = (s % 60).toString().padLeft(2, '0');
    return '$m:$ss';
  }

  String get _statusText {
    if (_timerService.running) {
      return '🕉️ साधना जारी है...';
    }
    if (_isCompleted) {
      return '🌸 Meditation complete';
    }
    if (_isPaused) {
      return '⏸️ ध्यान विराम';
    }
    return '🙏 मन को शांत करें';
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

    final caption = context.tr(
      'timer.share.caption',
      args: {
        'today': _formatMinutes(_todayMinutes),
        'lifetime': _formatMinutes(_lifetimeMinutes),
      },
    );
    final messenger = ScaffoldMessenger.of(context);
    final successLabel = context.tr('common.share');

    try {
      final adShown = await AdManager.instance.maybeShowRewarded(
        'timer.share_rewarded',
        timeout: const Duration(seconds: 8),
      );
      unawaited(
        AdManager.instance.recordEvent(
          'timer.share_rewarded',
          'attempt',
          data: {'ad_shown': adShown},
        ),
      );
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('[TimerShare] rewarded load failed: $e\n$st');
      }
    }

    if (!mounted) {
      setState(() => _shareBusy = false);
      return;
    }

    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _TimerShareSheet(
        todayMinutes: _todayMinutes,
        lifetimeMinutes: _lifetimeMinutes,
        caption: caption,
      ),
    );

    if (result == true && mounted) {
      messenger.showSnackBar(
        SnackBar(
          content: Text('$successLabel ✓'),
          duration: const Duration(seconds: 2),
        ),
      );
    }

    if (mounted) setState(() => _shareBusy = false);
  }

  String _ambienceLabel(BuildContext context) {
    return context.tr('timer.ambience.$_ambienceId');
  }

  // ---- UI ----
  @override
  Widget build(BuildContext context) {
    super.build(context);
    return ChangeNotifierProvider<TimerService>.value(
      value: _timerService,
      child: Consumer<TimerService>(
        builder: (context, svc, _) {
          final isRunning = svc.running;
          final remaining = svc.remaining;
          final target = svc.target;
          final isIdle = !isRunning && remaining == target;
          final isCompleted = !isRunning && remaining == Duration.zero;
          final isPaused =
              !isRunning && !isIdle && !isCompleted && !svc.isPristine;

          VoidCallback? primaryAction;
          if (isRunning) {
            primaryAction = () => unawaited(_pause());
          } else if (isPaused) {
            primaryAction = () => unawaited(_resume());
          } else {
            primaryAction = () => unawaited(_start());
          }

          final primaryLabel =
              isRunning ? 'Pause' : (isPaused ? 'Resume' : 'Start');
          final resetAction =
              (isIdle && svc.isPristine) ? null : () => unawaited(_reset());

          return Scaffold(
            appBar: AppBar(title: const Text('Timer'), centerTitle: true),
            body: SafeArea(
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                    child: _HeaderCard(soundLabel: _ambienceLabel(context)),
                  ),
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
                            LayoutBuilder(
                              builder: (context, _) {
                                final duration = _DurationSection(
                                  presets: _presets,
                                  selected: _selectedMinutes,
                                  onSelect: _selectPreset,
                                  enabled: !isRunning,
                                );
                                final sound = _AmbienceSection(
                                  selected: _ambienceId,
                                  onSelect: _selectAmbience,
                                  enabled: !isRunning,
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
                            _PrimaryTimerCard(
                              readout: _readout,
                              progress: _progress,
                              statusText: _statusText,
                            ),
                            const SizedBox(height: 24),
                            Row(
                              children: [
                                Expanded(
                                  child: FilledButton(
                                    onPressed: primaryAction,
                                    child: Text(primaryLabel),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: OutlinedButton(
                                    onPressed: resetAction,
                                    child: const Text('Reset'),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 32),
                            FilledButton.icon(
                              onPressed: _shareBusy ? null : _shareMeditation,
                              icon: _shareBusy
                                  ? SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        valueColor:
                                            AlwaysStoppedAnimation<Color>(
                                          Theme.of(context)
                                              .colorScheme
                                              .onPrimary,
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
        },
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

class _AmbienceSection extends StatelessWidget {
  final String selected;
  final Future<void> Function(String id) onSelect;
  final bool enabled;
  const _AmbienceSection({
    required this.selected,
    required this.onSelect,
    required this.enabled,
  });

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
        onChanged: !enabled
            ? null
            : (value) {
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

class _TimerShareCard extends StatelessWidget {
  final String todayValue;
  final String lifetimeValue;

  const _TimerShareCard({
    required this.todayValue,
    required this.lifetimeValue,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final todayLabel = context.tr('timer.share.today');
    final lifetimeLabel = context.tr('timer.share.lifetime');
    final title = context.tr('timer.share.cardTitle');
    final subtitle = context.tr('timer.share.subtitle');
    final onPrimary = Colors.white;
    final muted = Colors.white.withOpacity(0.72);

    return Container(
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
                child: _ShareStatTile(label: todayLabel, value: todayValue),
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
    );
  }
}

class _TimerShareSheet extends StatefulWidget {
  final int todayMinutes;
  final int lifetimeMinutes;
  final String caption;

  const _TimerShareSheet({
    required this.todayMinutes,
    required this.lifetimeMinutes,
    required this.caption,
  });

  @override
  State<_TimerShareSheet> createState() => _TimerShareSheetState();
}

class _TimerShareSheetState extends State<_TimerShareSheet> {
  final GlobalKey _cardKey = GlobalKey();
  bool _sharing = false;

  Future<void> _handleShare() async {
    if (_sharing) return;
    setState(() => _sharing = true);
    final messenger = ScaffoldMessenger.of(context);
    final errorText = context.tr('timer.share.error');

    try {
      await Future.delayed(Duration.zero);
      await WidgetsBinding.instance.endOfFrame;
      final ctx = _cardKey.currentContext;
      final render = ctx?.findRenderObject();
      if (render is! RenderRepaintBoundary) {
        throw Exception('Share boundary not ready');
      }
      final boundary = render;
      final image = await boundary.toImage(pixelRatio: 3.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      final pngBytes = byteData!.buffer.asUint8List();

      final dir = await getTemporaryDirectory();
      final file = File(
        '${dir.path}/timer_share_${DateTime.now().millisecondsSinceEpoch}.png',
      );
      await file.writeAsBytes(pngBytes);
      AdManager.instance.recordEvent(
        'timer.share_rewarded',
        'share_card_generated',
      );

      await SharePlus.instance.share(
        ShareParams(files: [XFile(file.path)], text: widget.caption),
      );
      AdManager.instance.recordEvent(
        'timer.share_rewarded',
        'share_intent_launched',
      );
      unawaited(AdManager.instance.preloadPlacement('timer.share_rewarded'));
      if (mounted) Navigator.of(context).pop(true);
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('[TimerShareSheet] share failed: $e\n$st');
      }
      if (mounted) {
        messenger.showSnackBar(SnackBar(content: Text(errorText)));
      }
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final todayValue = _formatMinutes(widget.todayMinutes);
    final lifetimeValue = _formatMinutes(widget.lifetimeMinutes);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.12),
              blurRadius: 24,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: SafeArea(
          child: Padding(
            padding: EdgeInsets.only(
              left: 20,
              right: 20,
              top: 20,
              bottom: MediaQuery.of(context).padding.bottom + 28,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                RepaintBoundary(
                  key: _cardKey,
                  child: _TimerShareCard(
                    todayValue: todayValue,
                    lifetimeValue: lifetimeValue,
                  ),
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: _sharing ? null : _handleShare,
                  icon: _sharing
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
                  label: Text(context.tr('common.share')),
                ),
              ],
            ),
          ),
        ),
      ),
    );
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
}
