import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:jap_counter/core/ad_manager.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Map<String, dynamic> policy;

  setUpAll(() async {
    final policyJson = await File(
      'assets/config/ad_policy.json',
    ).readAsString();
    policy = json.decode(policyJson) as Map<String, dynamic>;
  });

  Future<void> resetManager() async {
    SharedPreferences.setMockInitialValues({});
    await AdManager.instance.debugConfigureForTests(policy);
    await AdManager.instance.debugResetStorage();
  }

  Future<void> advanceRewardedCooldown() async {
    final prefs = await SharedPreferences.getInstance();
    final past = DateTime.now()
        .subtract(const Duration(hours: 3))
        .millisecondsSinceEpoch;
    await prefs.setInt('ad.rewarded.lastShown', past);
    await prefs.setInt('ad.rewarded.stats.share_rewarded.lastShown', past);
  }

  Future<void> advanceInterstitialCooldown() async {
    final past = DateTime.now().subtract(const Duration(minutes: 15));
    await AdManager.instance.debugSetLastInterstitialShown(past);
    await AdManager.instance.debugSetPlacementLastShown(
      'interstitial',
      'gita.long_session_interstitial',
      past,
    );
    await AdManager.instance.debugSetPlacementLastShown(
      'interstitial',
      'timer.post_session_interstitial',
      past,
    );
  }

  test('Stats rewarded respects placement caps and cooldowns', () async {
    await resetManager();
    AdManager.instance.debugSetTestMode(enabled: true, rewardedOutcome: true);

    // First three attempts succeed (placement cap = 3)
    for (var i = 0; i < 3; i++) {
      final shown = await AdManager.instance.maybeShowRewarded(
        'stats.share_rewarded',
      );
      expect(shown, isTrue);
      await advanceRewardedCooldown();
    }

    // Fourth attempt blocked by placement daily cap
    final fourth = await AdManager.instance.maybeShowRewarded(
      'stats.share_rewarded',
    );
    expect(fourth, isFalse);
  });

  test('Gita interstitial only after long session criteria met', () async {
    await resetManager();
    AdManager.instance.debugSetTestMode(
      enabled: true,
      interstitialOutcome: true,
    );

    // Not enough progress yet.
    AdManager.instance.debugSetGitaSession(start: DateTime.now(), shlokas: 2);
    final earlyAttempt = await AdManager.instance.maybeShowInterstitial(
      'gita.long_session_interstitial',
    );
    expect(earlyAttempt, isFalse);

    // Meets time + shloka thresholds
    AdManager.instance.debugSetGitaSession(
      start: DateTime.now().subtract(const Duration(minutes: 6)),
      shlokas: 10,
    );
    await advanceInterstitialCooldown();
    final qualified = await AdManager.instance.maybeShowInterstitial(
      'gita.long_session_interstitial',
    );
    expect(qualified, isTrue);
  });

  test('Timer interstitial follows every-session policy with caps', () async {
    await resetManager();
    AdManager.instance.debugSetTestMode(
      enabled: true,
      interstitialOutcome: true,
    );

    Future<bool> completeAndShow(double minutes) async {
      await AdManager.instance.recordEvent(
        'timer.session',
        'complete',
        data: {'minutes': minutes},
      );
      final shown = await AdManager.instance.maybeShowInterstitial(
        'timer.post_session_interstitial',
        timeout: const Duration(milliseconds: 1500),
      );
      return shown;
    }

    final first = await completeAndShow(10);
    expect(first, isTrue);
    await advanceInterstitialCooldown();

    final second = await completeAndShow(2);
    expect(second, isTrue);
    await advanceInterstitialCooldown();

    final third = await completeAndShow(5);
    expect(third, isTrue);
    await advanceInterstitialCooldown();

    final fourth = await completeAndShow(15);
    expect(fourth, isFalse);
  });
}
