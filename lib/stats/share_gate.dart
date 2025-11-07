import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import '../ads/rewarded_share.dart';

/// Shows the rewarded ad for the "Share My Streak" flow.
/// Returns true if the user earned the reward; false otherwise.
/// On failure to load/show, it shows a gentle SnackBar asking the user to try again.
Future<bool> gateShareMyStreak(BuildContext context, {required Future<void> Function() onEarned}) async {
  // Ensure MobileAds is initialized (should already be, but harmless if repeated)
  await MobileAds.instance.initialize();

  final earned = await RewardedShareAd().showIfAvailable(onEarned: onEarned);

  if (!earned && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Preparing video… please try again in a moment.')),
    );
  }

  return earned;
}