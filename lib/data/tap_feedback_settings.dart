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
  static const HapticMode defaultHapticMode = HapticMode.everyMala;
  static const int defaultHapticN = 10;
  static const SoundMode defaultSoundMode = SoundMode.everyMala;
  static const int defaultSoundN = 108;
  static const String defaultSoundAsset = 'audio/bell_end.mp3';
  
  // Special sound for everyMala mode
  static const String malaBellSound = 'audio/Temple Bell.mp3';

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
    final storedHapticModeIndex = prefs.getInt(_kHapticMode);
    HapticMode hapticMode;
    
    if (storedHapticModeIndex == null) {
      // New user - use default
      hapticMode = defaultHapticMode;
    } else {
      final loadedMode = HapticMode.values[storedHapticModeIndex];
      // Migrate existing everyN users to everyMala
      if (loadedMode == HapticMode.everyN) {
        hapticMode = HapticMode.everyMala;
        // Save the migration
        await prefs.setInt(_kHapticMode, hapticMode.index);
      } else {
        hapticMode = loadedMode;
      }
    }
    
    final storedSoundModeIndex = prefs.getInt(_kSoundMode);
    SoundMode soundMode;
    
    if (storedSoundModeIndex == null) {
      // New user - use default
      soundMode = defaultSoundMode;
    } else {
      final loadedMode = SoundMode.values[storedSoundModeIndex];
      // Migrate existing everyN and everyTap users to everyMala
      if (loadedMode == SoundMode.everyN || loadedMode == SoundMode.everyTap) {
        soundMode = SoundMode.everyMala;
        // Save the migration
        await prefs.setInt(_kSoundMode, soundMode.index);
      } else {
        soundMode = loadedMode;
      }
    }
    
    // Always use bell sound, ignore stored asset if it's not bell
    final storedAsset = prefs.getString(_kSoundAsset);
    final soundAsset = (storedAsset == 'audio/bell_end.mp3') 
        ? 'audio/bell_end.mp3'
        : defaultSoundAsset;
    // Save bell sound if it wasn't already set
    if (soundAsset != storedAsset) {
      await prefs.setString(_kSoundAsset, soundAsset);
    }
    
    return TapFeedbackSettings(
      hapticMode: hapticMode,
      hapticN: prefs.getInt(_kHapticN) ?? defaultHapticN,
      soundMode: soundMode,
      soundN: prefs.getInt(_kSoundN) ?? defaultSoundN,
      soundAsset: soundAsset,
    );
  }

  Future<void> save() async {
    final prefs = await PrefsManager.instance;
    // Always ensure bell sound is saved
    final assetToSave = (soundAsset == 'audio/bell_end.mp3') 
        ? soundAsset 
        : defaultSoundAsset;
    await Future.wait([
      prefs.setInt(_kHapticMode, hapticMode.index),
      prefs.setInt(_kHapticN, hapticN),
      prefs.setInt(_kSoundMode, soundMode.index),
      prefs.setInt(_kSoundN, soundN),
      prefs.setString(_kSoundAsset, assetToSave),
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

