import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:share_plus/share_plus.dart';

import '../core/prefs_manager.dart';
import '../notifications/notification_service.dart';
import '../data/language_store.dart';
import '../legal/privacy_policy.dart';
import '../legal/terms_conditions.dart';
import 'about_page.dart';
import '../ui/glow_card.dart';
import '../l10n/app_localizations.dart';
import '../data/tap_feedback_settings.dart';
import '../counter/tap_feedback_controller.dart';
import '../theme/design_system.dart';
import '../widgets/widgets.dart';

class SettingsPage extends StatefulWidget {
  final ThemeMode themeMode;
  final ValueChanged<ThemeMode> onThemeModeChanged;
  final String language;
  final ValueChanged<String> onLanguageChanged;

  const SettingsPage({
    super.key,
    required this.themeMode,
    required this.onThemeModeChanged,
    required this.language,
    required this.onLanguageChanged,
  });

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool _reminders = false;
  bool _remindersLocked = false;
  TapFeedbackSettings? _feedbackSettings;

  static const _keyReminders = 'notificationsEnabled';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await PrefsManager.instance;
    final ns = NotificationService();
    await ns.init();
    final allowed = await ns.areNotificationsAllowed();
    final storedReminders = prefs.getBool(_keyReminders) ?? true;
    final shouldEnable = allowed || storedReminders;
    if (allowed && shouldEnable) {
      final language = await LanguageStore.current();
      await ns.scheduleDefaults(language: language);
    }
    final feedbackSettings = await TapFeedbackSettings.load();
    if (!mounted) return;
    setState(() {
      _remindersLocked = allowed;
      _reminders = shouldEnable;
      _feedbackSettings = feedbackSettings;
    });
  }

  Future<void> _toggleReminders(bool value) async {
    if (_remindersLocked && !value) {
      HapticFeedback.selectionClick();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.tr('settings.notifications.locked'))),
      );
      return;
    }
    HapticFeedback.lightImpact();
    setState(() => _reminders = value);
    final prefs = await PrefsManager.instance;
    await prefs.setBool(_keyReminders, value);

    final ns = NotificationService();
    if (value) {
      await ns.init();
      final allowed = await ns.requestPermission();
      if (allowed) {
        final language = await LanguageStore.current();
        await ns.scheduleDefaults(language: language);
      }
      if (!allowed) {
        setState(() => _reminders = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.tr('settings.notifications.denied'))),
        );
      }
    } else {
      final plugin = FlutterLocalNotificationsPlugin();
      await plugin.cancelAll();
    }
  }

  Future<void> _updateFeedbackSettings(TapFeedbackSettings settings) async {
    HapticFeedback.lightImpact();
    setState(() => _feedbackSettings = settings);
    await settings.save();
    await TapFeedbackController.instance.updateSettings(settings);
  }

  Future<void> _shareApp() async {
    HapticFeedback.selectionClick();
    const pkg = 'com.example.jap_counter';
    final link = 'https://play.google.com/store/apps/details?id=$pkg';
    await SharePlus.instance.share(
      ShareParams(text: link, subject: 'Naam Jap Counter : Sadhna'),
    );
  }

  Future<void> _rateOnPlayStore() async {
    HapticFeedback.selectionClick();
    const pkg = 'com.example.jap_counter';
    final marketUri = Uri.parse('market://details?id=$pkg');
    final webUri = Uri.parse(
      'https://play.google.com/store/apps/details?id=$pkg',
    );
    if (await canLaunchUrl(marketUri)) {
      await launchUrl(marketUri);
    } else {
      await launchUrl(webUri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = widget.themeMode == ThemeMode.dark;
    final language = widget.language;

    return Scaffold(
      backgroundColor: DesignSystem.backgroundLight,
      appBar: AppBar(
        title: Text(context.tr('settings.title')),
        backgroundColor: Colors.transparent,
        elevation: 0,
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            color: DesignSystem.backgroundLight,
          ),
        ),
      ),
      body: Container(
        decoration: const BoxDecoration(
          color: DesignSystem.backgroundLight,
        ),
        child: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isNarrow = constraints.maxWidth < 360;
            final padding = isNarrow ? 12.0 : 16.0;
            
            return ListView(
              padding: EdgeInsets.fromLTRB(
                padding,
                padding,
                padding,
                MediaQuery.of(context).padding.bottom + 32,
              ),
          children: [
            _SettingsSection(
              icon: Icons.dark_mode,
              title: context.tr('settings.theme'),
              children: [
                Center(
                  child: SegmentedButton<bool>(
                    segments: [
                      ButtonSegment(
                        value: false,
                        label: Text(context.tr('common.light')),
                        icon: const Icon(Icons.wb_sunny),
                      ),
                      ButtonSegment(
                        value: true,
                        label: Text(context.tr('common.dark')),
                        icon: const Icon(Icons.dark_mode),
                      ),
                    ],
                    selected: {isDark},
                    onSelectionChanged: (selection) {
                      final dark = selection.first;
                      HapticFeedback.selectionClick();
                      widget.onThemeModeChanged(
                        dark ? ThemeMode.dark : ThemeMode.light,
                      );
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _SettingsSection(
              icon: Icons.language,
              title: context.tr('settings.language'),
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Text(
                      context.tr('settings.language.subtitle'),
                      style: Theme.of(context).textTheme.bodySmall,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    Center(
                      child: SegmentedButton<String>(
                        segments: [
                          ButtonSegment(
                            value: 'en',
                            label: Text(context.tr('common.english')),
                          ),
                          ButtonSegment(
                            value: 'hi',
                            label: Text(context.tr('common.hindi')),
                          ),
                        ],
                        selected: {widget.language},
                        onSelectionChanged: (selection) {
                          final value = selection.first;
                          HapticFeedback.selectionClick();
                          widget.onLanguageChanged(value);
                        },
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (_feedbackSettings != null) ...[
              _SettingsSection(
                icon: Icons.vibration,
                title: context.tr('settings.haptic.title'),
                children: [
                  _HapticFeedbackSettings(
                    settings: _feedbackSettings!,
                    onChanged: _updateFeedbackSettings,
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _SettingsSection(
                icon: Icons.music_note,
                title: context.tr('settings.soundFeedback.title'),
                children: [
                  _SoundFeedbackSettings(
                    settings: _feedbackSettings!,
                    onChanged: _updateFeedbackSettings,
                  ),
                ],
              ),
            ],
            const SizedBox(height: 16),
            _SettingsSection(
              icon: Icons.notifications_active,
              title: context.tr('settings.notifications'),
              children: [
                _SettingsSwitchTile(
                  icon: Icons.alarm,
                  title: context.tr('settings.notifications.daily'),
                  subtitle: _remindersLocked
                      ? context.tr('settings.notifications.locked')
                      : context.tr('settings.notifications.desc'),
                  value: _reminders,
                  onChanged: _toggleReminders,
                  enabled: !_remindersLocked,
                  onDisabledTap: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          context.tr('settings.notifications.locked'),
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
            const SizedBox(height: 16),
            _SettingsSection(
              icon: Icons.info_outline,
              title: context.tr('settings.about'),
              children: [
                _SettingsActionTile(
                  icon: Icons.share_rounded,
                  title: context.tr('common.shareApp'),
                  onTap: _shareApp,
                ),
                _SettingsActionTile(
                  icon: Icons.star_rate_rounded,
                  title: context.tr('settings.rate'),
                  subtitle: context.tr('settings.rate.subtitle'),
                  onTap: _rateOnPlayStore,
                ),
                _SettingsActionTile(
                  icon: Icons.privacy_tip_outlined,
                  title: context.tr('settings.privacy'),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const PrivacyPolicyPage(),
                    ),
                  ),
                ),
                _SettingsActionTile(
                  icon: Icons.article_outlined,
                  title: context.tr('settings.terms'),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const TermsConditionsPage(),
                    ),
                  ),
                ),
                _SettingsActionTile(
                  icon: Icons.info_outline,
                  title: context.tr('settings.aboutApp'),
                  onTap: () => Navigator.of(
                    context,
                  ).push(MaterialPageRoute(builder: (_) => const AboutPage())),
                ),
              ],
            ),
            const SizedBox(height: 24),
            _aboutFooter(context),
          ],
            );
          },
        ),
        ),
      ),
    );
  }

  Widget _aboutFooter(BuildContext context) {
    final style = Theme.of(context).textTheme.bodySmall;
    return Padding(
      padding: const EdgeInsets.only(bottom: 28),
      child: Column(
        children: [
          Text('Naam Jap Counter : Sadhna • V 1.0', style: style),
          const SizedBox(height: 4),
          Text('Made with devotion in India', style: style),
        ],
      ),
    );
  }
}

class _SettingsSection extends StatelessWidget {
  final IconData icon;
  final String title;
  final List<Widget> children;

  const _SettingsSection({
    required this.icon,
    required this.title,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return GlassCard(
      margin: EdgeInsets.zero,
      padding: const EdgeInsets.all(18),
      borderRadius: DesignSystem.radiusCard,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _SettingsIconCircle(icon: icon, color: cs.primary),
              const SizedBox(width: 12),
              Text(
                title,
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
              ),
            ],
          ),
          const SizedBox(height: 16),
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) const Divider(height: 20),
            children[i],
          ],
        ],
      ),
    );
  }
}

class _SettingsSwitchTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;
  final bool enabled;
  final VoidCallback? onDisabledTap;

  const _SettingsSwitchTile({
    required this.icon,
    required this.title,
    this.subtitle,
    required this.value,
    required this.onChanged,
    this.enabled = true,
    this.onDisabledTap,
  });

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: _SettingsIconCircle(
        icon: icon,
        color: Theme.of(context).colorScheme.primary,
      ),
      title: Text(
        title,
        style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
      ),
      subtitle: subtitle == null ? null : Text(subtitle!),
      trailing: Switch.adaptive(
        value: value,
        onChanged: enabled ? onChanged : null,
      ),
      onTap: () {
        if (enabled) {
          onChanged(!value);
        } else {
          onDisabledTap?.call();
        }
      },
    );
  }
}

class _SettingsActionTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;

  const _SettingsActionTile({
    required this.icon,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: _SettingsIconCircle(
        icon: icon,
        color: Theme.of(context).colorScheme.primary,
      ),
      title: Text(
        title,
        style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
      ),
      subtitle: subtitle == null ? null : Text(subtitle!),
      trailing: trailing ?? const Icon(Icons.chevron_right),
      onTap: onTap == null
          ? null
          : () {
              HapticFeedback.selectionClick();
              onTap!();
            },
    );
  }
}

class _SettingsIconCircle extends StatelessWidget {
  final IconData icon;
  final Color color;

  const _SettingsIconCircle({required this.icon, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color.withOpacity(0.12),
      ),
      child: Icon(icon, color: color),
    );
  }
}

class _ValuePill extends StatelessWidget {
  final String label;

  const _ValuePill({required this.label});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: cs.primary.withOpacity(0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
          color: cs.primary,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _HapticFeedbackSettings extends StatefulWidget {
  final TapFeedbackSettings settings;
  final ValueChanged<TapFeedbackSettings> onChanged;

  const _HapticFeedbackSettings({
    required this.settings,
    required this.onChanged,
  });

  @override
  State<_HapticFeedbackSettings> createState() =>
      _HapticFeedbackSettingsState();
}

class _HapticFeedbackSettingsState extends State<_HapticFeedbackSettings> {
  static const int _minInterval = 1;
  static const int _maxInterval = 50;

  late HapticMode _mode;
  late int _n;

  @override
  void initState() {
    super.initState();
    _syncFromWidget();
  }

  @override
  void didUpdateWidget(covariant _HapticFeedbackSettings oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.settings != widget.settings) {
      _syncFromWidget();
    }
  }

  void _syncFromWidget() {
    // Migrate any remaining everyN to everyMala (shouldn't happen due to migration in load, but safety check)
    final mode = widget.settings.hapticMode;
    _mode = mode == HapticMode.everyN ? HapticMode.everyMala : mode;
    _n = _sanitizeInterval(widget.settings.hapticN);
  }

  int _sanitizeInterval(int value) {
    if (value < _minInterval) return _minInterval;
    if (value > _maxInterval) return _maxInterval;
    return value;
  }

  String _labelFor(BuildContext context, HapticMode mode) {
    final key = switch (mode) {
      HapticMode.off => 'settings.haptic.mode.off',
      HapticMode.everyTap => 'settings.haptic.mode.everyTap',
      HapticMode.everyN => 'settings.haptic.mode.everyN',
      HapticMode.everyMala => 'settings.haptic.mode.everyMala',
    };
    return context.tr(key);
  }

  String _descriptionFor(BuildContext context, HapticMode mode) {
    final key = switch (mode) {
      HapticMode.off => 'settings.haptic.mode.off.desc',
      HapticMode.everyTap => 'settings.haptic.mode.everyTap.desc',
      HapticMode.everyN => 'settings.haptic.mode.everyN.desc',
      HapticMode.everyMala => 'settings.haptic.mode.everyMala.desc',
    };
    return context.tr(key);
  }

  Future<void> _previewHaptic() async {
    HapticFeedback.selectionClick();
    final current = widget.settings.copyWith(
      hapticMode: _mode,
      hapticN: _n,
    );
    await TapFeedbackController.instance.updateSettings(current);
    await TapFeedbackController.instance.previewHaptic();
  }

  void _updateMode(HapticMode mode) {
    if (_mode == mode) return;
    setState(() => _mode = mode);
    widget.onChanged(widget.settings.copyWith(hapticMode: mode));
  }

  void _updateN(int value) {
    final sanitized = _sanitizeInterval(value);
    if (_n == sanitized) return;
    setState(() => _n = sanitized);
    widget.onChanged(widget.settings.copyWith(hapticN: sanitized));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          context.tr('settings.haptic.description'),
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 12),
        ...HapticMode.values.where((mode) => mode != HapticMode.everyN).map(
          (mode) => RadioListTile<HapticMode>(
            value: mode,
            contentPadding: EdgeInsets.zero,
            groupValue: _mode,
            onChanged: (value) {
              if (value != null) {
                HapticFeedback.selectionClick();
                _updateMode(value);
              }
            },
            title: Text(_labelFor(context, mode)),
            subtitle: Text(_descriptionFor(context, mode)),
          ),
        ),
        const SizedBox(height: 16),
        FilledButton.tonalIcon(
          onPressed: _previewHaptic,
          icon: const Icon(Icons.vibration_rounded),
          label: Text(context.tr('settings.haptic.test')),
        ),
      ],
    );
  }
}

class _SoundFeedbackSettings extends StatefulWidget {
  final TapFeedbackSettings settings;
  final ValueChanged<TapFeedbackSettings> onChanged;

  const _SoundFeedbackSettings({
    required this.settings,
    required this.onChanged,
  });

  @override
  State<_SoundFeedbackSettings> createState() => _SoundFeedbackSettingsState();
}

class _SoundFeedbackSettingsState extends State<_SoundFeedbackSettings> {
  static const int _minInterval = 1;
  static const int _maxInterval = 108;

  late SoundMode _mode;
  late int _n;
  late String _asset;

  @override
  void initState() {
    super.initState();
    _syncFromWidget();
  }

  @override
  void didUpdateWidget(covariant _SoundFeedbackSettings oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.settings != widget.settings) {
      _syncFromWidget();
    }
  }

  void _syncFromWidget() {
    // Migrate any remaining everyN or everyTap to everyMala (shouldn't happen due to migration in load, but safety check)
    final mode = widget.settings.soundMode;
    _mode = (mode == SoundMode.everyN || mode == SoundMode.everyTap) 
        ? SoundMode.everyMala 
        : mode;
    _n = _sanitizeInterval(widget.settings.soundN);
    // Always use bell sound
    _asset = 'audio/bell_end.mp3';
  }

  int _sanitizeInterval(int value) {
    if (value < _minInterval) return _minInterval;
    if (value > _maxInterval) return _maxInterval;
    return value;
  }

  String _labelFor(BuildContext context, SoundMode mode) {
    final key = switch (mode) {
      SoundMode.off => 'settings.soundFeedback.mode.off',
      SoundMode.everyTap => 'settings.soundFeedback.mode.everyTap',
      SoundMode.everyN => 'settings.soundFeedback.mode.everyN',
      SoundMode.everyMala => 'settings.soundFeedback.mode.everyMala',
    };
    return context.tr(key);
  }

  String _descriptionFor(BuildContext context, SoundMode mode) {
    final key = switch (mode) {
      SoundMode.off => 'settings.soundFeedback.mode.off.desc',
      SoundMode.everyTap => 'settings.soundFeedback.mode.everyTap.desc',
      SoundMode.everyN => 'settings.soundFeedback.mode.everyN.desc',
      SoundMode.everyMala => 'settings.soundFeedback.mode.everyMala.desc',
    };
    return context.tr(key);
  }

  String _displayNameForAsset(String asset) {
    final name = asset.split('/').last;
    final withoutExt = name.replaceAll('.mp3', '').replaceAll('.wav', '');
    return withoutExt
        .split('_')
        .map((part) => part.isEmpty
            ? ''
            : part[0].toUpperCase() + part.substring(1).toLowerCase())
        .join(' ');
  }

  void _updateMode(SoundMode mode) {
    if (_mode == mode) return;
    setState(() => _mode = mode);
    // Always use bell sound when updating mode
    widget.onChanged(widget.settings.copyWith(
      soundMode: mode,
      soundAsset: 'audio/bell_end.mp3',
    ));
  }

  void _updateN(int value) {
    final sanitized = _sanitizeInterval(value);
    if (_n == sanitized) return;
    setState(() => _n = sanitized);
    widget.onChanged(widget.settings.copyWith(soundN: sanitized));
  }

  void _updateAsset(String asset) {
    if (_asset == asset) return;
    setState(() => _asset = asset);
    widget.onChanged(widget.settings.copyWith(soundAsset: asset));
  }

  Future<void> _previewSound() async {
    if (_mode == SoundMode.off) {
      HapticFeedback.selectionClick();
      return;
    }
    HapticFeedback.selectionClick();
    // Always use bell sound
    final current = widget.settings.copyWith(
      soundMode: _mode,
      soundN: _n,
      soundAsset: 'audio/bell_end.mp3',
    );
    await TapFeedbackController.instance.updateSettings(current);
    await TapFeedbackController.instance.previewSound();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final disableSoundControls = _mode == SoundMode.off;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          context.tr('settings.soundFeedback.description'),
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 12),
        ...SoundMode.values.where((mode) => mode != SoundMode.everyN && mode != SoundMode.everyTap).map(
          (mode) => RadioListTile<SoundMode>(
            value: mode,
            contentPadding: EdgeInsets.zero,
            groupValue: _mode,
            onChanged: (value) {
              if (value != null) {
                HapticFeedback.selectionClick();
                _updateMode(value);
              }
            },
            title: Text(_labelFor(context, mode)),
            subtitle: Text(_descriptionFor(context, mode)),
          ),
        ),
        const SizedBox(height: 16),
        FilledButton.tonalIcon(
          onPressed: disableSoundControls ? null : _previewSound,
          icon: const Icon(Icons.music_note_rounded),
          label: Text(context.tr('settings.soundFeedback.preview')),
        ),
      ],
    );
  }
}
