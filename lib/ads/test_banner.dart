import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

class TestBanner extends StatefulWidget {
  const TestBanner({super.key});

  @override
  State<TestBanner> createState() => _TestBannerState();
}

class _TestBannerState extends State<TestBanner> {
  BannerAd? _banner;

  @override
  void initState() {
    super.initState();
    final ad = BannerAd(
      size: AdSize.banner,
      request: const AdRequest(),
      // Google **TEST** banner unit for Android:
      adUnitId: 'ca-app-pub-3940256099942544/6300978111',
      listener: BannerAdListener(
        onAdLoaded: (ad) => setState(() {}),
        onAdFailedToLoad: (ad, error) {
          ad.dispose();
          // Keep space reserved even if it fails (to protect layout)
        },
      ),
    );
    ad.load();
    _banner = ad;
  }

  @override
  void dispose() {
    _banner?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Reserve banner height to avoid layout shift
    final reservedHeight = AdSize.banner.height.toDouble();
    return SizedBox(
      height: reservedHeight,
      child: _banner == null
          ? const SizedBox.shrink()
          : AdWidget(ad: _banner!),
    );
  }
}
