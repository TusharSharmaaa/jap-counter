import 'dart:async';

import 'package:flutter/foundation.dart';
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

  final adShown = await _showShareRewardedWithRetry('stats.share_rewarded');

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

  if (!adShown) {
    unawaited(
      AdManager.instance.preloadPlacement('stats.share_rewarded', force: true),
    );
  }
}

Future<bool> _showShareRewardedWithRetry(String placementId) async {
  bool adShown = false;

  try {
    adShown = await AdManager.instance.maybeShowRewarded(
      placementId,
      timeout: const Duration(seconds: 8),
    );

    if (!adShown) {
      if (kDebugMode) {
        debugPrint('[ShareGate] $placementId not ready, forcing preload');
      }
      await AdManager.instance.preloadPlacement(placementId, force: true);
      adShown = await AdManager.instance.maybeShowRewarded(
        placementId,
        timeout: const Duration(seconds: 10),
      );
    }
  } catch (error, stackTrace) {
    if (kDebugMode) {
      debugPrint('[ShareGate] rewarded attempt failed: $error\n$stackTrace');
    }
  }

  unawaited(
    AdManager.instance.recordEvent(
      placementId,
      'attempt',
      data: {'ad_shown': adShown},
    ),
  );

  return adShown;
}
