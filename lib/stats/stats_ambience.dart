import 'package:audioplayers/audioplayers.dart';

class StatsAmbience {
  StatsAmbience._();

  static final StatsAmbience instance = StatsAmbience._();

  final AudioPlayer _player = AudioPlayer()..setReleaseMode(ReleaseMode.loop);
  bool _playing = false;

  Future<void> start() async {
    if (_playing) return;
    try {
      await _player.setVolume(0.25);
      await _player.play(AssetSource('audio/om_loop.wav'));
      _playing = true;
    } catch (e) {
      // Handle audio errors gracefully
      _playing = false;
      // Could log error in debug mode
    }
  }

  Future<void> stop() async {
    if (!_playing) return;
    try {
      await _player.stop();
      _playing = false;
    } catch (e) {
      // Handle stop errors gracefully
      _playing = false;
    }
  }

  bool get isPlaying => _playing;

  Future<void> dispose() async {
    await _player.dispose();
  }
}
