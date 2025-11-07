import 'package:google_mobile_ads/google_mobile_ads.dart';

/// Shows a single interstitial per app session after a meditation completes.
/// Uses Google's TEST interstitial ID during development.
class TimerInterstitialGate {
  TimerInterstitialGate._();
  static final TimerInterstitialGate instance = TimerInterstitialGate._();

  InterstitialAd? _ad;
  bool _shownThisSession = false;

  static const String _testInterstitialId =
      'ca-app-pub-3940256099942544/1033173712'; // test ID
  static const String _adUnitId = _testInterstitialId;

  /// Preload if we don't already have one and haven't shown this session.
  Future<void> preload() async {
    if (_shownThisSession) return;
    if (_ad != null) return;

    await InterstitialAd.load(
      adUnitId: _adUnitId,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) {
          _ad = ad;
        },
        onAdFailedToLoad: (err) {
          _ad = null;
        },
      ),
    );
  }

  /// Show if ready and not already shown this session.
  Future<void> maybeShow() async {
    if (_shownThisSession) return;
    final ad = _ad;
    if (ad == null) return;

    _ad = null; // consume it
    _shownThisSession = true;

    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
      },
      onAdFailedToShowFullScreenContent: (ad, err) {
        ad.dispose();
      },
    );

    await ad.show();
  }

  /// (Optional for dev/testing) Call this to allow another show in same session.
  void resetForTesting() {
    _shownThisSession = false;
  }
}
