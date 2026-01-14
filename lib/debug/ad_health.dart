import 'package:flutter/foundation.dart';

typedef AdHealthSnapshotSupplier = AdHealthSnapshot Function();

class AdHealthSnapshot {
  const AdHealthSnapshot({
    required this.adMobInitialized,
    required this.consentStatus,
    required this.serveNpa,
    required this.policyLoaded,
    required this.policySource,
    required this.policyLoadError,
    required this.policyVersion,
    required this.adsEnabled,
    required this.useTestIds,
    required this.globalInterstitialConfig,
    required this.globalRewardedConfig,
    required this.rewardedReady,
    required this.interstitialReady,
    required this.preloadedRewardedCount,
    required this.preloadedInterstitialCount,
    required this.attemptLog,
  });

  final bool adMobInitialized;
  final String consentStatus;
  final bool serveNpa;
  final bool policyLoaded;
  final String? policySource;
  final String? policyLoadError;
  final String policyVersion;
  final bool adsEnabled;
  final bool useTestIds;
  final Map<String, dynamic> globalInterstitialConfig;
  final Map<String, dynamic> globalRewardedConfig;
  final bool rewardedReady;
  final bool interstitialReady;
  final int preloadedRewardedCount;
  final int preloadedInterstitialCount;
  final List<String> attemptLog;
}

class AdHealth {
  static AdHealthSnapshotSupplier? _supplier;

  static void registerSupplier(AdHealthSnapshotSupplier supplier) {
    _supplier = supplier;
  }

  static void printSnapshot({String? reason}) {
    final snapshot = _supplier?.call();
    final header = StringBuffer('[AD][HEALTH] Snapshot');
    if (reason != null && reason.isNotEmpty) {
      header.write(' ($reason)');
    }
    debugPrint(header.toString());

    if (snapshot == null) {
      debugPrint('[AD][HEALTH]   No snapshot supplier registered');
      return;
    }

    debugPrint(
      '[AD][HEALTH]   AdMob initialized: ${snapshot.adMobInitialized}',
    );
    debugPrint(
      '[AD][HEALTH]   UMP status: ${snapshot.consentStatus}${snapshot.serveNpa ? ' (serving NPA)' : ''}',
    );

    final policyStatus = snapshot.policyLoaded ? 'success' : 'fallback';
    final policyPath = snapshot.policySource ?? 'unknown';
    final policyLine = StringBuffer(
      '[AD][HEALTH]   Policy config loaded: $policyStatus (path: $policyPath, version: ${snapshot.policyVersion})',
    );
    if (snapshot.policyLoadError != null) {
      policyLine.write(' error: ${snapshot.policyLoadError}');
    }
    debugPrint(policyLine.toString());

    final interstitialCaps = _formatCaps(snapshot.globalInterstitialConfig);
    final rewardedCaps = _formatCaps(snapshot.globalRewardedConfig);
    debugPrint(
      '[AD][HEALTH]   Global caps: interstitial($interstitialCaps), rewarded($rewardedCaps)',
    );

    debugPrint('[AD][HEALTH]   Ads enabled: ${snapshot.adsEnabled}');
    debugPrint(
      '[AD][HEALTH]   Active unit mode: ${snapshot.useTestIds ? 'TEST IDs' : 'PROD IDs'}',
    );

    debugPrint(
      '[AD][HEALTH]   Preloaded: rewardedReady=${snapshot.rewardedReady} (cache=${snapshot.preloadedRewardedCount}), interstitialReady=${snapshot.interstitialReady} (cache=${snapshot.preloadedInterstitialCount})',
    );

    if (snapshot.attemptLog.isEmpty) {
      debugPrint('[AD][HEALTH]   Last show attempts: none yet');
    } else {
      debugPrint('[AD][HEALTH]   Last show attempts:');
      for (final attempt in snapshot.attemptLog) {
        debugPrint('[AD][HEALTH]     $attempt');
      }
    }
  }

  static String _formatCaps(Map<String, dynamic> config) {
    if (config.isEmpty) {
      return 'n/a';
    }
    final parts = <String>[];
    if (config.containsKey('daily_cap')) {
      parts.add('daily=${config['daily_cap']}');
    }
    if (config.containsKey('min_cooldown_seconds')) {
      parts.add('cooldown=${config['min_cooldown_seconds']}s');
    }
    if (config.containsKey('skip_if_last_interstitial_within_seconds')) {
      parts.add(
        'skipRecent=${config['skip_if_last_interstitial_within_seconds']}s',
      );
    }
    if (config.containsKey('skip_if_not_ready_after_ms')) {
      parts.add('timeout=${config['skip_if_not_ready_after_ms']}ms');
    }
    return parts.isEmpty ? 'n/a' : parts.join(', ');
  }
}




