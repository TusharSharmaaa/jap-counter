import 'package:flutter/material.dart';

import '../ads/rewarded_share.dart';
import 'streak_share_preview.dart';

/// Unified gate that:
/// 1) shows rewarded ad
/// 2) on earned → navigates to preview
/// 3) on dismiss early → shows friendly message
/// Also logs clearly for debugging.
Future<void> openShareMyStreak(
  BuildContext context, {
  required int todayJaps,
  required int lifetimeMalas,
  required int streakDays,
}) async {
  if (!context.mounted) return;

  // DEV bypass: long-press handler in caller can skip ad and call this with earned=true.
  // Here we always try the ad.
  debugPrint('[ShareGate] Launching rewarded gate…');
  final rs = RewardedShareAd();

  // Warm ad if needed
  await rs.ensureWarm();

  // Cooldown guard: let user know and return early.
  if (rs.isCoolingDown) {
    final rem = rs.cooldownRemaining ?? const Duration(seconds: 0);
    final msg = rem.inMinutes > 0
        ? 'Please wait ${rem.inMinutes}m ${rem.inSeconds % 60}s before sharing again.'
        : 'Please wait ${rem.inSeconds % 60}s before sharing again.';
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    }
    debugPrint('[ShareGate] Cooldown active → $msg');
    return;
  }

  final earned = await rs.showIfAvailable(context);
  debugPrint('[ShareGate] Reward result: earned=$earned');
  if (!context.mounted) return;

  if (earned) {
    debugPrint('[ShareGate] Opening StreakSharePreviewPage...');
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => StreakSharePreviewPage(
          todayJaps: todayJaps,
          lifetimeMalas: lifetimeMalas,
          streakDays: streakDays,
        ),
      ),
    );
  } else {
    // Not cooling down and not earned → user likely dismissed the ad early
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Watch the full video to unlock the Share Preview.'),
        duration: Duration(seconds: 3),
      ),
    );
  }
}