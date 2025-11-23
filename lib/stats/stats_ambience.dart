import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

class StatsAmbience {
  StatsAmbience._();

  static final StatsAmbience instance = StatsAmbience._();

  final AudioPlayer _player = AudioPlayer()..setReleaseMode(ReleaseMode.loop);
  bool _playing = false;
  bool _disposed = false;

  Future<void> start() async {
    if (_playing || _disposed) return;
    try {
      await _player.setVolume(0.25);
      await _player.play(AssetSource('audio/om_loop.wav'));
      _playing = true;
    } catch (e, stackTrace) {
      // Handle audio errors gracefully
      _playing = false;
      if (kDebugMode) {
        debugPrint('[StatsAmbience] Error starting audio: $e\n$stackTrace');
      }
    }
  }

  Future<void> stop() async {
    if (!_playing || _disposed) return;
    try {
      await _player.stop();
      _playing = false;
    } catch (e, stackTrace) {
      // Handle stop errors gracefully
      _playing = false;
      if (kDebugMode) {
        debugPrint('[StatsAmbience] Error stopping audio: $e\n$stackTrace');
      }
    }
  }

  bool get isPlaying => _playing;

  /// Dispose the audio player and clean up resources.
  /// Should be called when the app is closing or the stats page is disposed.
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    try {
      await stop();
      await _player.dispose();
    } catch (e, stackTrace) {
      if (kDebugMode) {
        debugPrint('[StatsAmbience] Error disposing: $e\n$stackTrace');
      }
    }
  }
}
