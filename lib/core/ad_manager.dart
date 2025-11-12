import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:jap_counter/debug/ad_health.dart';

const _logTag = '[AD]';
const _fallbackPolicyVersion = 'fallback-2025-11-09';

Map<String, dynamic> _buildFallbackPolicy() {
  return {
    'version': _fallbackPolicyVersion,
    'global': {
      'enable_ads': true,
      'interstitial': {
        'daily_cap': 1,
        'min_cooldown_seconds': 600,
        'skip_if_last_interstitial_within_seconds': 600,
      },
      'rewarded': {
        'daily_cap': 3,
        'min_cooldown_seconds': 0,
        'skip_if_not_ready_after_ms': 2000,
      },
      'consent': {'use_ump': false, 'serve_npa_if_declined': true},
    },
    'placements': {
      'stats': {
        'share_rewarded': {
          'type': 'rewarded',
          'enabled': true,
          'caps': {'daily_cap': 3, 'min_cooldown_seconds': 0},
        },
      },
      'gita': {
        'share_rewarded': {
          'type': 'rewarded',
          'enabled': true,
          'caps': {'daily_cap': 3, 'min_cooldown_seconds': 0},
        },
        'long_session_interstitial': {
          'type': 'interstitial',
          'enabled': true,
          'conditions': {
            'min_shlokas_read': 2,
            'min_time_ms': 60000,
            'skip_if_rewarded_shown_within_seconds': 300,
          },
          'caps': {'daily_cap': 1, 'min_cooldown_seconds': 600},
        },
      },
      'timer': {
        'post_session_interstitial': {
          'type': 'interstitial',
          'enabled': true,
          'conditions': {
            'skip_if_session_minutes_lt': 1,
            'skip_if_any_interstitial_within_seconds': 600,
          },
          'caps': {'daily_cap': 2, 'min_cooldown_seconds': 600},
        },
        'share_rewarded': {
          'type': 'rewarded',
          'enabled': true,
          'caps': {'daily_cap': 3, 'min_cooldown_seconds': 0},
        },
      },
    },
    'preload': {
      'rewarded': [
        'stats.share_rewarded',
        'gita.share_rewarded',
        'timer.share_rewarded',
      ],
      'interstitial': [
        'gita.long_session_interstitial',
        'timer.post_session_interstitial',
      ],
    },
  };
}

class AdManager {
  AdManager._() {
    AdHealth.registerSupplier(_buildAdHealthSnapshot);
  }

  static final AdManager instance = AdManager._();

  static const String _defaultPolicyAssetPath = 'assets/config/ad_policy.json';
  static const String defaultPolicyAssetPath = _defaultPolicyAssetPath;
  static const int _attemptHistoryLimit = 12;
  static const Duration _defaultRewardedTimeout = Duration(milliseconds: 1500);

  /// When true (default in debug), Google test IDs are used regardless of policy.
  bool useTestIds = kDebugMode;

  final Map<String, dynamic> _placements = {};
  Map<String, dynamic> _global = {};
  Map<String, dynamic> _policy = {};

  final Map<String, String> _productionRewardedUnitIds = {};
  final Map<String, String> _productionInterstitialUnitIds = {};
  final Map<String, String> _activeRewardedUnitIds = {};
  final Map<String, String> _activeInterstitialUnitIds = {};

  final Map<String, RewardedAd> _rewardedCache = {};
  final Map<String, InterstitialAd> _interstitialCache = {};
  final Map<String, Timer> _rewardedRetryTimers = {};
  final Map<String, Timer> _interstitialRetryTimers = {};
  final Map<String, int> _rewardedRetryCounts = {};
  final Map<String, int> _interstitialRetryCounts = {};

  final ListQueue<_AdAttemptLog> _attemptHistory = ListQueue();

  SharedPreferences? _prefs;
  Future<void>? _bootstrapFuture;

  bool _adMobInitialized = false;
  bool _policyLoaded = false;
  String? _policySource;
  String? _policyLoadError;
  String _consentStatusLabel = 'unknown';
  bool _serveNpa = false;

  // In-memory session tracking (reset per process).
  DateTime? _gitaSessionStart;
  int _gitaShlokasRead = 0;
  DateTime? _lastRewardedShownTime;
  DateTime? _lastInterstitialShownTime;

  // Debug/testing overrides.
  bool _testMode = false;
  bool _testRewardedOutcome = true;
  bool _testInterstitialOutcome = true;

  void adoptBootstrapFuture(Future<void> future) {
    if (_bootstrapFuture != null) return;
    _bootstrapFuture = future;
    unawaited(future.catchError((error, stackTrace) {
      _logError(
        'bootstrap future error: $error',
        stackTrace: stackTrace is StackTrace ? stackTrace : null,
      );
    }));
    unawaited(future.whenComplete(() {
      _logInfo('bootstrap future completed (external)');
    }));
  }

  Future<void> bootstrap({
    String policyAssetPath = _defaultPolicyAssetPath,
    List<String>? testDeviceIds,
  }) {
    if (_bootstrapFuture != null) {
      return _bootstrapFuture!;
    }
    final completer = Completer<void>();
    _bootstrapFuture = completer.future;
    unawaited(_runBootstrap(
      policyAssetPath: policyAssetPath,
      testDeviceIds: testDeviceIds,
    ).catchError((error, stackTrace) {
      _logError(
        'bootstrap failed: $error',
        stackTrace: stackTrace is StackTrace ? stackTrace : null,
      );
    }).whenComplete(() {
      if (!completer.isCompleted) {
        completer.complete();
      }
    }));
    return _bootstrapFuture!;
  }

  Future<void> _runBootstrap({
    required String policyAssetPath,
    List<String>? testDeviceIds,
  }) async {
    _logInfo('bootstrap start (policy: $policyAssetPath)');
    Future<bool> runBoolStep(
      String label,
      Future<bool> Function() action,
    ) async {
      try {
        final ok = await action();
        _logInfo('bootstrap step $label → ${ok ? 'OK' : 'FAIL'}');
        return ok;
      } catch (error, stackTrace) {
        _logError(
          'bootstrap step $label exception: $error',
          stackTrace: stackTrace,
        );
        return false;
      }
    }

    await runBoolStep('shared_prefs', () async {
      await _ensurePrefs();
      return true;
    });

    final policyOk = await runBoolStep('policy_load', () async {
      await loadPolicyFromAsset(policyAssetPath);
      return policyLoaded;
    });
    final adMobOk = await runBoolStep('admob_init', () async {
      return await initAdMob(testDeviceIds: testDeviceIds);
    });
    final consentOk = await runBoolStep('consent_init', () async {
      return await initConsent();
    });
    final preloadOk = await runBoolStep('preload_ads', () async {
      return await preloadAll(force: true, ensureReady: false);
    });

    AdHealth.printSnapshot(reason: 'bootstrap complete');
    _logInfo(
      'bootstrap complete (policy=${policyOk ? 'OK' : 'FAIL'}, '
      'admob=${adMobOk ? 'OK' : 'FAIL'}, consent=${consentOk ? 'OK' : 'FAIL'}, '
      'preload=${preloadOk ? 'OK' : 'FAIL'})',
    );
  }

  Future<void> loadPolicyFromAsset(String path) async {
    _policySource = path;
    _policyLoadError = null;
    try {
      final raw = await rootBundle.loadString(path);
      _policy = json.decode(raw) as Map<String, dynamic>;
      _policyLoaded = true;
      _logInfo('policy loaded from $path');
    } on FlutterError catch (error) {
      _policy = _buildFallbackPolicy();
      _policyLoaded = false;
      _policyLoadError = error.message;
      _logWarn('policy asset missing at $path, using fallback defaults');
    } catch (error) {
      _policy = _buildFallbackPolicy();
      _policyLoaded = false;
      _policyLoadError = '$error';
      _logWarn('policy load failed ($error). Using fallback defaults.');
    }

    _global = (_policy['global'] as Map?)?.cast<String, dynamic>() ?? {};
    final placements =
        (_policy['placements'] as Map?)?.cast<String, dynamic>() ?? {};
    _placements
      ..clear()
      ..addAll(_flattenPlacements(placements));

    final adUnits =
        (_policy['ad_units'] as Map?)?.cast<String, dynamic>() ?? {};
    final productionRewarded =
        (adUnits['rewarded'] as Map?)?.cast<String, String>() ?? {};
    final productionInterstitial =
        (adUnits['interstitial'] as Map?)?.cast<String, String>() ?? {};

    _productionRewardedUnitIds
      ..clear()
      ..addAll(productionRewarded);
    _productionInterstitialUnitIds
      ..clear()
      ..addAll(productionInterstitial);

    _updateActiveAdUnitIds();
  }

  Future<bool> initAdMob({List<String>? testDeviceIds}) async {
    try {
      final status = await MobileAds.instance.initialize();
      final adapters = status.adapterStatuses;
      final readyAdapters = adapters.entries
          .where(
            (entry) => entry.value.state == AdapterInitializationState.ready,
          )
          .map((entry) => entry.key)
          .toList(growable: false);
      _adMobInitialized = readyAdapters.isNotEmpty;
      _logInfo(
        'AdMob initialize → ${_adMobInitialized ? 'ready' : 'pending'} (ready=${readyAdapters.join(', ')}, total=${adapters.length})',
      );
    } catch (error, stackTrace) {
      _adMobInitialized = false;
      _logError(
        'AdMob initialize failed: $error',
        stackTrace: stackTrace,
      );
      return false;
    }

    try {
      final requestConfig = RequestConfiguration(
        testDeviceIds: testDeviceIds ?? const <String>[],
      );
      await MobileAds.instance.updateRequestConfiguration(requestConfig);
      _logInfo(
        'RequestConfiguration applied (testDeviceIds=${requestConfig.testDeviceIds})',
      );
    } catch (error, stackTrace) {
      _logWarn('RequestConfiguration failed: $error');
      _logError(
        'RequestConfiguration failed with stack trace',
        stackTrace: stackTrace,
      );
    }

    return _adMobInitialized;
  }

  Future<bool> initConsent() async {
    final consentConfig =
        (_global['consent'] as Map?)?.cast<String, dynamic>() ?? {};
    final useUmp = consentConfig['use_ump'] == true;

    if (!useUmp) {
      _serveNpa = consentConfig['serve_npa_if_declined'] == true;
      _consentStatusLabel = _serveNpa ? 'npa' : 'consented';
      _logInfo('UMP disabled in policy. Consent state → $_consentStatusLabel');
      return true;
    }

    try {
      _serveNpa = true; // default to NPA until consent known.
      final consentInfo = ConsentInformation.instance;
      final params = ConsentRequestParameters();
      final completer = Completer<void>();

      consentInfo.requestConsentInfoUpdate(
        params,
        () => completer.complete(),
        (error) => completer.completeError(error),
      );
      await completer.future;

      if (await consentInfo.isConsentFormAvailable()) {
        await ConsentForm.loadAndShowConsentFormIfRequired((formError) {
          if (formError != null) {
            _logWarn('Consent form error: ${formError.message}');
          }
        });
      }

      final status = await consentInfo.getConsentStatus();
      switch (status) {
        case ConsentStatus.obtained:
        case ConsentStatus.notRequired:
          _serveNpa = false;
          _consentStatusLabel = 'consented';
          break;
        case ConsentStatus.required:
          _serveNpa = true;
          _consentStatusLabel = 'required';
          break;
        default:
          _serveNpa = true;
          _consentStatusLabel = 'npa';
      }

      if (_serveNpa && consentConfig['serve_npa_if_declined'] != true) {
        _serveNpa = false;
        _consentStatusLabel = 'consented';
      }
      _logInfo('Consent resolved → $_consentStatusLabel');
      return true;
    } catch (error, stackTrace) {
      _serveNpa = true;
      _consentStatusLabel = 'npa';
      _logWarn('Consent flow failed. Falling back to NPA. ($error)');
      _logError(
        'Consent flow failed with stack trace',
        stackTrace: stackTrace,
      );
      return false;
    }
  }

  Future<bool> preloadAll({
    bool force = false,
    bool ensureReady = true,
  }) async {
    try {
      if (ensureReady) {
        await _waitUntilReady();
      }
      final rewardedIds = _placements.entries
          .where((entry) => entry.value['type'] == 'rewarded')
          .map((entry) => entry.key);
      final interstitialIds = _placements.entries
          .where((entry) => entry.value['type'] == 'interstitial')
          .map((entry) => entry.key);

      for (final id in rewardedIds) {
        await _preloadRewarded(id, force: force);
      }
      for (final id in interstitialIds) {
        await _preloadInterstitial(id, force: force);
      }
      return true;
    } catch (error, stackTrace) {
      _logError('preloadAll failed: $error', stackTrace: stackTrace);
      return false;
    }
  }

  Future<bool> preloadPlacement(
    String placementId, {
    bool force = false,
    bool ensureReady = true,
  }) async {
    try {
      if (ensureReady) {
        await _waitUntilReady();
      }
      final placement = _placements[placementId] as Map<String, dynamic>?;
      if (placement == null) return false;
      final type = placement['type'];
      if (type == 'rewarded') {
        await _preloadRewarded(placementId, force: force);
      } else if (type == 'interstitial') {
        await _preloadInterstitial(placementId, force: force);
      }
      return true;
    } catch (error, stackTrace) {
      _logError(
        'preloadPlacement failed for $placementId: $error',
        stackTrace: stackTrace,
      );
      return false;
    }
  }

  Future<void> recordEvent(
    String placementId,
    String event, {
    Map<String, dynamic>? data,
  }) async {
    await _ensurePrefs();

    switch (placementId) {
      case 'gita.session':
        if (event == 'start') {
          _gitaSessionStart = DateTime.now();
          _gitaShlokasRead = 0;
        } else if (event == 'shloka_read') {
          _gitaShlokasRead++;
        } else if (event == 'end') {
          _gitaSessionStart = null;
          _gitaShlokasRead = 0;
        }
        break;
      case 'timer.session':
        if (event == 'complete') {
          final minutes = (data?['minutes'] as num?)?.toDouble() ?? 0.0;
          await _setDouble('timer.lastSessionMinutes', minutes);
          await _incrementToday('timer.sessionsCompleted');
          await _setTimestamp('timer.lastSessionCompletedAt', DateTime.now());
        }
        break;
      default:
        break;
    }
  }

  Future<bool> maybeShowRewarded(
    String placementId, {
    Duration timeout = _defaultRewardedTimeout,
  }) async {
    try {
      await _waitUntilReady();
      final attempt = _beginAttempt('rewarded', placementId);
      AdHealth.printSnapshot(reason: 'maybeShowRewarded:$placementId');
      final placement = _placements[placementId] as Map<String, dynamic>?;
      _logAttempt('TRY rewarded $placementId');

      if (!_isPlacementEnabled(placement, 'rewarded')) {
        _completeAttempt(attempt, 'skipped:placement_disabled');
        _logAttempt('SKIP (placement disabled)');
        return false;
      }
      if (!_isGlobalEnabled()) {
        _completeAttempt(attempt, 'skipped:global_disabled');
        _logAttempt('SKIP (global disabled)');
        return false;
      }

      final gatesInfo = <String>[];
      if (!await _canServe('rewarded', placementId, placement, gatesInfo)) {
        _completeAttempt(attempt, 'skipped:gates (${gatesInfo.join(', ')})');
        _logAttempt('Gates BLOCKED (${gatesInfo.join(', ')})');
        _ensureRewardedRetryScheduled(placementId);
        return false;
      }
      _logAttempt('Gates OK (${gatesInfo.join(', ')})');

      if (_testMode) {
        if (!_testRewardedOutcome) {
          _completeAttempt(attempt, 'skipped:test_override');
          _logAttempt('SKIP (test override false)');
          return false;
        }
        await _markServed('rewarded', placementId);
        _completeAttempt(attempt, 'shown:test_stub');
        return true;
      }

      RewardedAd? ad = _rewardedCache.remove(placementId);
      ad ??= await _loadRewarded(placementId, timeout: timeout);

      if (ad == null) {
        _completeAttempt(attempt, 'skipped:not_ready');
        _logAttempt('READY=false → SKIP (load failed)');
        _ensureRewardedRetryScheduled(placementId);
        return false;
      }

      _logAttempt('READY=true → SHOW');
      bool earned = false;
      final completer = Completer<bool>();

      ad.fullScreenContentCallback = FullScreenContentCallback(
        onAdShowedFullScreenContent: (_) {
          _logAttempt('SHOWN callback → success');
        },
        onAdDismissedFullScreenContent: (ad) async {
          _logAttempt('DISMISSED → reload scheduled');
          await _markServed('rewarded', placementId);
          ad.dispose();
          _preloadRewarded(placementId);
          _completeAttempt(
            attempt,
            earned ? 'shown:reward_earned' : 'shown:no_reward',
          );
          if (!completer.isCompleted) {
            completer.complete(earned);
          }
        },
        onAdFailedToShowFullScreenContent: (ad, error) {
          _logAttempt('FAILED_TO_SHOW → $error');
          ad.dispose();
          _ensureRewardedRetryScheduled(placementId);
          _completeAttempt(attempt, 'failed_to_show:$error');
          if (!completer.isCompleted) completer.complete(false);
        },
      );

      try {
        await ad.show(
          onUserEarnedReward: (_, reward) {
            earned = true;
            _logAttempt(
              'REWARD earned amount=${reward.amount} type=${reward.type}',
            );
          },
        );
      } catch (error) {
        ad.dispose();
        _ensureRewardedRetryScheduled(placementId);
        _completeAttempt(attempt, 'exception:$error');
        if (!completer.isCompleted) completer.complete(false);
      }

      return await completer.future;
    } catch (error, stackTrace) {
      _logError(
        'maybeShowRewarded exception: $error',
        stackTrace: stackTrace,
      );
      return false;
    }
  }

  Future<bool> maybeShowInterstitial(
    String placementId, {
    Duration timeout = const Duration(milliseconds: 1500),
  }) async {
    try {
      await _waitUntilReady();
      final attempt = _beginAttempt('interstitial', placementId);
      AdHealth.printSnapshot(reason: 'maybeShowInterstitial:$placementId');
      final placement = _placements[placementId] as Map<String, dynamic>?;
      _logAttempt('TRY interstitial $placementId');

      if (!_isPlacementEnabled(placement, 'interstitial')) {
        _completeAttempt(attempt, 'skipped:placement_disabled');
        _logAttempt('SKIP (placement disabled)');
        return false;
      }
      if (!_isGlobalEnabled()) {
        _completeAttempt(attempt, 'skipped:global_disabled');
        _logAttempt('SKIP (global disabled)');
        return false;
      }

      final conditionInfo = <String>[];
      if (!await _checkInterstitialConditions(
        placementId,
        placement,
        conditionInfo,
      )) {
        _completeAttempt(
          attempt,
          'skipped:conditions (${conditionInfo.join(', ')})',
        );
        _logAttempt('Conditions BLOCKED (${conditionInfo.join(', ')})');
        _ensureInterstitialRetryScheduled(placementId);
        return false;
      }

      final gatesInfo = <String>[];
      if (!await _canServe('interstitial', placementId, placement, gatesInfo)) {
        _completeAttempt(attempt, 'skipped:gates (${gatesInfo.join(', ')})');
        _logAttempt('Gates BLOCKED (${gatesInfo.join(', ')})');
        _ensureInterstitialRetryScheduled(placementId);
        return false;
      }
      _logAttempt('Gates OK (${gatesInfo.join(', ')})');

      if (_testMode) {
        if (!_testInterstitialOutcome) {
          _completeAttempt(attempt, 'skipped:test_override');
          _logAttempt('SKIP (test override false)');
          return false;
        }
        await _markServed('interstitial', placementId);
        _completeAttempt(attempt, 'shown:test_stub');
        return true;
      }

      InterstitialAd? ad = _interstitialCache.remove(placementId);
      ad ??= await _loadInterstitial(placementId, timeout: timeout);

      if (ad == null) {
        _completeAttempt(attempt, 'skipped:not_ready');
        _logAttempt('READY=false → SKIP (load failed)');
        _ensureInterstitialRetryScheduled(placementId);
        return false;
      }

      _logAttempt('READY=true → SHOW');
      final completer = Completer<bool>();

      ad.fullScreenContentCallback = FullScreenContentCallback(
        onAdShowedFullScreenContent: (_) {
          _logAttempt('SHOWN callback → success');
        },
        onAdDismissedFullScreenContent: (ad) async {
          _logAttempt('DISMISSED → reload scheduled');
          await _markServed('interstitial', placementId);
          ad.dispose();
          unawaited(_preloadInterstitial(placementId));
          _completeAttempt(attempt, 'shown:dismissed');
          if (!completer.isCompleted) completer.complete(true);
        },
        onAdFailedToShowFullScreenContent: (ad, error) {
          _logAttempt('FAILED_TO_SHOW → $error');
          ad.dispose();
          _ensureInterstitialRetryScheduled(placementId);
          _completeAttempt(attempt, 'failed_to_show:$error');
          if (!completer.isCompleted) completer.complete(false);
        },
      );

      try {
        await ad.show();
      } catch (error) {
        ad.dispose();
        _ensureInterstitialRetryScheduled(placementId);
        _completeAttempt(attempt, 'exception:$error');
        if (!completer.isCompleted) completer.complete(false);
      }

      return await completer.future;
    } catch (error, stackTrace) {
      _logError(
        'maybeShowInterstitial exception: $error',
        stackTrace: stackTrace,
      );
      return false;
    }
  }

  bool _isGlobalEnabled() => _global['enable_ads'] != false;

  bool _isPlacementEnabled(Map<String, dynamic>? placement, String type) {
    if (placement == null) return false;
    if (placement['type'] != type) return false;
    if (placement['enabled'] == false) return false;
    return true;
  }

  Future<bool> _canServe(
    String type,
    String placementId,
    Map<String, dynamic>? placement,
    List<String> debugLog,
  ) async {
    await _ensurePrefs();
    final now = DateTime.now();
    final globalConfig = (_global[type] as Map?)?.cast<String, dynamic>() ?? {};
    final placementCaps =
        (placement?['caps'] as Map?)?.cast<String, dynamic>() ?? {};

    final dailyCap = (placementCaps['daily_cap'] as num?)?.toInt();
    final globalDailyCap = (globalConfig['daily_cap'] as num?)?.toInt();

    if (globalDailyCap != null) {
      final count = await _getTodayCount('ad.$type.count');
      debugLog.add('globalDailyCap $count/$globalDailyCap');
      if (count >= globalDailyCap) return false;
    }

    if (dailyCap != null) {
      final count = await _getTodayCount('ad.$type.$placementId.count');
      debugLog.add('dailyCap $count/$dailyCap');
      if (count >= dailyCap) return false;
    }

    final minCooldownSeconds =
        (globalConfig['min_cooldown_seconds'] as num?)?.toInt() ?? 0;
    if (minCooldownSeconds > 0) {
      final lastGlobal = await _getTimestamp('ad.$type.lastShown');
      final seconds = lastGlobal == null
          ? null
          : now.difference(lastGlobal).inSeconds;
      debugLog.add('globalCooldown ${seconds ?? 'never'}/$minCooldownSeconds');
      if (seconds != null && seconds < minCooldownSeconds) {
        return false;
      }
    }

    final placementCooldown = (placementCaps['min_cooldown_seconds'] as num?)
        ?.toInt();
    if (placementCooldown != null && placementCooldown > 0) {
      final lastPlacement = await _getTimestamp(
        'ad.$type.$placementId.lastShown',
      );
      final seconds = lastPlacement == null
          ? null
          : now.difference(lastPlacement).inSeconds;
      debugLog.add('cooldown ${seconds ?? 'never'}/$placementCooldown');
      if (seconds != null && seconds < placementCooldown) {
        return false;
      }
    }

    if (type == 'interstitial') {
      final skipRecentSeconds =
          (globalConfig['skip_if_last_interstitial_within_seconds'] as num?)
              ?.toInt();
      if (skipRecentSeconds != null && skipRecentSeconds > 0) {
        final lastAnyInterstitial = _lastInterstitialShownTime;
        final seconds = lastAnyInterstitial == null
            ? null
            : now.difference(lastAnyInterstitial).inSeconds;
        debugLog.add(
          'recentInterstitial ${seconds ?? 'never'}/$skipRecentSeconds',
        );
        if (seconds != null && seconds < skipRecentSeconds) {
          return false;
        }
      }
    }

    return true;
  }

  Future<bool> _checkInterstitialConditions(
    String placementId,
    Map<String, dynamic>? placement,
    List<String> debugLog,
  ) async {
    if (placement == null) return false;
    final conditions =
        (placement['conditions'] as Map?)?.cast<String, dynamic>() ?? {};
    final now = DateTime.now();

    switch (placementId) {
      case 'gita.long_session_interstitial':
        final minShlokas =
            (conditions['min_shlokas_read'] as num?)?.toInt() ?? 0;
        final minTimeMs = (conditions['min_time_ms'] as num?)?.toInt() ?? 0;
        final skipIfRewardedWithin =
            (conditions['skip_if_rewarded_shown_within_seconds'] as num?)
                ?.toInt() ??
            0;
        debugLog.add('shlokas $_gitaShlokasRead/$minShlokas');
        if (_gitaSessionStart == null) {
          debugLog.add('session not started');
          return false;
        }
        if (_gitaShlokasRead < minShlokas) {
          return false;
        }
        final elapsed = now.difference(_gitaSessionStart!).inMilliseconds;
        debugLog.add('elapsed ${elapsed}ms/$minTimeMs');
        if (elapsed < minTimeMs) return false;
        if (_lastRewardedShownTime != null) {
          final seconds = now.difference(_lastRewardedShownTime!).inSeconds;
          debugLog.add('rewardedAgo $seconds/${skipIfRewardedWithin}s');
          if (seconds < skipIfRewardedWithin) {
            return false;
          }
        }
        return true;
      case 'timer.post_session_interstitial':
        final minMinutes =
            (conditions['skip_if_session_minutes_lt'] as num?)?.toDouble() ?? 0;
        final minDuration = await _getDouble('timer.lastSessionMinutes') ?? 0.0;
        debugLog.add('sessionMinutes $minDuration/$minMinutes');
        if (minDuration < minMinutes) return false;

        final pattern = placement['pattern'] as String? ?? 'every_session';
        if (pattern == 'every_2nd_session') {
          final sessionsCompletedToday = await _getTodayCount(
            'timer.sessionsCompleted',
          );
          debugLog.add(
            'sessionsToday $sessionsCompletedToday (pattern $pattern)',
          );
          if (sessionsCompletedToday % 2 != 0) {
            return false;
          }
        }

        final lastAnyInterstitial =
            _lastInterstitialShownTime ??
            await _getTimestamp('ad.interstitial.lastShown');
        final skipIfAnyWithin =
            (conditions['skip_if_any_interstitial_within_seconds'] as num?)
                ?.toInt() ??
            0;
        if (lastAnyInterstitial != null) {
          final seconds = now.difference(lastAnyInterstitial).inSeconds;
          debugLog.add('anyInterstitialAgo $seconds/$skipIfAnyWithin');
          if (seconds < skipIfAnyWithin) {
            return false;
          }
        }
        return true;
      default:
        return true;
    }
  }

  Future<void> _markServed(String type, String placementId) async {
    await _incrementToday('ad.$type.count');
    await _incrementToday('ad.$type.$placementId.count');
    await _setTimestamp('ad.$type.lastShown', DateTime.now());
    await _setTimestamp('ad.$type.$placementId.lastShown', DateTime.now());

    if (type == 'rewarded') {
      _lastRewardedShownTime = DateTime.now();
    } else if (type == 'interstitial') {
      _lastInterstitialShownTime = DateTime.now();
      await _setTimestamp('timer.lastInterstitialAt', DateTime.now());
    }
  }

  Future<RewardedAd?> _loadRewarded(
    String placementId, {
    required Duration timeout,
  }) async {
    final unitId = _activeRewardedUnitIds[placementId];
    if (unitId == null) {
      _logWarn('No rewarded ad unit configured for $placementId');
      return null;
    }
    final completer = Completer<RewardedAd?>();
    final timer = Timer(timeout, () {
      if (!completer.isCompleted) {
        _logAttempt('LOAD timeout ($timeout) for $placementId');
        completer.complete(null);
      }
    });

    RewardedAd.load(
      adUnitId: unitId,
      request: AdRequest(nonPersonalizedAds: _serveNpa),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (ad) {
          timer.cancel();
          _logAttempt('LOAD success $placementId (id=$unitId)');
          if (!completer.isCompleted) {
            completer.complete(ad);
          } else {
            ad.dispose();
          }
        },
        onAdFailedToLoad: (error) {
          timer.cancel();
          _logAttempt('LOAD failed $placementId → $error');
          if (!completer.isCompleted) completer.complete(null);
        },
      ),
    );

    return completer.future;
  }

  Future<void> _preloadRewarded(
    String placementId, {
    bool force = false,
  }) async {
    if (!force && _rewardedCache[placementId] != null) return;
    final placement = _placements[placementId] as Map<String, dynamic>?;
    if (!_isPlacementEnabled(placement, 'rewarded')) return;
    final ad = await _loadRewarded(
      placementId,
      timeout: _rewardedTimeout(placement),
    );
    if (ad != null) {
      _rewardedRetryTimers.remove(placementId)?.cancel();
      _rewardedRetryCounts[placementId] = 0;
      _rewardedCache[placementId]?.dispose();
      _rewardedCache[placementId] = ad;
      _logAttempt('PRELOAD rewarded ready → $placementId');
    } else {
      _ensureRewardedRetryScheduled(placementId);
    }
  }

  Future<InterstitialAd?> _loadInterstitial(
    String placementId, {
    required Duration timeout,
  }) async {
    final unitId = _activeInterstitialUnitIds[placementId];
    if (unitId == null) {
      _logWarn('No interstitial ad unit configured for $placementId');
      return null;
    }

    final completer = Completer<InterstitialAd?>();
    final timer = Timer(timeout, () {
      if (!completer.isCompleted) {
        _logAttempt('LOAD timeout ($timeout) for $placementId');
        completer.complete(null);
      }
    });

    InterstitialAd.load(
      adUnitId: unitId,
      request: AdRequest(nonPersonalizedAds: _serveNpa),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) {
          timer.cancel();
          _logAttempt('LOAD success $placementId (id=$unitId)');
          if (!completer.isCompleted) {
            completer.complete(ad);
          }
        },
        onAdFailedToLoad: (error) {
          timer.cancel();
          _logAttempt('LOAD failed $placementId → $error');
          if (!completer.isCompleted) completer.complete(null);
        },
      ),
    );

    return completer.future;
  }

  Future<void> _preloadInterstitial(
    String placementId, {
    bool force = false,
  }) async {
    if (!force && _interstitialCache[placementId] != null) return;
    final placement = _placements[placementId] as Map<String, dynamic>?;
    if (!_isPlacementEnabled(placement, 'interstitial')) return;
    final ad = await _loadInterstitial(
      placementId,
      timeout: const Duration(seconds: 4),
    );
    if (ad != null) {
      _interstitialRetryTimers.remove(placementId)?.cancel();
      _interstitialRetryCounts[placementId] = 0;
      _interstitialCache[placementId]?.dispose();
      _interstitialCache[placementId] = ad;
      _logAttempt('PRELOAD interstitial ready → $placementId');
    } else {
      _ensureInterstitialRetryScheduled(placementId);
    }
  }

  Duration _rewardedTimeout(Map<String, dynamic>? placement) {
    final globalTimeoutMs =
        ((_global['rewarded'] as Map?)?['skip_if_not_ready_after_ms'] as num?)
            ?.toInt() ??
        _defaultRewardedTimeout.inMilliseconds;
    final placementTimeoutMs =
        ((placement?['caps'] as Map?)?['skip_if_not_ready_after_ms'] as num?)
            ?.toInt();
    final effective = placementTimeoutMs ?? globalTimeoutMs;
    return Duration(milliseconds: effective);
  }

  Future<int> _getTodayCount(String key) async {
    final todayKey = _todayKey(key);
    return _prefs?.getInt(todayKey) ?? 0;
  }

  Future<void> _incrementToday(String key) async {
    final todayKey = _todayKey(key);
    final current = _prefs?.getInt(todayKey) ?? 0;
    await _prefs?.setInt(todayKey, current + 1);
  }

  Future<DateTime?> _getTimestamp(String key) async {
    final ms = _prefs?.getInt(key);
    if (ms == null) return null;
    return DateTime.fromMillisecondsSinceEpoch(ms);
  }

  Future<void> _setTimestamp(String key, DateTime value) async {
    await _prefs?.setInt(key, value.millisecondsSinceEpoch);
  }

  Future<double?> _getDouble(String key) async {
    return _prefs?.getDouble(_todayKey(key)) ?? _prefs?.getDouble(key);
  }

  Future<void> _setDouble(String key, double value) async {
    await _prefs?.setDouble(_todayKey(key), value);
  }

  Map<String, dynamic> _flattenPlacements(
    Map<String, dynamic> node, [
    String prefix = '',
  ]) {
    final Map<String, dynamic> result = {};
    node.forEach((key, value) {
      final nextPrefix = prefix.isEmpty ? key : '$prefix.$key';
      if (value is Map<String, dynamic>) {
        if (value.containsKey('type')) {
          result[nextPrefix] = value;
        } else {
          result.addAll(_flattenPlacements(value, nextPrefix));
        }
      }
    });
    return result;
  }

  Future<void> _ensurePrefs() async {
    _prefs ??= await SharedPreferences.getInstance();
  }

  Future<void> _waitUntilReady() async {
    if (_bootstrapFuture == null) {
      _logWarn('AdManager used before bootstrap. Running fallback bootstrap.');
      await bootstrap();
    }
    await _bootstrapFuture;
  }

  void _updateActiveAdUnitIds() {
    final testRewarded = <String, String>{
      'stats.share_rewarded': 'ca-app-pub-3940256099942544/5224354917',
      'gita.share_rewarded': 'ca-app-pub-3940256099942544/5224354917',
      'timer.share_rewarded': 'ca-app-pub-3940256099942544/5224354917',
    };

    final testInterstitial = <String, String>{
      'gita.long_session_interstitial':
          'ca-app-pub-3940256099942544/1033173712',
      'timer.post_session_interstitial':
          'ca-app-pub-3940256099942544/1033173712',
    };

    final rewarded = useTestIds
        ? testRewarded
        : (_productionRewardedUnitIds.isEmpty
              ? testRewarded
              : _productionRewardedUnitIds);
    final interstitial = useTestIds
        ? testInterstitial
        : (_productionInterstitialUnitIds.isEmpty
              ? testInterstitial
              : _productionInterstitialUnitIds);

    _activeRewardedUnitIds
      ..clear()
      ..addAll(rewarded);
    _activeInterstitialUnitIds
      ..clear()
      ..addAll(interstitial);

    _logInfo(
      'Ad units active (mode=${useTestIds ? 'TEST' : 'PROD'}) '
      'rewarded=${_activeRewardedUnitIds.values.toSet()} '
      'interstitial=${_activeInterstitialUnitIds.values.toSet()}',
    );
  }

  void setUseTestIds(bool value) {
    if (useTestIds == value) return;
    useTestIds = value;
    _updateActiveAdUnitIds();
    _logInfo('useTestIds toggled → $useTestIds');
  }

  void _ensureRewardedRetryScheduled(String placementId) {
    final attempt = (_rewardedRetryCounts[placementId] ?? 0) + 1;
    _rewardedRetryCounts[placementId] = attempt;
    final delay = attempt == 1
        ? const Duration(seconds: 5)
        : const Duration(seconds: 15);
    _rewardedRetryTimers[placementId]?.cancel();
    _rewardedRetryTimers[placementId] = Timer(delay, () {
      _logAttempt(
        'Retrying rewarded preload for $placementId (attempt $attempt)',
      );
      _preloadRewarded(placementId, force: true);
    });
  }

  void _ensureInterstitialRetryScheduled(String placementId) {
    final attempt = (_interstitialRetryCounts[placementId] ?? 0) + 1;
    _interstitialRetryCounts[placementId] = attempt;
    final delay = attempt == 1
        ? const Duration(seconds: 5)
        : const Duration(seconds: 15);
    _interstitialRetryTimers[placementId]?.cancel();
    _interstitialRetryTimers[placementId] = Timer(delay, () {
      _logAttempt(
        'Retrying interstitial preload for $placementId (attempt $attempt)',
      );
      _preloadInterstitial(placementId, force: true);
    });
  }

  String _todayKey(String base) {
    final now = DateTime.now();
    final date = DateFormat('yyyyMMdd').format(now);
    return '$base.$date';
  }

  _AdAttemptLog _beginAttempt(String type, String placementId) {
    final entry = _AdAttemptLog(
      timestamp: DateTime.now(),
      placementId: placementId,
      type: type,
    );
    _attemptHistory.add(entry);
    while (_attemptHistory.length > _attemptHistoryLimit) {
      _attemptHistory.removeFirst();
    }
    return entry;
  }

  void _completeAttempt(_AdAttemptLog attempt, String result) {
    attempt.result = result;
  }

  void _logAttempt(String message) {
    _logInfo(message);
  }

  void _logInfo(String message) {
    if (kDebugMode) {
      debugPrint('$_logTag $message');
    }
  }

  void _logWarn(String message) {
    if (kDebugMode) {
      debugPrint('$_logTag WARN $message');
    }
  }

  void _logError(String message, {StackTrace? stackTrace}) {
    if (kDebugMode) {
      debugPrint(
        '$_logTag ERROR $message${stackTrace != null ? '\n$stackTrace' : ''}',
      );
    }
  }

  bool get isAdMobInitialized => _adMobInitialized;
  bool get policyLoaded => _policyLoaded;
  String? get policySource => _policySource;
  String? get policyLoadError => _policyLoadError;
  String get consentStatusLabel => _consentStatusLabel;

  Map<String, dynamic> get globalConfig => _global;
  bool get rewardedReady =>
      _rewardedCache.values.any((ad) => ad.responseInfo != null);
  bool get interstitialReady =>
      _interstitialCache.values.any((ad) => ad.responseInfo != null);
  List<String> get lastAttempts =>
      _attemptHistory.map((entry) => entry.describe()).toList(growable: false);
  bool get adsGloballyEnabled => _isGlobalEnabled();

  AdHealthSnapshot _buildAdHealthSnapshot() {
    final interstitialConfig =
        ((_global['interstitial'] as Map?)?.cast<String, dynamic>() ?? {});
    final rewardedConfig =
        ((_global['rewarded'] as Map?)?.cast<String, dynamic>() ?? {});

    return AdHealthSnapshot(
      adMobInitialized: _adMobInitialized,
      consentStatus: _consentStatusLabel,
      serveNpa: _serveNpa,
      policyLoaded: _policyLoaded,
      policySource: _policySource,
      policyLoadError: _policyLoadError,
      policyVersion: (_policy['version'] as String?) ?? _fallbackPolicyVersion,
      adsEnabled: adsGloballyEnabled,
      useTestIds: useTestIds,
      globalInterstitialConfig: Map<String, dynamic>.unmodifiable(
        interstitialConfig,
      ),
      globalRewardedConfig: Map<String, dynamic>.unmodifiable(rewardedConfig),
      rewardedReady: rewardedReady,
      interstitialReady: interstitialReady,
      preloadedRewardedCount: _rewardedCache.length,
      preloadedInterstitialCount: _interstitialCache.length,
      attemptLog: List<String>.unmodifiable(lastAttempts),
    );
  }

  @visibleForTesting
  Future<void> debugConfigureForTests(Map<String, dynamic> policy) async {
    _policy = policy;
    _global = (policy['global'] as Map?)?.cast<String, dynamic>() ?? {};
    final placements =
        (policy['placements'] as Map?)?.cast<String, dynamic>() ?? {};
    _placements
      ..clear()
      ..addAll(_flattenPlacements(placements));
    _prefs = await SharedPreferences.getInstance();
    _policyLoaded = true;
    _updateActiveAdUnitIds();
  }

  @visibleForTesting
  void debugSetTestMode({
    required bool enabled,
    bool rewardedOutcome = true,
    bool interstitialOutcome = true,
  }) {
    _testMode = enabled;
    _testRewardedOutcome = rewardedOutcome;
    _testInterstitialOutcome = interstitialOutcome;
  }

  @visibleForTesting
  Future<void> debugResetStorage() async {
    await _prefs?.clear();
    _lastRewardedShownTime = null;
    _lastInterstitialShownTime = null;
    _gitaSessionStart = null;
    _gitaShlokasRead = 0;
  }

  @visibleForTesting
  void debugSetGitaSession({DateTime? start, int shlokas = 0}) {
    _gitaSessionStart = start;
    _gitaShlokasRead = shlokas;
  }

  @visibleForTesting
  Future<void> debugSetTimerStats({
    double? lastSessionMinutes,
    DateTime? lastSessionCompletedAt,
  }) async {
    if (lastSessionMinutes != null) {
      await _setDouble('timer.lastSessionMinutes', lastSessionMinutes);
    }
    if (lastSessionCompletedAt != null) {
      await _setTimestamp(
        'timer.lastSessionCompletedAt',
        lastSessionCompletedAt,
      );
    }
  }

  @visibleForTesting
  void debugSetLastInterstitialShown(DateTime? when) {
    _lastInterstitialShownTime = when;
  }

  /// Dispose method to clean up resources and prevent memory leaks
  void dispose() {
    // Cancel all retry timers
    for (final timer in _rewardedRetryTimers.values) {
      timer.cancel();
    }
    for (final timer in _interstitialRetryTimers.values) {
      timer.cancel();
    }
    _rewardedRetryTimers.clear();
    _interstitialRetryTimers.clear();
    
    // Dispose all cached ads
    for (final ad in _rewardedCache.values) {
      ad.dispose();
    }
    for (final ad in _interstitialCache.values) {
      ad.dispose();
    }
    _rewardedCache.clear();
    _interstitialCache.clear();
  }
}

class _AdAttemptLog {
  _AdAttemptLog({
    required this.timestamp,
    required this.placementId,
    required this.type,
  });

  final DateTime timestamp;
  final String placementId;
  final String type;
  String result = 'pending';

  String describe() =>
      '${timestamp.toIso8601String()} $type $placementId → $result';
}
