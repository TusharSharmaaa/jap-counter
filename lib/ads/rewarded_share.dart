import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:flutter/foundation.dart';
import 'dart:async' show Completer, unawaited;

/// Rewarded ad used to gate the "Share My Streak" action on the Stats tab.
/// Test unit ID from Google: https://developers.google.com/admob/flutter/test-ads
/// Android Rewarded (TEST): ca-app-pub-3940256099942544/5224354917
class RewardedShareAd {
  RewardedAd? _ad;
  bool _isLoading = false;
  bool _invalidated = false;
  // NEW: capture result across callbacks, complete only after dismiss
  Completer<bool>? _activeCompleter;
  bool _earnedThisImpression = false;
  DateTime? _lastRewardTime;
  static const Duration _minGapBetweenRewards = Duration(minutes: 3);

  static final RewardedShareAd _instance = RewardedShareAd._internal();
  RewardedShareAd._internal();
  factory RewardedShareAd() => _instance;
  static RewardedShareAd get instance => _instance;

  static const String _testUnitId = 'ca-app-pub-3940256099942544/5224354917';

  bool get isCoolingDown {
    if (_lastRewardTime == null) return false;
    return DateTime.now().difference(_lastRewardTime!) < _minGapBetweenRewards;
  }

  Duration? get cooldownRemaining {
    if (_lastRewardTime == null) return null;
    final elapsed = DateTime.now().difference(_lastRewardTime!);
    final remaining = _minGapBetweenRewards - elapsed;
    return remaining.isNegative ? Duration.zero : remaining;
  }

  /// Preload a rewarded ad (safe to call multiple times).
  Future<void> preload() async {
    if (_ad != null || _isLoading) return;
    _isLoading = true;
    _invalidated = false;

    await RewardedAd.load(
      adUnitId: _testUnitId,
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (ad) {
          _ad = ad;
          _isLoading = false;
          _wireFullScreenCallbacks(ad);
          if (kDebugMode) debugPrint('[RewardedShareAd] Loaded.');
        },
        onAdFailedToLoad: (error) {
          _isLoading = false;
          _ad = null;
          if (kDebugMode) debugPrint('[RewardedShareAd] Failed to load: $error');
        },
      ),
    );
  }

  /// Shows the ad if available. Returns true if the user earned the reward.
  Future<bool> showIfAvailable(BuildContext context) async {
    debugPrint('[RewardedShareAd] showIfAvailable()');

    final now = DateTime.now();
    if (_lastRewardTime != null &&
        now.difference(_lastRewardTime!) < _minGapBetweenRewards) {
      final rem = _minGapBetweenRewards - now.difference(_lastRewardTime!);
      if (kDebugMode) {
        debugPrint('[RewardedShareAd] Cooldown active: ${rem.inSeconds}s');
      }
      unawaited(preload());
      return false;
    }

    final ad = _ad;
    if (ad == null) {
      if (kDebugMode) {
        debugPrint('[RewardedShareAd] No ad available to show → preloading.');
      }
      unawaited(preload());
      return false;
    }

    _activeCompleter = Completer<bool>();
    _earnedThisImpression = false;

    await ad.show(onUserEarnedReward: (adWithoutView, reward) async {
      _earnedThisImpression = true;
      _lastRewardTime = DateTime.now();
      if (kDebugMode) {
        debugPrint('[RewardedShareAd] onUserEarnedReward → amount=${reward.amount} type=${reward.type}');
      }
    });

    final earned = await _activeCompleter!.future;

    _disposeCurrent(invalidate: true);
    unawaited(preload());
    if (kDebugMode) {
      debugPrint('[RewardedShareAd] Returning earned=$earned after dismiss.');
    }
    return earned;
  }

  void _wireFullScreenCallbacks(RewardedAd ad) {
    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdShowedFullScreenContent: (ad) {
        if (kDebugMode) debugPrint('[RewardedShareAd] Ad showed.');
      },
      onAdDismissedFullScreenContent: (ad) {
        if (kDebugMode) {
          debugPrint('[RewardedShareAd] Ad dismissed. earned=$_earnedThisImpression');
        }
        if (_activeCompleter != null && !_activeCompleter!.isCompleted) {
          _activeCompleter!.complete(_earnedThisImpression);
        }
        _activeCompleter = null;
        _earnedThisImpression = false;
        _disposeCurrent(invalidate: true);
      },
      onAdFailedToShowFullScreenContent: (ad, error) {
        if (kDebugMode) {
          debugPrint('[RewardedShareAd] Failed to show: $error');
        }
        if (_activeCompleter != null && !_activeCompleter!.isCompleted) {
          _activeCompleter!.complete(false);
        }
        _activeCompleter = null;
        _earnedThisImpression = false;
        _disposeCurrent(invalidate: true);
      },
      onAdImpression: (ad) {
        if (kDebugMode) debugPrint('[RewardedShareAd] Impression logged.');
      },
      onAdClicked: (ad) {
        if (kDebugMode) debugPrint('[RewardedShareAd] Clicked.');
      },
    );
  }

  void _disposeCurrent({bool invalidate = false}) {
    try {
      _ad?.dispose();
    } catch (_) {}
    _ad = null;
    if (invalidate) _invalidated = true;
  }

  Future<void> ensureWarm() async {
    if (_ad == null && !_isLoading && !_invalidated) {
      await preload();
    }
  }

  void dispose() => _disposeCurrent();
}