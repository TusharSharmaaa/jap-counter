import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Singleton that encapsulates all ad policy, consent handling and serving logic.
///
/// The manager loads the policy from `assets/config/ad_policy.json`, handles
/// UMP consent, enforces global/placement caps & cooldowns, and exposes simple
/// APIs that the UI can call when an ad _may_ be shown. If an ad is not allowed,
/// fails to load, or times out, the call resolves with `false` and the caller
/// must continue its primary action (per policy fail-safe rule).
class AdManager {
  AdManager._internal();

  static final AdManager instance = AdManager._internal();

  static const _policyAssetPath = 'assets/config/ad_policy.json';

  // Ad unit ids (Google test ids for now).
  static const Map<String, String> _rewardedUnitIds = {
    'stats.share_rewarded': 'ca-app-pub-3940256099942544/5224354917',
    'gita.share_rewarded': 'ca-app-pub-3940256099942544/5224354917',
    'timer.share_rewarded': 'ca-app-pub-3940256099942544/5224354917',
  };

  static const Map<String, String> _interstitialUnitIds = {
    'gita.long_session_interstitial': 'ca-app-pub-3940256099942544/1033173712',
    'timer.post_session_interstitial': 'ca-app-pub-3940256099942544/1033173712',
  };

  final Map<String, dynamic> _placements = {};
  Map<String, dynamic> _global = {};
  Map<String, dynamic> _policy = {};

  SharedPreferences? _prefs;
  bool _initialized = false;
  bool _serveNpa = false;

  final Map<String, RewardedAd> _rewardedCache = {};
  final Map<String, InterstitialAd> _interstitialCache = {};

  // In-memory session tracking (reset per process).
  DateTime? _gitaSessionStart;
  int _gitaShlokasRead = 0;
  DateTime? _lastRewardedShownTime;
  DateTime? _lastInterstitialShownTime;
  bool _testMode = false;
  bool _testRewardedOutcome = true;
  bool _testInterstitialOutcome = true;

  static Future<void> ensureInitialized() => instance._init();

  Future<void> _init() async {
    if (_initialized) return;
    _prefs = await SharedPreferences.getInstance();
    await _loadPolicy();
    await _requestConsentIfNeeded();
    _initialized = true;
    await preload();
  }

  Future<void> _loadPolicy() async {
    final raw = await rootBundle.loadString(_policyAssetPath);
    _policy = json.decode(raw) as Map<String, dynamic>;
    _global = (_policy['global'] as Map?)?.cast<String, dynamic>() ?? {};
    final placements =
        (_policy['placements'] as Map?)?.cast<String, dynamic>() ?? {};
    _placements
      ..clear()
      ..addAll(_flattenPlacements(placements));
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

  Future<void> _requestConsentIfNeeded() async {
    if (kDebugMode) {
      _serveNpa = true;
      return;
    }
    final consentConfig =
        (_global['consent'] as Map?)?.cast<String, dynamic>() ?? {};
    final useUmp = consentConfig['use_ump'] == true;
    if (!useUmp) return;

    try {
      _serveNpa = true; // default to non-personalized until consent known.
      final consentInfo = ConsentInformation.instance;
      final params = ConsentRequestParameters();
      final updateCompleter = Completer<void>();
      consentInfo.requestConsentInfoUpdate(
        params,
        () => updateCompleter.complete(),
        (error) => updateCompleter.completeError(error),
      );
      await updateCompleter.future;

      if (await consentInfo.isConsentFormAvailable()) {
        await ConsentForm.loadAndShowConsentFormIfRequired((formError) {
          if (formError != null && kDebugMode) {
            debugPrint('[AdManager] Consent form error: ${formError.message}');
          }
        });
      }

      final status = await consentInfo.getConsentStatus();
      if (status == ConsentStatus.obtained ||
          status == ConsentStatus.notRequired) {
        _serveNpa = false;
      } else if (consentConfig['serve_npa_if_declined'] != true) {
        _serveNpa = false;
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[AdManager] Consent flow failed: $e');
      }
      // Default to non-personalized if consent failed.
      _serveNpa = true;
    }
  }

  /// Preloads the placements defined in the policy.
  Future<void> preload() async {
    if (_testMode) return;
    await _init();
    final preloadConfig =
        (_policy['preload'] as Map?)?.cast<String, dynamic>() ?? {};
    final rewarded = (preloadConfig['rewarded'] as List?)?.cast<String>() ?? [];
    final interstitial =
        (preloadConfig['interstitial'] as List?)?.cast<String>() ?? [];

    for (final id in rewarded) {
      await _preloadRewarded(id);
    }
    for (final id in interstitial) {
      await _preloadInterstitial(id);
    }
  }

  Future<void> recordEvent(
    String placementId,
    String event, {
    Map<String, dynamic>? data,
  }) async {
    if (!_initialized) await _init();

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
    Duration? timeout,
  }) async {
    await _init();
    final placement = _placements[placementId] as Map<String, dynamic>?;
    if (!_isPlacementEnabled(placement, 'rewarded')) {
      return false;
    }
    if (!_isGlobalEnabled()) return false;

    if (!await _canServe('rewarded', placementId, placement)) {
      _log(placementId, 'ad_skipped', {'reason': 'caps_or_cooldown'});
      return false;
    }

    if (_testMode) {
      if (!_testRewardedOutcome) {
        _log(placementId, 'ad_skipped', {'reason': 'test_override'});
        return false;
      }
      await _markServed('rewarded', placementId);
      return true;
    }

    _log(placementId, 'ad_request');
    RewardedAd? ad = _rewardedCache.remove(placementId);
    ad ??= await _loadRewarded(
      placementId,
      timeout: timeout ?? _rewardedTimeout(placement),
    );

    if (ad == null) {
      _log(placementId, 'ad_failed_to_load');
      _preloadRewarded(placementId);
      return false;
    }

    final completer = Completer<bool>();
    bool earned = false;
    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdShowedFullScreenContent: (ad) {
        _log(placementId, 'ad_shown');
      },
      onAdDismissedFullScreenContent: (ad) async {
        _log(placementId, 'ad_dismissed');
        await _markServed('rewarded', placementId);
        ad.dispose();
        _preloadRewarded(placementId);
        completer.complete(earned);
      },
      onAdFailedToShowFullScreenContent: (ad, error) {
        _log(placementId, 'ad_failed_to_load', {'error': '$error'});
        ad.dispose();
        _preloadRewarded(placementId);
        if (!completer.isCompleted) completer.complete(false);
      },
    );

    try {
      await ad.show(
        onUserEarnedReward: (ad, reward) {
          earned = true;
          _log(placementId, 'ad_reward_earned', {
            'amount': reward.amount,
            'type': reward.type,
          });
        },
      );
    } catch (e) {
      ad.dispose();
      _preloadRewarded(placementId);
      if (!completer.isCompleted) completer.complete(false);
    }

    final result = await completer.future;
    return result;
  }

  Future<bool> maybeShowInterstitial(
    String placementId, {
    Duration? timeout,
  }) async {
    await _init();
    final placement = _placements[placementId] as Map<String, dynamic>?;
    if (!_isPlacementEnabled(placement, 'interstitial')) {
      return false;
    }
    if (!_isGlobalEnabled()) return false;

    if (!await _checkInterstitialConditions(placementId, placement)) {
      _log(placementId, 'ad_skipped', {'reason': 'conditions_not_met'});
      return false;
    }

    if (!await _canServe('interstitial', placementId, placement)) {
      _log(placementId, 'ad_skipped', {'reason': 'caps_or_cooldown'});
      return false;
    }

    if (_testMode) {
      if (!_testInterstitialOutcome) {
        _log(placementId, 'ad_skipped', {'reason': 'test_override'});
        return false;
      }
      await _markServed('interstitial', placementId);
      return true;
    }

    _log(placementId, 'ad_request');
    InterstitialAd? ad = _interstitialCache.remove(placementId);
    ad ??= await _loadInterstitial(placementId, timeout: timeout);

    if (ad == null) {
      _log(placementId, 'ad_failed_to_load');
      return false;
    }

    final completer = Completer<bool>();
    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdShowedFullScreenContent: (ad) {
        _log(placementId, 'ad_shown');
      },
      onAdDismissedFullScreenContent: (ad) async {
        _log(placementId, 'ad_dismissed');
        await _markServed('interstitial', placementId);
        ad.dispose();
        unawaited(_preloadInterstitial(placementId));
        completer.complete(true);
      },
      onAdFailedToShowFullScreenContent: (ad, error) {
        _log(placementId, 'ad_failed_to_load', {'error': '$error'});
        ad.dispose();
        if (!completer.isCompleted) completer.complete(false);
      },
    );

    try {
      await ad.show();
    } catch (e) {
      ad.dispose();
      if (!completer.isCompleted) completer.complete(false);
      unawaited(_preloadInterstitial(placementId));
    }

    final shown = await completer.future;
    return shown;
  }

  bool _isGlobalEnabled() => _global['enable_ads'] != false;

  bool _isPlacementEnabled(Map<String, dynamic>? placement, String type) {
    if (placement == null) return false;
    if (placement['type'] != type) return false;
    if (placement['enabled'] == false) return false;
    return true;
  }

  Duration _rewardedTimeout(Map<String, dynamic>? placement) {
    final globalTimeoutMs =
        ((_global['rewarded'] as Map?)?['skip_if_not_ready_after_ms'] as num?)
            ?.toInt() ??
        1500;
    final placementTimeoutMs =
        ((placement?['caps'] as Map?)?['skip_if_not_ready_after_ms'] as num?)
            ?.toInt();
    final effective = placementTimeoutMs ?? globalTimeoutMs;
    return Duration(milliseconds: effective);
  }

  Future<bool> _canServe(
    String type,
    String placementId,
    Map<String, dynamic>? placement,
  ) async {
    final now = DateTime.now();
    final globalConfig = (_global[type] as Map?)?.cast<String, dynamic>() ?? {};
    final placementCaps =
        (placement?['caps'] as Map?)?.cast<String, dynamic>() ?? {};

    final dailyCap = (placementCaps['daily_cap'] as num?)?.toInt();
    final globalDailyCap = (globalConfig['daily_cap'] as num?)?.toInt();

    if (globalDailyCap != null) {
      final count = await _getTodayCount('ad.$type.count');
      if (count >= globalDailyCap) return false;
    }
    if (dailyCap != null) {
      final count = await _getTodayCount('ad.$type.$placementId.count');
      if (count >= dailyCap) return false;
    }

    final minCooldownSeconds =
        (globalConfig['min_cooldown_seconds'] as num?)?.toInt() ?? 0;
    if (minCooldownSeconds > 0) {
      final lastGlobal = await _getTimestamp('ad.$type.lastShown');
      if (lastGlobal != null &&
          now.difference(lastGlobal).inSeconds < minCooldownSeconds) {
        return false;
      }
    }

    final placementCooldown = (placementCaps['min_cooldown_seconds'] as num?)
        ?.toInt();
    if (placementCooldown != null && placementCooldown > 0) {
      final lastPlacement = await _getTimestamp(
        'ad.$type.$placementId.lastShown',
      );
      if (lastPlacement != null &&
          now.difference(lastPlacement).inSeconds < placementCooldown) {
        return false;
      }
    }

    if (type == 'interstitial') {
      final skipRecentSeconds =
          (globalConfig['skip_if_last_interstitial_within_seconds'] as num?)
              ?.toInt();
      if (skipRecentSeconds != null && skipRecentSeconds > 0) {
        final lastAnyInterstitial = _lastInterstitialShownTime;
        if (lastAnyInterstitial != null &&
            now.difference(lastAnyInterstitial).inSeconds < skipRecentSeconds) {
          return false;
        }
      }
    }

    return true;
  }

  Future<bool> _checkInterstitialConditions(
    String placementId,
    Map<String, dynamic>? placement,
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
        if (_gitaSessionStart == null) return false;
        if (_gitaShlokasRead < minShlokas) return false;
        final elapsed = now.difference(_gitaSessionStart!).inMilliseconds;
        if (elapsed < minTimeMs) return false;
        if (_lastRewardedShownTime != null &&
            now.difference(_lastRewardedShownTime!).inSeconds <
                skipIfRewardedWithin) {
          return false;
        }
        return true;
      case 'timer.post_session_interstitial':
        final minMinutes =
            (conditions['skip_if_session_minutes_lt'] as num?)?.toDouble() ?? 0;
        final minDuration = await _getDouble('timer.lastSessionMinutes') ?? 0.0;
        if (minDuration < minMinutes) return false;

        final pattern = placement['pattern'] as String? ?? 'every_session';
        if (pattern == 'every_2nd_session') {
          final sessionsCompletedToday = await _getTodayCount(
            'timer.sessionsCompleted',
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
        if (lastAnyInterstitial != null &&
            now.difference(lastAnyInterstitial).inSeconds < skipIfAnyWithin) {
          return false;
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
    Duration? timeout,
  }) async {
    final unitId = _rewardedUnitIds[placementId];
    if (unitId == null) return null;
    final completer = Completer<RewardedAd?>();
    final timer = timeout == null
        ? null
        : Timer(timeout, () {
            if (!completer.isCompleted) {
              completer.complete(null);
            }
          });

    RewardedAd.load(
      adUnitId: unitId,
      request: AdRequest(nonPersonalizedAds: _serveNpa),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (ad) {
          timer?.cancel();
          if (!completer.isCompleted) {
            if (kDebugMode) {
              debugPrint('[AdManager] Rewarded loaded for $placementId');
            }
            completer.complete(ad);
          } else {
            ad.dispose();
          }
        },
        onAdFailedToLoad: (error) {
          timer?.cancel();
          if (kDebugMode) {
            debugPrint('[AdManager] Rewarded load failed: $error');
          }
          if (!completer.isCompleted) completer.complete(null);
        },
      ),
    );

    final ad = await completer.future;
    return ad;
  }

  Future<void> _preloadRewarded(String placementId) async {
    final ad = await _loadRewarded(placementId);
    if (ad != null) {
      _rewardedCache[placementId]?.dispose();
      _rewardedCache[placementId] = ad;
      _log(placementId, 'ad_loaded');
    }
  }

  Future<InterstitialAd?> _loadInterstitial(
    String placementId, {
    Duration? timeout,
  }) async {
    final unitId = _interstitialUnitIds[placementId];
    if (unitId == null) return null;
    final completer = Completer<InterstitialAd?>();
    final timer = timeout == null
        ? null
        : Timer(timeout, () {
            if (!completer.isCompleted) completer.complete(null);
          });

    InterstitialAd.load(
      adUnitId: unitId,
      request: AdRequest(nonPersonalizedAds: _serveNpa),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) {
          timer?.cancel();
          if (!completer.isCompleted) {
            if (kDebugMode) {
              debugPrint('[AdManager] Interstitial loaded for $placementId');
            }
            completer.complete(ad);
          }
        },
        onAdFailedToLoad: (error) {
          timer?.cancel();
          if (kDebugMode) {
            debugPrint('[AdManager] Interstitial load failed: $error');
          }
          if (!completer.isCompleted) completer.complete(null);
        },
      ),
    );

    return completer.future;
  }

  Future<void> _preloadInterstitial(String placementId) async {
    final ad = await _loadInterstitial(placementId);
    if (ad != null) {
      _interstitialCache[placementId]?.dispose();
      _interstitialCache[placementId] = ad;
      _log(placementId, 'ad_loaded');
    }
  }

  Future<void> preloadPlacement(String placementId) async {
    await _init();
    final placement = _placements[placementId] as Map<String, dynamic>?;
    if (placement == null) return;
    final type = placement['type'];
    if (type == 'rewarded') {
      await _preloadRewarded(placementId);
    } else if (type == 'interstitial') {
      await _preloadInterstitial(placementId);
    }
  }

  Future<void> preloadAll() async {
    await _init();
    for (final entry in _rewardedUnitIds.keys) {
      await _preloadRewarded(entry);
    }
    for (final entry in _interstitialUnitIds.keys) {
      await _preloadInterstitial(entry);
    }
  }

  Future<bool> showRewardedAd(String placementId,
      {Duration? timeout}) async {
    return maybeShowRewarded(placementId, timeout: timeout);
  }

  Future<bool> showInterstitialAd(String placementId,
      {Duration? timeout}) async {
    return maybeShowInterstitial(placementId, timeout: timeout);
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

  String _todayKey(String base) {
    final now = DateTime.now();
    final date = DateFormat('yyyyMMdd').format(now);
    return '$base.$date';
  }

  void _log(String placementId, String event, [Map<String, dynamic>? data]) {
    if (kDebugMode) {
      debugPrint('[AdManager] $placementId → $event ${data ?? {}}');
    }
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
    _initialized = true;
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
}
