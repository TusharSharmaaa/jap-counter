import 'package:audioplayers/audioplayers.dart';
import 'timer_sound_controller.dart';

enum TimerSoundType { mute, om, birds, water, flute, bell }

String _assetFor(TimerSoundType t) {
  switch (t) {
    case TimerSoundType.om:
      return 'assets/sounds/om.wav'; // <-- WAV file
    case TimerSoundType.birds:
      return 'assets/sounds/birds.mp3';
    case TimerSoundType.water:
      return 'assets/sounds/water.mp3';
    case TimerSoundType.flute:
      return 'assets/sounds/flute.mp3';
    case TimerSoundType.bell:
      return 'assets/sounds/bell.mp3';
    case TimerSoundType.mute:
    default:
      return '';
  }
}

class TimerSoundController {
  final AudioPlayer _player = AudioPlayer();
  TimerSoundType _current = TimerSoundType.mute;

  TimerSoundController() {
    _player.setReleaseMode(ReleaseMode.loop); // seamless loop
  }

  /// Change the selected ambience (doesn't auto-play).
  Future<void> setSound(TimerSoundType t) async {
    _current = t;
    if (_current == TimerSoundType.mute) {
      await _player.stop();
      return;
    }
    // Preload source for instant start later
    final asset = _assetFor(_current);
    if (asset.isEmpty) return;
    await _player.setSource(AssetSource(asset.replaceFirst('assets/', '')));
    // Note: setSource with AssetSource expects path relative to /assets
  }

  /// Start or restart playback of the selected ambience.
  Future<void> start() async {
    if (_current == TimerSoundType.mute) return;
    final asset = _assetFor(_current);
    if (asset.isEmpty) return;
    await _player.play(AssetSource(asset.replaceFirst('assets/', '')));
  }

  Future<void> pause() async {
    await _player.pause();
  }

  Future<void> resume() async {
    if (_current == TimerSoundType.mute) return;
    await _player.resume();
  }

  Future<void> stop() async {
    await _player.stop();
  }

  Future<void> dispose() async {
    await _player.stop();
    await _player.release();
    await _player.dispose();
  }
}
