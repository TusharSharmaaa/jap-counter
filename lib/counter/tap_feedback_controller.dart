import 'dart:async' show unawaited, Timer;
import 'dart:io';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:vibration/vibration.dart';
import '../data/tap_feedback_settings.dart';

/// Centralized controller for haptic and sound feedback on tap & mala events.
/// Handles debouncing, preloading, and platform-specific implementations.
class TapFeedbackController {
  TapFeedbackController._();
  static TapFeedbackController? _instance;
  static TapFeedbackController get instance =>
      _instance ??= TapFeedbackController._();

  TapFeedbackSettings? _settings;
  AudioPlayer? _audioPlayer;
  String? _loadedSoundAsset;
  Timer? _debounceTimer;
  Timer? _soundStopTimer;
  DateTime _lastTapTime = DateTime.fromMillisecondsSinceEpoch(0);
  static const Duration _debounceDuration = Duration(milliseconds: 60);
  static const Duration _soundTrimDuration = Duration(seconds: 1);

  /// Initialize with settings and preload audio.
  Future<void> initialize(TapFeedbackSettings settings) async {
    _settings = settings;
    await _preloadAudio();
  }

  /// Update settings and reload audio if asset changed.
  Future<void> updateSettings(TapFeedbackSettings settings) async {
    final previous = _settings;
    _settings = settings;
    final assetChanged = previous?.soundAsset != settings.soundAsset;
    final modeChanged = previous?.soundMode != settings.soundMode;
    if (assetChanged || modeChanged) {
      await _preloadAudio();
    }
  }

  /// Preload audio asset for low-latency playback.
  Future<void> _preloadAudio() async {
    if (_settings == null) return;

    if (_settings!.soundMode == SoundMode.off) {
      await _disposeSoundResources();
      return;
    }

    try {
      // Use Temple Bell sound when sound mode is "everyMala"
      final asset = _settings!.soundMode == SoundMode.everyMala
          ? TapFeedbackSettings.malaBellSound
          : _settings!.soundAsset;
      
      if (kDebugMode) {
        debugPrint('[TapFeedback] Preloading sound: $asset (mode: ${_settings!.soundMode})');
      }
      
      if (_loadedSoundAsset == asset && _audioPlayer != null) {
        if (kDebugMode) {
          debugPrint('[TapFeedback] Sound already loaded: $asset');
        }
        return;
      }

      // Dispose old player if asset changed
      if (_audioPlayer != null && _loadedSoundAsset != asset) {
        await _audioPlayer!.dispose();
        _audioPlayer = null;
      }

      // Create new player if needed
      _audioPlayer ??= AudioPlayer();
      
      // Optimize for low latency
      await _audioPlayer!.setReleaseMode(ReleaseMode.stop);
      await _audioPlayer!.setPlayerMode(PlayerMode.lowLatency);
      
      // Preload the source
      await _audioPlayer!.setSource(AssetSource(asset));
      _loadedSoundAsset = asset;
      
      if (kDebugMode) {
        debugPrint('[TapFeedback] Sound preloaded successfully: $asset');
      }
    } catch (e, stackTrace) {
      if (kDebugMode) {
        debugPrint('[TapFeedback] Sound preload failed: $e\n$stackTrace');
      }
      _loadedSoundAsset = null;
    }
  }

  Future<void> _disposeSoundResources() async {
    _loadedSoundAsset = null;
    await _audioPlayer?.dispose();
    _audioPlayer = null;
  }

  /// Handle tap event with debouncing.
  /// Returns true if feedback was triggered, false if debounced.
  Future<bool> handleTap({
    required int currentCount,
    required bool isMalaComplete,
  }) async {
    final now = DateTime.now();
    final timeSinceLastTap = now.difference(_lastTapTime);

    // Debounce check
    if (timeSinceLastTap < _debounceDuration) {
      return false;
    }

    _lastTapTime = now;
    _debounceTimer?.cancel();
    _debounceTimer = Timer(_debounceDuration, () {});

    if (_settings == null) {
      await initialize(await TapFeedbackSettings.load());
    }

    final settings = _settings!;
    bool hapticTriggered = false;
    bool soundTriggered = false;

    // Check haptic feedback
    switch (settings.hapticMode) {
      case HapticMode.off:
        break;
      case HapticMode.everyTap:
        hapticTriggered = true;
        break;
      case HapticMode.everyN:
        if (currentCount > 0 && currentCount % settings.hapticN == 0) {
          hapticTriggered = true;
        }
        break;
      case HapticMode.everyMala:
        if (isMalaComplete) {
          hapticTriggered = true;
        }
        break;
    }

    // Check sound feedback
    switch (settings.soundMode) {
      case SoundMode.off:
        break;
      case SoundMode.everyTap:
        soundTriggered = true;
        break;
      case SoundMode.everyN:
        if (currentCount > 0 && currentCount % settings.soundN == 0) {
          soundTriggered = true;
        }
        break;
      case SoundMode.everyMala:
        if (isMalaComplete) {
          soundTriggered = true;
        }
        break;
    }

    // Trigger feedback
    if (hapticTriggered) {
      unawaited(_triggerHaptic());
    }
    if (soundTriggered) {
      unawaited(_triggerSound());
    }

    return hapticTriggered || soundTriggered;
  }

  /// Trigger haptic feedback with platform-specific implementation.
  Future<void> _triggerHaptic() async {
    try {
      if (Platform.isIOS) {
        // Use HapticFeedback for iOS-friendly impacts
        await HapticFeedback.lightImpact();
      } else if (Platform.isAndroid) {
        // Use vibration package for Android custom patterns
        if (await Vibration.hasVibrator() ?? false) {
          Vibration.vibrate(duration: 10);
        }
      } else {
        // Fallback for other platforms
        await HapticFeedback.lightImpact();
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[TapFeedback] Haptic failed: $e');
      }
    }
  }

  /// Trigger sound feedback using preloaded audio player.
  Future<void> _triggerSound() async {
    if (_audioPlayer == null || _loadedSoundAsset == null) {
      if (kDebugMode) {
        debugPrint('[TapFeedback] Cannot play sound: player=${_audioPlayer != null}, asset=${_loadedSoundAsset != null}');
        // Try to reload audio if not loaded
        if (_settings != null && _settings!.soundMode != SoundMode.off) {
          debugPrint('[TapFeedback] Attempting to reload audio...');
          await _preloadAudio();
          if (_audioPlayer == null || _loadedSoundAsset == null) {
            debugPrint('[TapFeedback] Still cannot play sound after reload');
            return;
          }
        } else {
          return;
        }
      } else {
        return;
      }
    }

    try {
      // Cancel any existing stop timer
      _soundStopTimer?.cancel();
      
      // Stop any currently playing sound
      await _audioPlayer!.stop();
      
      // Play the sound from the beginning
      await _audioPlayer!.play(AssetSource(_loadedSoundAsset!));
      
      if (kDebugMode) {
        debugPrint('[TapFeedback] Playing sound: $_loadedSoundAsset');
      }
    } catch (e, stackTrace) {
      if (kDebugMode) {
        debugPrint('[TapFeedback] Sound playback failed: $e\n$stackTrace');
      }
    }
  }

  /// Preview haptic feedback (for settings UI).
  Future<void> previewHaptic() async {
    await _triggerHaptic();
  }

  /// Preview sound feedback (for settings UI).
  Future<void> previewSound() async {
    if (_settings == null) {
      await initialize(await TapFeedbackSettings.load());
    }
    // Reload audio if needed (especially for everyMala mode which uses different sound)
    final expectedAsset = _settings!.soundMode == SoundMode.everyMala
        ? TapFeedbackSettings.malaBellSound
        : _settings!.soundAsset;
    if (_audioPlayer == null || _loadedSoundAsset != expectedAsset) {
      await _preloadAudio();
    }
    await _triggerSound();
  }

  /// Dispose resources.
  void dispose() {
    _debounceTimer?.cancel();
    _soundStopTimer?.cancel();
    unawaited(_disposeSoundResources());
  }
}

