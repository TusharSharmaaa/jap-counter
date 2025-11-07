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

  static const String _testUnitId = 'ca-app-pub-3940256099942544/5224354917';

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
          if (kDebugMode) {
            debugPrint('[RewardedShareAd] Loaded.');
          }
        },
        onAdFailedToLoad: (error) {
          _isLoading = false;
          _ad = null;
          if (kDebugMode) {
            debugPrint('[RewardedShareAd] Failed to load: $error');
          }
        },
      ),
    );
  }

  /// Shows the ad if available. Returns true if the user earned the reward.
  /// If no ad is available, returns false and does NOT call [onEarned].
  Future<bool> showIfAvailable({required Future<void> Function() onEarned}) async {
    // Cooldown: avoid showing too frequently
    final now = DateTime.now();
    if (_lastRewardTime != null && now.difference(_lastRewardTime!) < _minGapBetweenRewards) {
      if (kDebugMode) {
        debugPrint('[RewardedShareAd] Cooldown active. Try again later.');
      }
      // Ensure a future ad is ready
      unawaited(preload());
      return false;
    }
    final ad = _ad;
    if (ad == null) {
      // Try to kick off a background load for next time.
      unawaited(preload());
      if (kDebugMode) {
        debugPrint('[RewardedShareAd] No ad available to show.');
      }
      return false;
    }

    var earned = false;
    await ad.show(onUserEarnedReward: (adWithoutView, reward) async {
      earned = true;
      if (kDebugMode) {
        debugPrint('[RewardedShareAd] Reward earned: ${reward.amount} ${reward.type}');
      }
      _lastRewardTime = DateTime.now();
      await onEarned();
    });

    // After show, the ad cannot be reused; clear and request next.
    _disposeCurrent(invalidate: true);
    // Fire and forget next preload.
    unawaited(preload());

    return earned;
  }

  void _wireFullScreenCallbacks(RewardedAd ad) {
    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdShowedFullScreenContent: (ad) {
        if (kDebugMode) debugPrint('[RewardedShareAd] Ad showed.');
      },
      onAdDismissedFullScreenContent: (ad) {
        if (kDebugMode) debugPrint('[RewardedShareAd] Ad dismissed.');
        _disposeCurrent(invalidate: true);
      },
      onAdFailedToShowFullScreenContent: (ad, error) {
        if (kDebugMode) debugPrint('[RewardedShareAd] Failed to show: $error');
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

  /// For lifecycle owners (optional): call on app resume to ensure an ad is queued.
  Future<void> ensureWarm() async {
    if (_ad == null && !_isLoading && !_invalidated) {
      await preload();
    }
  }

  /// Manual dispose (usually not needed).
  void dispose() {
    _disposeCurrent();
  }
}