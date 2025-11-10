import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/ad_manager.dart';
import '../debug/boot_health.dart';

const _logTag = '[BOOTSTRAP]';

class AppBootstrapResult {
  AppBootstrapResult({
    this.adsInitialized = false,
    this.umpStatus = 'unknown',
    this.policyLoaded = false,
    List<String>? notes,
  }) : notes = notes ?? <String>[];

  bool adsInitialized;
  String umpStatus;
  bool policyLoaded;
  final List<String> notes;

  @override
  String toString() => 'AppBootstrapResult('
      'adsInitialized=$adsInitialized, '
      'umpStatus=$umpStatus, '
      'policyLoaded=$policyLoaded, '
      'notes=${notes.join('; ')})';
}

class AppBootstrapper {
  AppBootstrapper({
    Duration stepTimeout = const Duration(seconds: 2),
    List<String> testDeviceIds = const <String>['TEST_DEVICE_ID'],
  })  : _stepTimeout = stepTimeout,
        _testDeviceIds = List<String>.unmodifiable(testDeviceIds);

  final Duration _stepTimeout;
  final List<String> _testDeviceIds;
  final AdManager _adManager = AdManager.instance;

  Future<AppBootstrapResult> run() async {
    final result = AppBootstrapResult();
    final bootstrapCompleter = Completer<void>();
    _adManager.adoptBootstrapFuture(bootstrapCompleter.future);

    void log(String message) {
      debugPrint('$_logTag $message');
    }

    Future<bool> runStep(
      String name,
      Future<bool> Function() action, {
      Duration? timeout,
    }) async {
      final effectiveTimeout = timeout ?? _stepTimeout;
      log('step:$name start (timeout=${effectiveTimeout.inMilliseconds}ms)');
      try {
        final ok = await action().timeout(effectiveTimeout);
        if (ok) {
          log('step:$name ok');
        } else {
          log('step:$name returned false');
          result.notes.add('$name returned false');
        }
        return ok;
      } on TimeoutException {
        log('step:$name timeout after ${effectiveTimeout.inMilliseconds}ms');
        result.notes.add('$name timeout');
        return false;
      } catch (error, stackTrace) {
        log('step:$name error → $error');
        debugPrint('$_logTag $name stackTrace → $stackTrace');
        result.notes.add('$name error: $error');
        return false;
      }
    }

    try {
      log('run start');

      await runStep('shared_prefs', () async {
        await SharedPreferences.getInstance();
        return true;
      });

      await runStep('policy_load', () async {
        await _adManager.loadPolicyFromAsset(
          AdManager.defaultPolicyAssetPath,
        );
        return true;
      });
      result.policyLoaded = _adManager.policyLoaded;
      if (!result.policyLoaded) {
        final error = _adManager.policyLoadError;
        final source = _adManager.policySource ?? 'unknown';
        result.notes.add(
          'policy fallback (source=$source, error=${error ?? 'unknown'})',
        );
      }

      final adsOk = await runStep('admob_init', () async {
        return await _adManager.initAdMob(testDeviceIds: _testDeviceIds);
      });
      result.adsInitialized = adsOk && _adManager.isAdMobInitialized;
      if (!result.adsInitialized) {
        result.notes.add('admob init incomplete');
      }

      final consentConfig =
          (_adManager.globalConfig['consent'] as Map?)?.cast<String, dynamic>() ??
              const <String, dynamic>{};
      final useUmp = consentConfig['use_ump'] == true;

      if (useUmp) {
        final consentOk = await runStep('ump_consent', () async {
          return await _adManager.initConsent();
        });
        result.umpStatus = _adManager.consentStatusLabel;
        if (!consentOk) {
          result.notes.add('UMP consent failed, serving NPA');
          if (result.umpStatus == 'unknown') {
            result.umpStatus = 'timeout';
          }
        }
      } else {
        result.umpStatus = _adManager.consentStatusLabel;
        result.notes.add('UMP disabled by policy');
        log('Consent flow skipped (use_ump=false). Status=${result.umpStatus}');
      }

      await runStep('preload_ads', () async {
        final ok = await _adManager.preloadAll(
          force: true,
          ensureReady: false,
        );
        if (!ok) {
          result.notes.add('preload incomplete');
        }
        return ok;
      });

      BootHealth.printSnapshot(
        reason: 'AppBootstrapper.run',
        adsInitialized: result.adsInitialized,
        umpStatus: result.umpStatus,
        policyLoaded: result.policyLoaded,
        notes: result.notes,
      );
      log('run complete → $result');
    } finally {
      if (!bootstrapCompleter.isCompleted) {
        bootstrapCompleter.complete();
      }
    }
    return result;
  }
}

