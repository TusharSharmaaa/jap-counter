import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

/// Shows one interstitial after a completed meditation session,
/// with a soft cooldown to avoid spamming.
class TimerInterstitialGate {
  TimerInterstitialGate._() {
    _sessionsTarget = _rollTarget();
  }

  static final TimerInterstitialGate instance = TimerInterstitialGate._();
  static const String _testUnitId = 'ca-app-pub-3940256099942544/1033173712';

  final Random _rand = Random();
  InterstitialAd? _ad;
  bool _loading = false;
  DateTime? _lastShownAt;
  static const _cooldown = Duration(minutes: 3);

  int _sessionsSinceAd = 0;
  int _sessionsTarget = 2;
  bool _readyForExit = false;

  bool get _inCooldown {
    if (_lastShownAt == null) return false;
    return DateTime.now().difference(_lastShownAt!) < _cooldown;
  }

  int _rollTarget() => 2 + _rand.nextInt(2); // 2 or 3 sessions

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

  void markMeditationComplete() {
    _sessionsSinceAd++;
    if (_sessionsSinceAd >= _sessionsTarget) {
      _readyForExit = true;
      if (kDebugMode) {
        debugPrint(
          '[TimerInterstitial] ready after $_sessionsSinceAd sessions',
        );
      }
    }
    unawaited(preload());
  }

  Future<void> maybeShowOnExit() async {
    if (!_readyForExit) return;
    if (_inCooldown) {
      if (kDebugMode) debugPrint('[TimerInterstitial] exit skipped (cooldown)');
      return;
    }

    final ad = _ad;
    if (ad == null) {
      if (kDebugMode) debugPrint('[TimerInterstitial] exit no ad → preload');
      _readyForExit = false;
      unawaited(preload());
      return;
    }

    _readyForExit = false;
    _sessionsSinceAd = 0;
    _sessionsTarget = _rollTarget();
    _lastShownAt = DateTime.now();

    await ad.show();
    unawaited(preload());
  }

  void _dispose() {
    try {
      _ad?.dispose();
    } catch (_) {}
    _ad = null;
  }
}
