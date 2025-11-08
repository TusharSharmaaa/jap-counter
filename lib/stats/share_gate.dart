import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'dart:async' show unawaited;

import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../ads/rewarded_share.dart';
import '../widgets/ad_loading_overlay.dart';
import 'streak_share_preview.dart';

/// Shows the rewarded ad for the "Share My Streak" flow.
/// Returns true if the user earned the reward; false otherwise.
/// Caller must pass today's stats so we can build the preview immediately after the ad.
Future<bool> gateShareMyStreak(
    BuildContext context, {
      required Future<void> Function() onEarned,
      required int todayJaps,
      required int lifetimeMalas,
      required int streakDays,
    }) async {
  showAdLoadingOverlay(context);
  bool earned = false;

  try {
    // Ensure the ads SDK is ready (safe to call multiple times).
    await MobileAds.instance.initialize();

    earned = await RewardedShareAd.instance.showIfAvailable(context);
    if (kDebugMode) {
      debugPrint('[ShareGate] Reward result → earned=$earned');
    }

    if (earned) {
      if (kDebugMode) {
        debugPrint('[ShareGate] earned=true → invoking onEarned() and opening preview');
      }
      // Allow caller to record any side-effects (analytics, state writes, etc.)
      await onEarned();

      // Navigate to the preview card with all the required data.
      if (context.mounted) {
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => StreakSharePreviewPage(
              todayJaps: todayJaps,
              lifetimeMalas: lifetimeMalas,
              streakDays: streakDays,
            ),
          ),
        );
      }
    } else {
      if (kDebugMode) debugPrint('[ShareGate] earned=false (no nav)');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Watch the full video to unlock the Share Preview.'),
            duration: Duration(seconds: 3),
          ),
        );
      }
    }

    // If not earned, provide precise cooldown feedback when applicable.
    if (!earned && context.mounted) {
      final rs = RewardedShareAd.instance;
      if (rs.isCoolingDown) {
        final rem = rs.cooldownRemaining ?? const Duration(seconds: 0);
        final m = rem.inMinutes;
        final s = rem.inSeconds % 60;
        final msg =
        m > 0 ? 'Please wait ${m}m ${s}s before sharing again.' : 'Please wait ${s}s before sharing again.';
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      }
    }

    return earned;
  } finally {
    // Always remove the loading overlay, even if something failed.
    hideAdLoadingOverlay(context);
  }
}