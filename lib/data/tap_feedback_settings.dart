import 'package:shared_preferences/shared_preferences.dart';
import '../core/prefs_manager.dart';

enum HapticMode {
  off,
  everyTap,
  everyN,
  everyMala,
}

enum SoundMode {
  off,
  everyTap,
  everyN,
  everyMala,
}

class TapFeedbackSettings {
  static const String _kHapticMode = 'tap_feedback.haptic_mode';
  static const String _kHapticN = 'tap_feedback.haptic_n';
  static const String _kSoundMode = 'tap_feedback.sound_mode';
  static const String _kSoundN = 'tap_feedback.sound_n';
  static const String _kSoundAsset = 'tap_feedback.sound_asset';

  // Defaults
  static const HapticMode defaultHapticMode = HapticMode.everyN;
  static const int defaultHapticN = 10;
  static const SoundMode defaultSoundMode = SoundMode.everyMala;
  static const int defaultSoundN = 108;
  static const String defaultSoundAsset = 'audio/bell_end.mp3';

  final HapticMode hapticMode;
  final int hapticN;
  final SoundMode soundMode;
  final int soundN;
  final String soundAsset;

  const TapFeedbackSettings({
    required this.hapticMode,
    required this.hapticN,
    required this.soundMode,
    required this.soundN,
    required this.soundAsset,
  });

  static Future<TapFeedbackSettings> load() async {
    final prefs = await PrefsManager.instance;
    return TapFeedbackSettings(
      hapticMode: HapticMode.values[
          prefs.getInt(_kHapticMode) ?? defaultHapticMode.index],
      hapticN: prefs.getInt(_kHapticN) ?? defaultHapticN,
      soundMode: SoundMode.values[
          prefs.getInt(_kSoundMode) ?? defaultSoundMode.index],
      soundN: prefs.getInt(_kSoundN) ?? defaultSoundN,
      soundAsset: prefs.getString(_kSoundAsset) ?? defaultSoundAsset,
    );
  }

  Future<void> save() async {
    final prefs = await PrefsManager.instance;
    await Future.wait([
      prefs.setInt(_kHapticMode, hapticMode.index),
      prefs.setInt(_kHapticN, hapticN),
      prefs.setInt(_kSoundMode, soundMode.index),
      prefs.setInt(_kSoundN, soundN),
      prefs.setString(_kSoundAsset, soundAsset),
    ]);
  }

  TapFeedbackSettings copyWith({
    HapticMode? hapticMode,
    int? hapticN,
    SoundMode? soundMode,
    int? soundN,
    String? soundAsset,
  }) {
    return TapFeedbackSettings(
      hapticMode: hapticMode ?? this.hapticMode,
      hapticN: hapticN ?? this.hapticN,
      soundMode: soundMode ?? this.soundMode,
      soundN: soundN ?? this.soundN,
      soundAsset: soundAsset ?? this.soundAsset,
    );
  }
}

