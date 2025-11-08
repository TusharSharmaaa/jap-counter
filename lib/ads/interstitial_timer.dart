import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

/// Shows one interstitial after a completed meditation session,
/// with a soft cooldown to avoid spamming.
class TimerInterstitialGate {
  TimerInterstitialGate._();

  static final TimerInterstitialGate instance = TimerInterstitialGate._();
  static const String _testUnitId = 'ca-app-pub-3940256099942544/1033173712';

  InterstitialAd? _ad;
  bool _loading = false;
  bool _shownThisSession = false;
  DateTime? _lastShownAt;
  static const _cooldown = Duration(minutes: 3);

  bool get _inCooldown {
    if (_lastShownAt == null) return false;
    return DateTime.now().difference(_lastShownAt!) < _cooldown;
  }

  Future<void> preload() async {
    if (_ad != null || _loading) return;
    _loading = true;

    await InterstitialAd.load(
      adUnitId: _testUnitId,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) {
          _ad = ad;
          _loading = false;
          ad.fullScreenContentCallback = FullScreenContentCallback(
            onAdShowedFullScreenContent: (ad) {
              if (kDebugMode) debugPrint('[TimerInterstitial] shown');
            },
            onAdDismissedFullScreenContent: (ad) {
              if (kDebugMode) debugPrint('[TimerInterstitial] dismissed');
              _dispose();
            },
            onAdFailedToShowFullScreenContent: (ad, err) {
              if (kDebugMode) debugPrint('[TimerInterstitial] failed: $err');
              _dispose();
            },
          );
          if (kDebugMode) debugPrint('[TimerInterstitial] loaded');
        },
        onAdFailedToLoad: (err) {
          _loading = false;
          _ad = null;
          if (kDebugMode) debugPrint('[TimerInterstitial] load failed: $err');
        },
      ),
    );
  }

  Future<void> maybeShow() async {
    if (_shownThisSession || _inCooldown) {
      if (kDebugMode) debugPrint('[TimerInterstitial] skip (session or cooldown)');
      return;
    }

    final ad = _ad;
    if (ad == null) {
      if (kDebugMode) debugPrint('[TimerInterstitial] no ad → preload');
      unawaited(preload());
      return;
    }

    _shownThisSession = true;
    _lastShownAt = DateTime.now();

    await ad.show();

    unawaited(preload());
  }

  void resetSession() {
    _shownThisSession = false;
  }

  void _dispose() {
    try {
      _ad?.dispose();
    } catch (_) {}
    _ad = null;
  }
}
