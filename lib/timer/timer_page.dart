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
import 'package:wakelock_plus/wakelock_plus.dart';

import '../core/ad_manager.dart';
import '../core/sound_manager.dart';
import '../data/meditation_store.dart';
import '../l10n/app_localizations.dart';
import '../theme/responsive_tokens.dart';
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
  TimerService? _timerServiceInstance;
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
  TimerService get _timerService {
    final svc = _timerServiceInstance;
    assert(svc != null, 'TimerService accessed before initialization');
    return svc!;
  }

  bool _timerServiceAttached = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final svc = Provider.of<TimerService>(context, listen: false);
    if (!identical(_timerServiceInstance, svc)) {
      _timerServiceInstance?.removeListener(_handleServiceUpdate);
      _timerServiceInstance = svc;
      _timerServiceInstance?.addListener(_handleServiceUpdate);
      if (!_timerServiceAttached) {
        _timerServiceAttached = true;
        Future.microtask(_bootstrap);
      } else {
        _handleServiceUpdate();
      }
    }
  }

  Future<void> _bootstrap() async {
    _applyServiceSnapshot();
    _revealContent();
    if (mounted) setState(() {});

    final soundInit = _soundManager.init();

    unawaited(_ensureWakelockActive(_timerService.running));
    unawaited(_syncAmbience(soundInit));
    unawaited(_loadMeditationStats());
    unawaited(AdManager.instance.preloadPlacement('timer.share_rewarded'));
  }

  void _applyServiceSnapshot() {
    final svc = _timerService;
    _ambienceId = svc.sound;
    _selectedMinutes = svc.target.inMinutes;
    _wasRunning = svc.running;
    _activeRunId = svc.runId.isEmpty ? null : svc.runId;
  }

  Future<void> _syncAmbience(Future<void> soundInit) async {
    try {
      await soundInit;
      final targetSound = _timerService.sound;
      if (targetSound != 'mute') {
        await _soundManager.setAmbience(targetSound, preload: true);
        if (_timerService.running) {
          await _soundManager.playAmbience(forceId: targetSound);
        }
      } else {
        await _soundManager.setAmbience(targetSound);
      }
      unawaited(_ensureWakelockActive(_timerService.running));
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('[TimerPage] ambience sync failed: $e\n$st');
      }
    }
  }

  Future<void> _ensureWakelockActive(bool active) async {
    try {
      if (active) {
        await WakelockPlus.enable();
      } else {
        await WakelockPlus.disable();
      }
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('[TimerPage] Wakelock toggle failed: $e\n$st');
      }
    }
  }

  Future<void> _safeSoundCall(Future<void> Function() operation) async {
    try {
      await operation();
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('[TimerPage] Sound operation failed: $e\n$st');
      }
    }
  }

  void _revealContent() {
    if (_visible) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_visible) {
        setState(() => _visible = true);
      }
    });
  }

  Future<void> _loadMeditationStats() async {
    final store = await MeditationStore.create();
    if (!mounted) return;
    setState(() {
      _todayMinutes = store.todayMinutes;
      _lifetimeMinutes = store.lifetimeMinutes;
    });
  }

  Future<void> _pauseForInterruption() async {
    final wasRunning = _timerService.running;
    if (wasRunning) {
      await _timerService.pause();
      await _safeSoundCall(() => _soundManager.pauseAmbience());
      _wasRunning = false;
      await _ensureWakelockActive(false);
    }
    await _commitProgress();
    if (wasRunning && mounted) {
      setState(() {});
    }
  }

  Future<void> _commitProgress({bool forceFull = false}) async {
    final minutes = await _timerService.captureUncreditedMinutes(
      forceFull: forceFull,
    );
    if (minutes <= 0) return;
    final store = await MeditationStore.create();
    await store.addMinutes(minutes);
    if (!mounted) return;
    setState(() {
      _todayMinutes = store.todayMinutes;
      _lifetimeMinutes = store.lifetimeMinutes;
    });
  }

  Future<void> _finalizeSessionOnExit() async {
    await _pauseForInterruption();
    await _ensureWakelockActive(false);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timerServiceInstance?.removeListener(_handleServiceUpdate);
    if (!(_timerServiceInstance?.running ?? false)) {
      unawaited(_safeSoundCall(() => _soundManager.stopAmbience()));
      unawaited(_ensureWakelockActive(false));
    }
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      unawaited(_pauseForInterruption());
    } else if (state == AppLifecycleState.detached) {
      unawaited(_finalizeSessionOnExit());
    } else if (state == AppLifecycleState.resumed) {
      _applyServiceSnapshot();
      if (mounted) setState(() {});
      if (_timerService.running && _ambienceId != 'mute') {
        unawaited(
          _safeSoundCall(
            () => _soundManager.playAmbience(forceId: _ambienceId),
          ),
        );
      }
      _timerService.refresh();
      unawaited(_ensureWakelockActive(_timerService.running));
    }
  }

  Duration get _remaining => _timerService.remaining;

  Duration get _target => _timerService.target;

  bool get _isRunning => _timerService.running;

  bool get _isIdle => !_timerService.running && _remaining == _target;

  bool get _isCompleted =>
      !_timerService.running && _remaining == Duration.zero;

  bool get _isPaused =>
      !_timerService.running &&
      !_isIdle &&
      !_isCompleted &&
      !_timerService.isPristine;

  bool get _isPristine => _timerService.isPristine;

  void _handleServiceUpdate() {
    final svc = _timerService;
    final nowRunning = svc.running;
    final newMinutes = svc.target.inMinutes;
    final newSound = svc.sound;
    final currentRunId = svc.runId;

    if (_activeRunId != null && svc.consumeCompletion(_activeRunId!)) {
      _activeRunId = null;
      unawaited(_onComplete());
    }

    if (_ambienceId != newSound) {
      if (newSound == 'mute') {
        unawaited(_safeSoundCall(() => _soundManager.stopAmbience()));
      } else if (nowRunning) {
        unawaited(
          _safeSoundCall(() => _soundManager.playAmbience(forceId: newSound)),
        );
      } else {
        unawaited(
          _safeSoundCall(
            () => _soundManager.setAmbience(newSound, preload: true),
          ),
        );
      }
    } else if (!_wasRunning && nowRunning && newSound != 'mute') {
      unawaited(
        _safeSoundCall(() => _soundManager.playAmbience(forceId: newSound)),
      );
    } else if (_wasRunning && !nowRunning && newSound != 'mute') {
      unawaited(_safeSoundCall(() => _soundManager.pauseAmbience()));
    }

    if (mounted) {
      setState(() {
        _selectedMinutes = newMinutes;
        _ambienceId = newSound;
        _activeRunId = currentRunId.isEmpty ? null : currentRunId;
      });
    }

    if (!_wasRunning && nowRunning) {
      unawaited(_ensureWakelockActive(true));
    } else if (_wasRunning && !nowRunning) {
      unawaited(_ensureWakelockActive(false));
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
    final safeId = id.toLowerCase();
    if (_ambienceId == safeId) return;
    HapticFeedback.selectionClick();
    if (mounted) {
      setState(() {
        _ambienceId = safeId;
      });
    } else {
      _ambienceId = safeId;
    }
    await _timerService.selectSound(safeId);
    if (_timerService.running) {
      if (safeId == 'mute') {
        await _safeSoundCall(() => _soundManager.stopAmbience());
      } else {
        await _safeSoundCall(
          () => _soundManager.setAmbience(safeId, preload: true),
        );
        await _safeSoundCall(() => _soundManager.playAmbience(forceId: safeId));
      }
    } else {
      await _safeSoundCall(
        () => _soundManager.setAmbience(safeId, preload: true),
      );
    }
    unawaited(_ensureWakelockActive(_timerService.running));
  }

  Future<void> _start() async {
    if (_timerService.running) return;
    HapticFeedback.lightImpact();
    final isFreshRun =
        _timerService.remaining == _timerService.target ||
        _activeRunId == null ||
        _timerService.remaining == Duration.zero;
    if (isFreshRun || (_activeRunId ?? '').isEmpty) {
      _activeRunId = DateTime.now().microsecondsSinceEpoch.toString();
    }
    if (_ambienceId != 'mute') {
      await _safeSoundCall(
        () => _soundManager.setAmbience(_ambienceId, preload: true),
      );
    } else {
      await _safeSoundCall(() => _soundManager.stopAmbience());
    }
    await _timerService.start(runId: _activeRunId);
    await _ensureWakelockActive(true);
    unawaited(
      AdManager.instance.preloadPlacement('timer.post_session_interstitial'),
    );
    if (mounted) setState(() {});
  }

  Future<void> _pause() async {
    if (!_timerService.running) return;
    HapticFeedback.selectionClick();
    await _timerService.pause();
    await _safeSoundCall(() => _soundManager.pauseAmbience());
    await _ensureWakelockActive(false);
    await _commitProgress();
    if (mounted) setState(() {});
  }

  Future<void> _resume() async {
    if (_timerService.running || _timerService.remaining == Duration.zero) {
      return;
    }
    final existingRunId = _timerService.runId;
    if ((_activeRunId ?? '').isEmpty) {
      _activeRunId = existingRunId.isNotEmpty
          ? existingRunId
          : DateTime.now().microsecondsSinceEpoch.toString();
    }
    if (_ambienceId != 'mute') {
      await _safeSoundCall(
        () => _soundManager.setAmbience(_ambienceId, preload: true),
      );
    } else {
      await _safeSoundCall(() => _soundManager.stopAmbience());
    }
    await _timerService.resume(runId: _activeRunId);
    await _ensureWakelockActive(true);
    unawaited(
      AdManager.instance.preloadPlacement('timer.post_session_interstitial'),
    );
    if (mounted) setState(() {});
  }

  Future<void> _reset() async {
    HapticFeedback.selectionClick();
    if (_timerService.running) {
      await _timerService.pause();
      await _safeSoundCall(() => _soundManager.pauseAmbience());
    }
    await _ensureWakelockActive(false);
    await _commitProgress();
    _activeRunId = null;
    await _timerService.reset();
    await _safeSoundCall(() => _soundManager.stopAmbience());
    if (mounted) setState(() {});
  }

  Future<void> _onComplete() async {
    HapticFeedback.mediumImpact();
    await _safeSoundCall(() => _soundManager.stopAmbience());
    await _safeSoundCall(() => _soundManager.playBell());
    await _ensureWakelockActive(false);
    final addedMinutes = await _timerService.captureUncreditedMinutes(
      forceFull: true,
    );
    final targetMinutes = _timerService.target.inMinutes;
    if (addedMinutes > 0) {
      final medStore = await MeditationStore.create();
      await medStore.addMinutes(addedMinutes);
      if (mounted) {
        setState(() {
          _todayMinutes = medStore.todayMinutes;
          _lifetimeMinutes = medStore.lifetimeMinutes;
        });
      }
    }
    await AdManager.instance.recordEvent(
      'timer.session',
      'complete',
      data: {'minutes': targetMinutes.toDouble()},
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
      if (kDebugMode) {
        debugPrint('[TimerShare] maybeShowRewarded -> shown=$adShown');
      }
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
    if (kDebugMode) {
      debugPrint('[TimerShare] share sheet closed -> result=$result');
    }

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
    return Consumer<TimerService>(
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

        final primaryLabel = isRunning
            ? 'Pause'
            : (isPaused ? 'Resume' : 'Start');
        final resetAction = (isIdle && svc.isPristine)
            ? null
            : () => unawaited(_reset());

        return Scaffold(
          appBar: AppBar(title: const Text('Timer'), centerTitle: true),
          body: SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    ResponsiveTokens.spacingMD,
                    ResponsiveTokens.spacingSM + 4,
                    ResponsiveTokens.spacingMD,
                    ResponsiveTokens.spacingSM,
                  ),
                  child: _HeaderCard(soundLabel: _ambienceLabel(context)),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    physics: const ClampingScrollPhysics(),
                    padding: EdgeInsets.fromLTRB(
                      ResponsiveTokens.spacingMD,
                      ResponsiveTokens.spacingSM,
                      ResponsiveTokens.spacingMD,
                      ResponsiveTokens.spacingMD,
                    ),
                    child: AnimatedOpacity(
                      opacity: _visible ? 1 : 0,
                      duration: const Duration(milliseconds: 700),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          LayoutBuilder(
                            builder: (context, constraints) {
                              final isNarrow = constraints.maxWidth < 420;
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
                              
                              // Stack vertically on narrow screens to prevent overflow
                              if (isNarrow) {
                                return Column(
                                  crossAxisAlignment: CrossAxisAlignment.stretch,
                                  children: [
                                    duration,
                                    SizedBox(height: ResponsiveTokens.spacingSM),
                                    sound,
                                  ],
                                );
                              }
                              
                              return Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(child: duration),
                                  SizedBox(width: ResponsiveTokens.spacingSM),
                                  Expanded(child: sound),
                                ],
                              );
                            },
                          ),
                          SizedBox(height: ResponsiveTokens.spacingLG),
                          _PrimaryTimerCard(
                            readout: _readout,
                            progress: _progress,
                            statusText: _statusText,
                            isPaused: isPaused,
                          ),
                          SizedBox(height: ResponsiveTokens.spacingLG),
                          Row(
                            children: [
                              Expanded(
                                child: FilledButton(
                                  onPressed: primaryAction,
                                  style: FilledButton.styleFrom(
                                    backgroundColor: isPaused 
                                        ? const Color(0xFF6B2C91) // Dark purple for Resume
                                        : Theme.of(context).colorScheme.primary,
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(vertical: 16),
                                  ),
                                  child: Text(primaryLabel),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: OutlinedButton(
                                  onPressed: resetAction,
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: const Color(0xFF6B2C91),
                                    side: const BorderSide(color: Color(0xFF6B2C91), width: 1.5),
                                    padding: const EdgeInsets.symmetric(vertical: 16),
                                  ),
                                  child: const Text('Reset'),
                                ),
                              ),
                            ],
                          ),
                          SizedBox(height: ResponsiveTokens.spacingMD * 2),
                          FilledButton.icon(
                            onPressed: _shareBusy ? null : _shareMeditation,
                            style: FilledButton.styleFrom(
                              backgroundColor: const Color(0xFF6B2C91),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                            ),
                            icon: _shareBusy
                                ? SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      valueColor: const AlwaysStoppedAnimation<Color>(
                                        Colors.white,
                                      ),
                                    ),
                                  )
                                : const Icon(Icons.ios_share, color: Colors.white),
                            label: Text(
                              context.tr('timer.share.cta'),
                              style: const TextStyle(color: Colors.white),
                            ),
                          ),
                          SizedBox(height: ResponsiveTokens.spacingXL),
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
    );
  }
}

// --- small widgets ---
class _PrimaryTimerCard extends StatelessWidget {
  final String readout;
  final double progress;
  final String statusText;
  final bool isPaused;

  const _PrimaryTimerCard({
    required this.readout,
    required this.progress,
    required this.statusText,
    required this.isPaused,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        return Container(
          padding: EdgeInsets.symmetric(
            vertical: ResponsiveTokens.spacingLG,
            horizontal: constraints.maxWidth < 360 
                ? ResponsiveTokens.spacingMD 
                : 20,
          ),
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
                style: theme.textTheme.displayLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.2,
                  fontSize: 48,
                ),
              ),
              SizedBox(height: ResponsiveTokens.spacingMD),
              ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 8,
                  backgroundColor: const Color(0xFFFFE5E5), // Light pink/red
                  valueColor: const AlwaysStoppedAnimation<Color>(
                    Color(0xFFD32F2F), // Dark red/pink
                  ),
                ),
              ),
              SizedBox(height: ResponsiveTokens.spacingSM + 2),
              if (isPaused)
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.pause,
                      size: 18,
                      color: const Color(0xFFFF6B35), // Orange pause icon
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'ध्यान विराम',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: Colors.black87,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                )
              else
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
      },
    );
  }
}

class _HeaderCard extends StatelessWidget {
  final String soundLabel;
  const _HeaderCard({required this.soundLabel});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < 360;
        return Container(
          padding: EdgeInsets.all(isNarrow ? ResponsiveTokens.spacingSM : ResponsiveTokens.spacingMD),
          decoration: BoxDecoration(
            color: const Color(0xFFE8D5F2), // Light purple background
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: theme.dividerColor.withOpacity(.2)),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                constraints: const BoxConstraints(
                  minWidth: 40,
                  minHeight: 40,
                  maxWidth: 48,
                  maxHeight: 48,
                ),
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Color(0xFF6B2C91), // Dark purple icon background
                ),
                child: const Icon(
                  Icons.spa,
                  color: Colors.white,
                  size: 24,
                ),
              ),
              SizedBox(width: ResponsiveTokens.spacingSM),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Meditation Timer',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'भक्ति में ध्यान, ध्यान में शांति।',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: Colors.black87,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              SizedBox(width: ResponsiveTokens.spacingXS),
              Flexible(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.graphic_eq, size: 18, color: Colors.black87),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        soundLabel,
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: Colors.black87,
                          fontWeight: FontWeight.w500,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.end,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
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
    return LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < 360;
        return Container(
          padding: EdgeInsets.all(isNarrow ? ResponsiveTokens.spacingSM : 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: theme.dividerColor.withOpacity(.4)),
          ),
          child: DropdownButtonFormField<int>(
            value: selected,
            icon: const Icon(Icons.expand_more),
            isExpanded: isNarrow,
            decoration: InputDecoration(
              labelText: 'Select time',
              labelStyle: TextStyle(color: Colors.black87),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: theme.dividerColor.withOpacity(.6)),
              ),
              contentPadding: EdgeInsets.symmetric(
                horizontal: isNarrow ? ResponsiveTokens.spacingSM : 12,
                vertical: 14,
              ),
            ),
            items: presets
                .map((m) => DropdownMenuItem(
                      value: m,
                      child: Text('$m minutes'),
                    ))
                .toList(),
            onChanged: !enabled
                ? null
                : (value) {
                    if (value != null) onSelect(value);
                  },
          ),
        );
      },
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
    return LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < 360;
        return Container(
          padding: EdgeInsets.all(isNarrow ? ResponsiveTokens.spacingSM : 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: theme.dividerColor.withOpacity(.4)),
          ),
          child: DropdownButtonFormField<String>(
            value: selected,
            icon: const Icon(Icons.expand_more),
            isExpanded: isNarrow,
            decoration: InputDecoration(
              labelText: 'Select sound',
              labelStyle: TextStyle(color: Colors.black87),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: theme.dividerColor.withOpacity(.6)),
              ),
              contentPadding: EdgeInsets.symmetric(
                horizontal: isNarrow ? ResponsiveTokens.spacingSM : 12,
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
      },
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
      if (kDebugMode) {
        debugPrint(
          '[ShareFlow] boundary ready -> hasSize=${boundary.size}, pixelRatio=3.0',
        );
      }

      Future<Uint8List> capture() async {
        final image = await boundary.toImage(pixelRatio: 3.0);
        final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
        if (byteData == null) {
          throw Exception('Unable to encode boundary to PNG byteData');
        }
        return byteData.buffer.asUint8List();
      }

      Uint8List pngBytes = await capture();
      if (pngBytes.isEmpty) {
        if (kDebugMode) {
          debugPrint('[ShareFlow] capture produced 0 bytes, retrying once');
        }
        await Future.delayed(const Duration(milliseconds: 16));
        pngBytes = await capture();
      }

      final dir = await getTemporaryDirectory();
      final file = File(
        '${dir.path}/timer_share_${DateTime.now().millisecondsSinceEpoch}.png',
      );
      await file.writeAsBytes(pngBytes);
      if (kDebugMode) {
        debugPrint('[ShareFlow] capture success -> bytes=${pngBytes.length}');
      }
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
      if (kDebugMode) {
        debugPrint('[ShareFlow] share intent launched');
      }
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
