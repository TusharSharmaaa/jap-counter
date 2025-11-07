import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

class TestNativeAd extends StatefulWidget {
  const TestNativeAd({super.key});

  @override
  State<TestNativeAd> createState() => _TestNativeAdState();
}

class _TestNativeAdState extends State<TestNativeAd> {
  NativeAd? _ad;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _ad = NativeAd(
      adUnitId: 'ca-app-pub-3940256099942544/2247696110', // ✅ Google TEST Native
      request: const AdRequest(),
      nativeTemplateStyle: NativeTemplateStyle(
        templateType: TemplateType.medium,
        mainBackgroundColor: Colors.white,
        callToActionTextStyle: NativeTemplateTextStyle(
          textColor: Colors.white,
          backgroundColor: Colors.pinkAccent,
          style: NativeTemplateFontStyle.bold,
        ),
        primaryTextStyle: NativeTemplateTextStyle(
          textColor: Colors.black,
          backgroundColor: Colors.transparent,
          style: NativeTemplateFontStyle.normal,
        ),
      ),
      listener: NativeAdListener(
        onAdLoaded: (ad) => setState(() => _loaded = true),
        onAdFailedToLoad: (ad, error) {
          ad.dispose();
          setState(() => _loaded = false);
        },
      ),
    )..load();
  }

  @override
  void dispose() {
    _ad?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 300, // enough height for medium native
      width: double.infinity,
      child: _loaded && _ad != null
          ? AdWidget(ad: _ad!)
          : const Center(child: Text("Loading native ad...")),
    );
  }
}
