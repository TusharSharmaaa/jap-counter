import 'package:flutter/foundation.dart';

import '../core/ad_manager.dart';

class BootHealth {
  static void printSnapshot({
    String? reason,
    bool? adsInitialized,
    String? umpStatus,
    bool? policyLoaded,
    List<String>? notes,
  }) {
    final header = StringBuffer('[BOOT][HEALTH] Snapshot');
    if (reason != null && reason.isNotEmpty) {
      header.write(' ($reason)');
    }
    debugPrint(header.toString());

    final adManager = AdManager.instance;
    final resolvedPolicyLoaded = policyLoaded ?? adManager.policyLoaded;
    final policyStatus = resolvedPolicyLoaded ? 'OK' : 'FAIL';
    final policySource = adManager.policySource ?? 'unknown';
    final policyError = adManager.policyLoadError;
    final policyLine = StringBuffer(
      '[BOOT][HEALTH]   ad policy load: $policyStatus (source: $policySource',
    );
    if (policyError != null) {
      policyLine.write(', error: $policyError');
    }
    policyLine.write(')');
    debugPrint(policyLine.toString());

    final resolvedNotes = notes ?? const <String>[];
    final admobStatus = _resolveAdMobStatus(
      adsInitialized ?? adManager.isAdMobInitialized,
      resolvedNotes,
    );
    debugPrint('[BOOT][HEALTH]   AdMob init: $admobStatus');

    final resolvedUmp = (umpStatus ?? adManager.consentStatusLabel).isEmpty
        ? 'unknown'
        : (umpStatus ?? adManager.consentStatusLabel);
    debugPrint('[BOOT][HEALTH]   UMP: $resolvedUmp');

    debugPrint(
      '[BOOT][HEALTH]   Preloads ready: rewarded=${adManager.rewardedReady}, interstitial=${adManager.interstitialReady}',
    );

    if (resolvedNotes.isNotEmpty) {
      debugPrint('[BOOT][HEALTH]   Notes:');
      for (final note in resolvedNotes) {
        debugPrint('[BOOT][HEALTH]     $note');
      }
    }
  }

  static String _resolveAdMobStatus(
    bool adsInitialized,
    List<String> notes,
  ) {
    if (adsInitialized) return 'OK';
    final lowerNotes = notes.map((note) => note.toLowerCase()).toList();
    final hasTimeout =
        lowerNotes.any((note) => note.contains('admob') && note.contains('timeout'));
    if (hasTimeout) return 'TIMEOUT';
    final hasError =
        lowerNotes.any((note) => note.contains('admob') && note.contains('error'));
    if (hasError) return 'ERROR';
    return 'FAIL';
  }
}

