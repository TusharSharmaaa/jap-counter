import 'dart:async';

import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

/// Centralised audio helper used by the Timer experience.
///
/// This manager wraps a looping ambience player and a short SFX (bell) player,
/// configuring audio focus through `audio_session` and providing simple
/// convenience methods used by the UI. It does **not** keep audio playing in
/// the background – callers are expected to pause/stop on lifecycle changes.
class SoundManager {
  SoundManager._();

  static final SoundManager instance = SoundManager._();

  static const _ambienceSources = <String, String>{
    'mute': '',
    'om': 'assets/audio/om_loop.wav',
    'flute': 'assets/audio/flute_loop.mp3',
    'birds': 'assets/audio/birds_loop.mp3',
    'water': 'assets/audio/water_loop.mp3',
  };

  final AudioPlayer _ambiencePlayer = AudioPlayer();
  final AudioPlayer _sfxPlayer = AudioPlayer();
  AudioSession? _session;

  String _currentAmbience = 'mute';
  String? _loadedAmbience;
  bool _initialized = false;
  bool _ambiencePrepared = false;
  bool _ambiencePlaying = false;

  double _ambienceVolume = 0.85;
  double _bellVolume = 1.0;

  Future<void> init() async {
    if (_initialized) return;

    _session ??= await AudioSession.instance;
    final config = const AudioSessionConfiguration.music().copyWith(
      avAudioSessionCategoryOptions:
          AVAudioSessionCategoryOptions.mixWithOthers,
      avAudioSessionRouteSharingPolicy:
          AVAudioSessionRouteSharingPolicy.defaultPolicy,
      androidAudioAttributes: const AndroidAudioAttributes(
        contentType: AndroidAudioContentType.music,
        usage: AndroidAudioUsage.media,
        flags: AndroidAudioFlags.none,
      ),
      androidWillPauseWhenDucked: true,
    );
    await _session?.configure(config);

    await _ambiencePlayer.setLoopMode(LoopMode.one);
    await _ambiencePlayer.setVolume(_ambienceVolume);
    await _ambiencePlayer.setAndroidAudioAttributes(
      const AndroidAudioAttributes(
        contentType: AndroidAudioContentType.music,
        usage: AndroidAudioUsage.media,
        flags: AndroidAudioFlags.none,
      ),
    );

    await _sfxPlayer.setAndroidAudioAttributes(
      const AndroidAudioAttributes(
        contentType: AndroidAudioContentType.music,
        usage: AndroidAudioUsage.media,
        flags: AndroidAudioFlags.none,
      ),
    );
    await _sfxPlayer.setLoopMode(LoopMode.off);
    await _sfxPlayer.setVolume(_bellVolume);

    _initialized = true;
  }

  Future<void> setAmbience(String id, {bool preload = false}) async {
    await init();
    final safeId = _ambienceSources.containsKey(id) ? id : 'mute';
    _currentAmbience = safeId;
    if (preload && safeId != 'mute') {
      await _prepareAmbience(safeId);
    }
  }

  Future<void> playAmbience({String? forceId}) async {
    await init();

    final targetId = forceId ?? _currentAmbience;
    if (targetId == 'mute') {
      await stopAmbience();
      return;
    }
    final ready = await _prepareAmbience(targetId);
    if (!ready) return;

    try {
      await _session?.setActive(true);
      await _ambiencePlayer.setLoopMode(LoopMode.one);
      await _ambiencePlayer.setVolume(_ambienceVolume);
      await _ambiencePlayer.play();
      _ambiencePlaying = true;
      _currentAmbience = targetId;
    } on PlayerException catch (e, st) {
      if (kDebugMode) {
        debugPrint('[SoundManager] PlayerException while playing $targetId: ${e.message}\n$st');
      }
      _ambiencePrepared = false;
      _loadedAmbience = null;
      _ambiencePlaying = false;
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('[SoundManager] Failed to play ambience $targetId: $e\n$st');
      }
      _ambiencePrepared = false;
      _loadedAmbience = null;
      _ambiencePlaying = false;
    }
  }

  Future<void> pauseAmbience() async {
    _ambiencePlaying = false;
    if (!_ambiencePrepared) return;
    try {
      await _ambiencePlayer.pause();
      await _session?.setActive(false);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[SoundManager] Failed to pause ambience: $e');
      }
    }
  }

  Future<void> stopAmbience() async {
    _ambiencePlaying = false;
    try {
      await _ambiencePlayer.stop();
      await _session?.setActive(false);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[SoundManager] Failed to stop ambience: $e');
      }
    } finally {
      _ambiencePrepared = false;
      _loadedAmbience = null;
    }
  }

  Future<void> playBell() async {
    await init();
    try {
      await _sfxPlayer.stop();
      await _sfxPlayer.setAudioSource(
        AudioSource.asset('assets/audio/bell_end.mp3'),
      );
      await _sfxPlayer.setVolume(_bellVolume);
      await _sfxPlayer.play();
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[SoundManager] Failed to play bell: $e');
      }
    }
  }

  Future<void> dispose() async {
    try {
      await _ambiencePlayer.dispose();
    } catch (_) {}
    try {
      await _sfxPlayer.dispose();
    } catch (_) {}
    _initialized = false;
    _ambiencePrepared = false;
    _ambiencePlaying = false;
  }

  Future<void> setAmbienceVolume(double value) async {
    _ambienceVolume = value.clamp(0.0, 1.0);
    await _ambiencePlayer.setVolume(_ambienceVolume);
  }

  Future<void> setBellVolume(double value) async {
    _bellVolume = value.clamp(0.0, 1.0);
    await _sfxPlayer.setVolume(_bellVolume);
  }

  Future<bool> _prepareAmbience(String id) async {
    final asset = _ambienceSources[id];
    if (asset == null || asset.isEmpty) {
      return false;
    }
    if (_loadedAmbience == id && _ambiencePrepared) {
      return true;
    }
    try {
      await _ambiencePlayer.stop();
      await _ambiencePlayer.setAsset(asset);
      await _ambiencePlayer.setLoopMode(LoopMode.one);
      await _ambiencePlayer.setVolume(_ambienceVolume);
      _ambiencePrepared = true;
      _loadedAmbience = id;
      return true;
    } on PlayerException catch (e, st) {
      if (kDebugMode) {
        debugPrint('[SoundManager] PlayerException while preparing $id: ${e.message}\n$st');
      }
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('[SoundManager] Failed to prepare ambience $id: $e\n$st');
      }
    }
    _ambiencePrepared = false;
    _loadedAmbience = null;
    return false;
  }

  bool get isAmbiencePlaying => _ambiencePlaying;
}
