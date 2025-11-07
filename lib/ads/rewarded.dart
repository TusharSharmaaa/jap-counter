import 'dart:async';
import 'package:google_mobile_ads/google_mobile_ads.dart';

class RewardedGate {
  RewardedAd? _ad;
  bool _loading = false;

  // Google TEST rewarded ad unit (Android)
  static const _testUnitId = 'ca-app-pub-3940256099942544/5224354917';

  /// Loads a rewarded ad and waits until either:
  /// - it loads, or
  /// - it fails, or
  /// - the timeout elapses.
  Future<bool> load({Duration timeout = const Duration(seconds: 5)}) async {
    if (_ad != null) return true;
    if (_loading) {
      // If already loading, just wait for it to finish or timeout.
      return _waitUntilLoaded(timeout);
    }

    _loading = true;
    final completer = Completer<bool>();

    RewardedAd.load(
      adUnitId: _testUnitId,
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (ad) {
          _ad = ad;
          _loading = false;
          if (!completer.isCompleted) completer.complete(true);
        },
        onAdFailedToLoad: (error) {
          _ad = null;
          _loading = false;
          if (!completer.isCompleted) completer.complete(false);
        },
      ),
    );

    try {
      return await completer.future.timeout(timeout, onTimeout: () {
        _loading = false;
        return false;
      });
    } catch (_) {
      _loading = false;
      return false;
    }
  }

  Future<bool> _waitUntilLoaded(Duration timeout) async {
    final started = DateTime.now();
    while (_loading) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
      if (DateTime.now().difference(started) > timeout) return false;
    }
    return _ad != null;
  }

  /// Shows the ad if ready. Returns true if the user earned a reward.
  Future<bool> showIfReady() async {
    final ad = _ad;
    if (ad == null) return false;

    bool rewarded = false;
    await ad.show(onUserEarnedReward: (_, __) {
      rewarded = true;
    });

    _ad?.dispose();
    _ad = null;
    return rewarded;
  }
}
