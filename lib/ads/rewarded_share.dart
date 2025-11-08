import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:flutter/foundation.dart';
import 'dart:async' show unawaited;

/// Rewarded ad used to gate the "Share My Streak" action on the Stats tab.
/// Test unit ID from Google: https://developers.google.com/admob/flutter/test-ads
/// Android Rewarded (TEST): ca-app-pub-3940256099942544/5224354917
class RewardedShareAd {
  RewardedAd? _ad;
  bool _isLoading = false;
  bool _invalidated = false;
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
    debugPrint('[RewardedShare] showIfAvailable() called');

    final now = DateTime.now();
    if (_lastRewardTime != null &&
        now.difference(_lastRewardTime!) < _minGapBetweenRewards) {
      final rem = _minGapBetweenRewards - now.difference(_lastRewardTime!);
      debugPrint('[RewardedShareAd] Cooldown active: ${rem.inSeconds}s remaining.');
      unawaited(preload());
      return false;
    }

    final ad = _ad;
    if (ad == null) {
      debugPrint('[RewardedShareAd] No ad available to show.');
      unawaited(preload());
      return false;
    }

    var earned = false;

    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdShowedFullScreenContent: (ad) =>
          debugPrint('[RewardedShareAd] Ad shown'),
      onAdDismissedFullScreenContent: (ad) {
        debugPrint('[RewardedShareAd] Ad dismissed (earned=$earned)');
        _disposeCurrent(invalidate: true);
        Navigator.of(context).pop(earned); // pass result to caller
      },
      onAdFailedToShowFullScreenContent: (ad, error) {
        debugPrint('[RewardedShareAd] Failed to show: $error');
        _disposeCurrent(invalidate: true);
        Navigator.of(context).pop(false);
      },
    );

    await ad.show(onUserEarnedReward: (adWithoutView, reward) async {
      earned = true;
      _lastRewardTime = DateTime.now();
      debugPrint('[RewardedShareAd] onUserEarnedReward fired! → ${reward.type}');
    });

    debugPrint('[RewardedShareAd] ad.show() finished, earned=$earned');
    _disposeCurrent(invalidate: true);
    unawaited(preload());
    return earned;
  }

  void _wireFullScreenCallbacks(RewardedAd ad) {
    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdShowedFullScreenContent: (ad) =>
          debugPrint('[RewardedShareAd] Ad showed.'),
      onAdDismissedFullScreenContent: (ad) {
        debugPrint('[RewardedShareAd] Ad dismissed.');
        _disposeCurrent(invalidate: true);
      },
      onAdFailedToShowFullScreenContent: (ad, error) {
        debugPrint('[RewardedShareAd] Failed to show: $error');
        _disposeCurrent(invalidate: true);
      },
      onAdImpression: (ad) =>
          debugPrint('[RewardedShareAd] Impression logged.'),
      onAdClicked: (ad) => debugPrint('[RewardedShareAd] Clicked.'),
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