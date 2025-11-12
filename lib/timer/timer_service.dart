import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

  Duration get target => _target;
  bool get running => _running;
  String get sound => _sound;
  String get runId => _runId;
  bool get completed => _completedThisRun;

  Duration get elapsed {
    if (!_running || _startedAt == null) {
      return _accumulated;
    }
    return _accumulated + DateTime.now().difference(_startedAt!);
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
    final prefs = await SharedPreferences.getInstance();
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

    // SIMPLE RULE: When app loads, if timer is NOT running, reset it to starting time
    // This ensures that when app is closed and reopened, timer always starts fresh
    if (running != true) {
      // Timer is paused or idle - reset it to starting time
      if (_accumulated > Duration.zero || startedMillis != null) {
        if (kDebugMode) {
          debugPrint(
            '[TimerService] App loaded with paused/idle timer -> resetting to starting time',
          );
        }
        _accumulated = Duration.zero;
        _startedAt = null;
        _runId = '';
        _recordedSeconds = 0;
        _completedThisRun = false;
        needsPersist = true;
      }
    }

    if (running == true && startedMillis != null) {
      _startedAt = DateTime.fromMillisecondsSinceEpoch(
        startedMillis,
        isUtc: false,
      );
      
      // Check if timer was started on a different day
      // Use timezone-aware comparison to handle day boundaries correctly
      final startDate = _startedAt!;
      final startDay = DateTime(startDate.year, startDate.month, startDate.day);
      final nowDay = DateTime(now.year, now.month, now.day);
      
      if (startDay.isBefore(nowDay)) {
        // Timer was started on a previous day - reset it
        _resetForNewDay();
        needsPersist = true;
      } else if (_startedAt != null) {
        // Calculate elapsed time since start
        final elapsedSinceStart = now.difference(_startedAt!);
        final totalElapsed = _accumulated + elapsedSinceStart;
        final remaining = _target - totalElapsed;
        
        // Check if timer has completed while app was closed
        if (remaining <= Duration.zero) {
          _running = false;
          _startedAt = null;
          _accumulated = _target;
          _completedThisRun = true;
          _recordedSeconds = _target.inSeconds;
          needsPersist = true;
        } else {
          // Timer is still running - restore state
          _running = true;
          _startTicker();
        }
      } else {
        // Invalid state - reset
        _running = false;
        _startedAt = null;
        _stopTicker();
        needsPersist = true;
      }
    } else {
      _running = false;
      _startedAt = null;
      _stopTicker();
    }

    if (needsPersist) {
      await _persist();
    }

    if (kDebugMode) {
      debugPrint(
        '[TimerService] load -> running=$_running startedAt=$_startedAt accumulated=$_accumulated target=$_target',
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
    final prefs = await SharedPreferences.getInstance();
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
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!_running) return;
      if (remaining == Duration.zero) {
        unawaited(_complete());
        return;
      }
      notifyListeners();
    });
    if (kDebugMode) {
      debugPrint('[TimerService] _startTicker -> tickerCreated');
    }
    notifyListeners();
  }

  void _stopTicker() {
    _ticker?.cancel();
    _ticker = null;
  }

  Future<void> start({String? runId}) async {
    if (_running) return;
    // Clear pause timestamp when starting
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kPausedAtMillis);
    final newRunId =
        runId ??
        (_runId.isEmpty
            ? DateTime.now().microsecondsSinceEpoch.toString()
            : _runId);
    final wasCompleted = remaining == Duration.zero && !_running;
    final isNewRun =
        wasCompleted || _runId.isEmpty || _accumulated == Duration.zero;
    if (isNewRun) {
      _accumulated = Duration.zero;
      _recordedSeconds = 0;
    }
    _runId = newRunId;
    _completedThisRun = false;
    _startedAt = DateTime.now();
    _running = true;
    _startTicker();
    await _persist();
    if (kDebugMode) {
      debugPrint(
        '[TimerService] start -> runId=$_runId accumulated=$_accumulated startedAt=$_startedAt',
      );
    }
  }

  Future<void> resume({String? runId}) async {
    if (_running || remaining == Duration.zero) return;
    // Clear pause timestamp when resuming
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kPausedAtMillis);
    final resumeId =
        runId ??
        (_runId.isEmpty
            ? DateTime.now().microsecondsSinceEpoch.toString()
            : _runId);
    _runId = resumeId;
    _completedThisRun = false;
    _startedAt = DateTime.now();
    _running = true;
    _startTicker();
    await _persist();
    if (kDebugMode) {
      debugPrint(
        '[TimerService] resume -> runId=$_runId accumulated=$_accumulated startedAt=$_startedAt',
      );
    }
  }

  Future<void> pause() async {
    if (!_running) return;
    _accumulated = elapsed;
    _startedAt = null;
    _running = false;
    _stopTicker();
    // Save pause timestamp to detect if app was closed
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(
      _kPausedAtMillis,
      DateTime.now().millisecondsSinceEpoch,
    );
    await _persist();
    notifyListeners();
    if (kDebugMode) {
      debugPrint(
        '[TimerService] pause -> accumulated=$_accumulated recorded=$_recordedSeconds',
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
    // Clear pause timestamp when resetting
    final prefs = await SharedPreferences.getInstance();
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
    _recordedSeconds = _target.inSeconds;
    _stopTicker();
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
      _startTicker();
    } else {
      notifyListeners();
    }
  }

  Future<int> captureUncreditedMinutes({bool forceFull = false}) async {
    final totalSecs = forceFull ? _target.inSeconds : elapsed.inSeconds;
    final cappedSecs = totalSecs.clamp(0, _target.inSeconds);
    final deltaSecs = cappedSecs - _recordedSeconds;
    if (deltaSecs <= 0) {
      return 0;
    }

    int minutes;
    if (forceFull) {
      minutes = (deltaSecs / 60).ceil();
      _recordedSeconds = cappedSecs;
    } else {
      if (deltaSecs < 60) {
        return 0;
      }
      minutes = deltaSecs ~/ 60;
      _recordedSeconds += minutes * 60;
      if (_recordedSeconds > cappedSecs) {
        _recordedSeconds = cappedSecs;
      }
    }
    await _persist();
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
    final prefs = await SharedPreferences.getInstance();
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
    super.dispose();
  }
}
