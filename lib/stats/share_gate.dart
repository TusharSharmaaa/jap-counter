import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import '../ads/rewarded_share.dart';
import '../widgets/ad_loading_overlay.dart';

/// Shows the rewarded ad for the "Share My Streak" flow.
/// Returns true if the user earned the reward; false otherwise.
/// On failure to load/show, it shows a gentle SnackBar asking the user to try again.
Future<bool> gateShareMyStreak(BuildContext context, {required Future<void> Function() onEarned}) async {
  showAdLoadingOverlay(context);

  await MobileAds.instance.initialize();
  final earned = await RewardedShareAd().showIfAvailable(onEarned: onEarned);

  hideAdLoadingOverlay(context);

  if (!earned && context.mounted) {
    final rs = RewardedShareAd();
    if (rs.isCoolingDown) {
      final rem = rs.cooldownRemaining ?? const Duration(seconds: 0);
      final m = rem.inMinutes;
      final s = rem.inSeconds % 60;
      final msg = m > 0
          ? 'Please wait ${m}m ${s}s before sharing again.'
          : 'Please wait ${s}s before sharing again.';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg)),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Preparing video… please try again in a moment.')),
      );
    }
  }

  return earned;
}