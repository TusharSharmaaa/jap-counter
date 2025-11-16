import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/prefs_manager.dart';

class TimerService extends ChangeNotifier {
  // Pref keys
  static const _kTargetSecs = 'timer_target_secs';
  static const _kAccumulatedSecs = 'timer_accumulated_secs';
  static const _kStartedAtMillis = 'timer_started_at_millis';
  static const _kRunning = 'timer_running';
  static const _kSoundKey = 'timer_sound';
  static const _kRunId = 'timer_run_id';
  static const _kCompletedFlag = 'timer_completed_flag';
  static const _kRecordedSecs = 'timer_recorded_secs';
  static const _kLastActiveMillis = 'timer_last_active_millis';
  static const _kAppWasClosed = 'timer_app_was_closed';
  static const _kPausedAtMillis = 'timer_paused_at_millis';

  // Defaults
  static const Duration defaultTarget = Duration(minutes: 2);

  Duration _target = defaultTarget;
  Duration _accumulated = Duration.zero;
  DateTime? _startedAt;
  String _sound = 'mute';
  String _runId = '';
  bool _running = false;
  bool _completedThisRun = false;
  Timer? _ticker;
  int _recordedSeconds = 0;
  int? _lastDisplayedSeconds;
  final ValueNotifier<String> displayNotifier = ValueNotifier<String>('');

  Duration get target => _target;
  bool get running => _running;
  String get sound => _sound;
  String get runId => _runId;
  bool get completed => _completedThisRun;

  Duration get elapsed {
    if (!_running || _startedAt == null) {
      return _accumulated;
    }
    // Always use DateTime.now() for accurate real-time calculations
    // The cached value is only used within the ticker for performance
    final now = DateTime.now();
    return _accumulated + now.difference(_startedAt!);
  }

  Duration get remaining {
    final remainder = _target - elapsed;
    return remainder.isNegative ? Duration.zero : remainder;
  }

  bool get hasProgress => elapsed > Duration.zero;

  double get progress {
    final totalMillis = _target.inMilliseconds;
    if (totalMillis <= 0) return 1;
    final done = elapsed.inMilliseconds.clamp(0, totalMillis);
    return done / totalMillis;
  }

  bool get isPristine =>
      !_running && _accumulated == Duration.zero && _startedAt == null;

  bool get _hasInFlightTicker => _ticker != null;

  Future<void> load() async {
    final prefs = await PrefsManager.instance;
    final targetSecs = prefs.getInt(_kTargetSecs);
    final accumSecs = prefs.getInt(_kAccumulatedSecs);
    final startedMillis = prefs.getInt(_kStartedAtMillis);
    final running = prefs.getBool(_kRunning);
    final sound = prefs.getString(_kSoundKey);
    _runId = prefs.getString(_kRunId) ?? '';
    _completedThisRun = prefs.getBool(_kCompletedFlag) ?? false;
    _recordedSeconds = prefs.getInt(_kRecordedSecs) ?? 0;

    _target = Duration(seconds: targetSecs ?? defaultTarget.inSeconds);
    _accumulated = Duration(seconds: accumSecs ?? 0);
    _sound = (sound ?? 'mute').toLowerCase();

    var needsPersist = false;
    final lastActiveMillis = prefs.getInt(_kLastActiveMillis);
    final now = DateTime.now();
    if (lastActiveMillis != null) {
      final lastActive = DateTime.fromMillisecondsSinceEpoch(
        lastActiveMillis,
        isUtc: false,
      );
      if (!_isSameDay(lastActive, now)) {
        _resetForNewDay();
        needsPersist = true;
      }
    }

    // Restore timer state
    if (running == true && startedMillis != null) {
      _startedAt = DateTime.fromMillisecondsSinceEpoch(
        startedMillis,
        isUtc: false,
      );
      
      // Check if timer was started on a different day
      final startDate = _startedAt!;
      final startDay = DateTime(startDate.year, startDate.month, startDate.day);
      final nowDay = DateTime(now.year, now.month, now.day);
      
      if (startDay.isBefore(nowDay)) {
        // Timer was started on a previous day - reset it
        _resetForNewDay();
        needsPersist = true;
      } else {
        // Calculate elapsed time since start
        final elapsedSinceStart = now.difference(_startedAt!);
        final totalElapsed = _accumulated + elapsedSinceStart;
        final remaining = _target - totalElapsed;
        
        // Check if timer has completed while app was closed
        if (remaining <= Duration.zero) {
          // Timer completed while app was closed.
          // Mark as completed, but DO NOT touch _recordedSeconds here.
          // Any remaining minutes will be credited later via
          // captureUncreditedMinutes(forceFull: true) invoked from the UI.
          _running = false;
          _startedAt = null;
          _accumulated = _target;
          _completedThisRun = true;
          _stopTicker();
          needsPersist = true;
        } else {
          // Timer is still running - restore state and start ticker
          _running = true;
          _startTicker();
        }
      }
    } else {
      // Timer is not running - ensure clean state
      _running = false;
      _startedAt = null;
      _stopTicker();
      // Only reset accumulated if we have a valid pause state (accumulated > 0)
      // Otherwise, keep it at zero for fresh starts
      if (accumSecs == null || accumSecs == 0) {
        // No previous state, ensure everything is reset
        if (_accumulated > Duration.zero || _runId.isNotEmpty) {
          _accumulated = Duration.zero;
          _runId = '';
          _recordedSeconds = 0;
          _completedThisRun = false;
          needsPersist = true;
        }
      }
    }

    if (needsPersist) {
      await _persist();
    }

    // Update display notifier to reflect current state
    final currentSeconds = remaining.inSeconds;
    _lastDisplayedSeconds = currentSeconds;
    final minutes = currentSeconds ~/ 60;
    final secs = currentSeconds % 60;
    displayNotifier.value = '${minutes.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';

    if (kDebugMode) {
      debugPrint(
        '[TimerService] load -> running=$_running startedAt=$_startedAt accumulated=${_accumulated.inSeconds}s target=${_target.inSeconds}s remaining=${remaining.inSeconds}s',
      );
    }

    notifyListeners();
  }

  Duration _remainingFor(DateTime anchor) {
    final elapsedSinceStart = (_startedAt != null && _running)
        ? anchor.difference(_startedAt!)
        : Duration.zero;
    final totalElapsed = _accumulated + elapsedSinceStart;
    final remainder = _target - totalElapsed;
    return remainder.isNegative ? Duration.zero : remainder;
  }

  Future<void> _persist() async {
    final prefs = await PrefsManager.instance;
    await prefs.setInt(_kTargetSecs, _target.inSeconds);
    await prefs.setInt(_kAccumulatedSecs, _accumulated.inSeconds);
    if (_startedAt != null) {
      await prefs.setInt(_kStartedAtMillis, _startedAt!.millisecondsSinceEpoch);
    } else {
      await prefs.remove(_kStartedAtMillis);
    }
    await prefs.setBool(_kRunning, _running);
    await prefs.setString(_kSoundKey, _sound);
    await prefs.setString(_kRunId, _runId);
    await prefs.setBool(_kCompletedFlag, _completedThisRun);
    await prefs.setInt(_kRecordedSecs, _recordedSeconds);
    await prefs.setInt(
      _kLastActiveMillis,
      DateTime.now().millisecondsSinceEpoch,
    );
  }

  void _startTicker() {
    _stopTicker();
    if (!_running) {
      // Don't start ticker if not running
      return;
    }
    _ticker = Timer.periodic(const Duration(seconds: 1), (timer) {
      // Check running state first - if false, stop ticker and return
      if (!_running) {
        timer.cancel();
        _ticker = null;
        return;
      }
      
      // Calculate remaining time using current time
      final now = DateTime.now();
      final elapsedSinceStart = _startedAt != null 
          ? now.difference(_startedAt!) 
          : Duration.zero;
      final totalElapsed = _accumulated + elapsedSinceStart;
      final remainder = _target - totalElapsed;
      final remaining = remainder.isNegative ? Duration.zero : remainder;
      
      // Check if timer has completed
      if (remaining == Duration.zero) {
        timer.cancel();
        _ticker = null;
        unawaited(_complete());
        return;
      }
      
      // Only update display if seconds changed to reduce rebuilds
      final currentSeconds = remaining.inSeconds;
      if (_lastDisplayedSeconds != currentSeconds) {
        _lastDisplayedSeconds = currentSeconds;
        // Update display notifier for selective listening
        final minutes = currentSeconds ~/ 60;
        final secs = currentSeconds % 60;
        displayNotifier.value = '${minutes.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
        // Notify listeners for state changes
        notifyListeners();
      }
    });
    if (kDebugMode) {
      debugPrint('[TimerService] _startTicker -> tickerCreated, running=$_running');
    }
    // Initialize display immediately
    final initialSeconds = remaining.inSeconds;
    _lastDisplayedSeconds = initialSeconds;
    final minutes = initialSeconds ~/ 60;
    final secs = initialSeconds % 60;
    displayNotifier.value = '${minutes.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
    notifyListeners();
  }

  void _stopTicker() {
    _ticker?.cancel();
    _ticker = null;
  }

  Future<void> start({String? runId}) async {
    if (_running) return;
    
    // Clear pause timestamp when starting
    final prefs = await PrefsManager.instance;
    await prefs.remove(_kPausedAtMillis);
    
    // Determine if this is a new run or resuming
    final wasCompleted = remaining == Duration.zero && !_running;
    final isNewRun =
        wasCompleted || _runId.isEmpty || _accumulated == Duration.zero;
    
    if (isNewRun) {
      // Starting fresh - reset everything
      _accumulated = Duration.zero;
      _recordedSeconds = 0;
      _runId = runId ?? DateTime.now().microsecondsSinceEpoch.toString();
    } else {
      // Resuming existing run - keep accumulated time and runId
      _runId = runId ?? _runId;
    }
    
    _completedThisRun = false;
    _startedAt = DateTime.now();
    _running = true;
    _startTicker();
    await _persist();
    notifyListeners();
    if (kDebugMode) {
      debugPrint(
        '[TimerService] start -> runId=$_runId accumulated=${_accumulated.inSeconds}s isNewRun=$isNewRun',
      );
    }
  }

  Future<void> resume({String? runId}) async {
    if (_running || remaining == Duration.zero) return;
    
    // Clear pause timestamp when resuming
    final prefs = await PrefsManager.instance;
    await prefs.remove(_kPausedAtMillis);
    
    // Use existing runId or create new one
    final resumeId = runId ?? 
        (_runId.isEmpty 
            ? DateTime.now().microsecondsSinceEpoch.toString() 
            : _runId);
    _runId = resumeId;
    _completedThisRun = false;
    _startedAt = DateTime.now();
    _running = true;
    _startTicker();
    await _persist();
    notifyListeners();
    if (kDebugMode) {
      debugPrint(
        '[TimerService] resume -> runId=$_runId accumulated=${_accumulated.inSeconds}s remaining=${remaining.inSeconds}s',
      );
    }
  }

  Future<void> pause() async {
    if (!_running) return;
    
    // Update accumulated time with current elapsed time
    _accumulated = elapsed;
    _startedAt = null;
    _running = false;
    _stopTicker();
    
    // Update display to show paused state
    final pausedSeconds = remaining.inSeconds;
    _lastDisplayedSeconds = pausedSeconds;
    final minutes = pausedSeconds ~/ 60;
    final secs = pausedSeconds % 60;
    displayNotifier.value = '${minutes.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
    
    // Save pause timestamp to detect if app was closed
    final prefs = await PrefsManager.instance;
    await prefs.setInt(
      _kPausedAtMillis,
      DateTime.now().millisecondsSinceEpoch,
    );
    await _persist();
    notifyListeners();
    if (kDebugMode) {
      debugPrint(
        '[TimerService] pause -> accumulated=${_accumulated.inSeconds}s recorded=$_recordedSeconds remaining=${remaining.inSeconds}s',
      );
    }
  }

  Future<void> reset() async {
    _stopTicker();
    _running = false;
    _startedAt = null;
    _accumulated = Duration.zero;
    _completedThisRun = false;
    _runId = '';
    _recordedSeconds = 0;
    
    // Update display to show reset state (target time)
    final resetSeconds = _target.inSeconds;
    _lastDisplayedSeconds = resetSeconds;
    final minutes = resetSeconds ~/ 60;
    final secs = resetSeconds % 60;
    displayNotifier.value = '${minutes.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
    
    // Clear pause timestamp when resetting
    final prefs = await PrefsManager.instance;
    await prefs.remove(_kPausedAtMillis);
    await _persist();
    notifyListeners();
  }

  Future<void> selectDuration(Duration duration) async {
    if (_running) return;
    _target = duration;
    _accumulated = Duration.zero;
    _startedAt = null;
    _completedThisRun = false;
    _runId = '';
    _recordedSeconds = 0;
    
    // Update display to show new target time
    final targetSeconds = _target.inSeconds;
    _lastDisplayedSeconds = targetSeconds;
    final minutes = targetSeconds ~/ 60;
    final secs = targetSeconds % 60;
    displayNotifier.value = '${minutes.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
    
    await _persist();
    notifyListeners();
  }

  Future<void> selectSound(String soundId) async {
    final normalized = soundId.toLowerCase();
    if (_sound == normalized) return;
    _sound = normalized;
    await _persist();
    notifyListeners();
  }

  Future<void> _complete() async {
    if (_completedThisRun) return;
    _completedThisRun = true;
    _accumulated = _target;
    _running = false;
    _startedAt = null;
  // IMPORTANT: Do NOT mutate _recordedSeconds here.
  // It tracks how many seconds have already been credited to MeditationStore.
  // The UI layer will call captureUncreditedMinutes(forceFull: true) on completion,
  // which uses _recordedSeconds to compute the remaining minutes to credit.
    _stopTicker();
    
    // Update display to show completed state (00:00)
    _lastDisplayedSeconds = 0;
    displayNotifier.value = '00:00';
    
    await _persist();
    notifyListeners();
    if (kDebugMode) {
      debugPrint(
        '[TimerService] complete -> runId=$_runId recorded=$_recordedSeconds',
      );
    }
  }

  bool consumeCompletion(String runId) {
    final shouldShow =
        _completedThisRun && _runId.isNotEmpty && _runId == runId;
    if (shouldShow) {
      _completedThisRun = false;
      _runId = '';
      unawaited(_persist());
    }
    return shouldShow;
  }

  void refresh() {
    if (_running && !_hasInFlightTicker) {
      // Timer is running but ticker is not - restart it
      _startTicker();
    } else {
      // Update display notifier even when not running
      final currentSeconds = remaining.inSeconds;
      if (_lastDisplayedSeconds != currentSeconds) {
        _lastDisplayedSeconds = currentSeconds;
        final minutes = currentSeconds ~/ 60;
        final secs = currentSeconds % 60;
        displayNotifier.value = '${minutes.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
      }
      notifyListeners();
    }
  }

  Future<int> captureUncreditedMinutes({bool forceFull = false}) async {
    // Calculate total elapsed seconds
    final totalSecs = forceFull ? _target.inSeconds : elapsed.inSeconds;
    final cappedSecs = totalSecs.clamp(0, _target.inSeconds);
    
    // Calculate delta from what we've already recorded
    final deltaSecs = cappedSecs - _recordedSeconds;
    if (deltaSecs <= 0) {
      // No new time to credit
      return 0;
    }

    int minutes;
    if (forceFull) {
      // Credit all remaining time (used when timer completes)
      minutes = (deltaSecs / 60).ceil();
      _recordedSeconds = cappedSecs;
    } else {
      // Only credit full minutes (used during pause)
      if (deltaSecs < 60) {
        // Less than a minute - don't credit yet
        return 0;
      }
      // Credit full minutes only
      minutes = deltaSecs ~/ 60;
      _recordedSeconds += minutes * 60;
      // Ensure we don't exceed the total
      if (_recordedSeconds > cappedSecs) {
        _recordedSeconds = cappedSecs;
      }
    }
    
    // Persist the updated recorded seconds
    await _persist();
    
    if (kDebugMode) {
      debugPrint(
        '[TimerService] captureUncreditedMinutes -> minutes=$minutes recorded=$_recordedSeconds total=$cappedSecs',
      );
    }
    
    return minutes;
  }

  void _resetForNewDay() {
    _running = false;
    _startedAt = null;
    _accumulated = Duration.zero;
    _completedThisRun = false;
    _runId = '';
    _recordedSeconds = 0;
    _stopTicker();
  }

  Future<void> markAppClosed() async {
    final prefs = await PrefsManager.instance;
    await prefs.setBool(_kAppWasClosed, true);
    if (kDebugMode) {
      debugPrint('[TimerService] App closed flag set');
    }
  }

  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  @override
  void dispose() {
    _stopTicker();
    displayNotifier.dispose();
    super.dispose();
  }
}
