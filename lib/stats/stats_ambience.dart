import 'package:audioplayers/audioplayers.dart';

class StatsAmbience {
  StatsAmbience._();

  static final StatsAmbience instance = StatsAmbience._();

  final AudioPlayer _player = AudioPlayer()..setReleaseMode(ReleaseMode.loop);
  bool _playing = false;

  Future<void> start() async {
    if (_playing) return;
    await _player.setVolume(0.25);
    await _player.play(AssetSource('audio/om_loop.wav'));
    _playing = true;
  }

  Future<void> stop() async {
    if (!_playing) return;
    await _player.stop();
    _playing = false;
  }

  bool get isPlaying => _playing;

  Future<void> dispose() async {
    await _player.dispose();
  }
}
