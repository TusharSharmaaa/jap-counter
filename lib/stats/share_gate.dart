import 'package:flutter/material.dart';

import '../core/ad_manager.dart';
import 'streak_share_preview.dart';

Future<void> openShareMyStreak(
  BuildContext context, {
  required int todayJaps,
  required int lifetimeMalas,
  required int streakDays,
}) async {
  if (!context.mounted) return;

  final adShown = await AdManager.instance.showRewardedAd(
    'stats.share_rewarded',
    timeout: const Duration(seconds: 8),
  );
  AdManager.instance.recordEvent(
    'stats.share_rewarded',
    'attempt',
    data: {'ad_shown': adShown},
  );

  if (!context.mounted) return;

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
