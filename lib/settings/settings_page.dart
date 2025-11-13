import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:share_plus/share_plus.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../core/prefs_manager.dart';
import '../notifications/notification_service.dart';
import '../data/goal_store.dart';
import '../data/language_store.dart';
import '../legal/privacy_policy.dart';
import '../legal/terms_conditions.dart';
import 'about_page.dart';
import '../ui/glow_card.dart';
import '../l10n/app_localizations.dart';

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
  int _goalMalas = 1;
  bool _soundEnabled = true;

  static const _keyReminders = 'notificationsEnabled';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await PrefsManager.instance;
    final gs = await GoalStore.create();
    final ns = NotificationService();
    await ns.init();
    final allowed = await ns.areNotificationsAllowed();
    final storedReminders = prefs.getBool(_keyReminders) ?? true;
    final shouldEnable = allowed || storedReminders;
    if (allowed && shouldEnable) {
      final language = await LanguageStore.current();
      await ns.scheduleDefaults(language: language);
    }
    if (!mounted) return;
    setState(() {
      _remindersLocked = allowed;
      _reminders = shouldEnable;
      _goalMalas = gs.dailyMalasGoal;
      _soundEnabled = prefs.getBool('settings.soundEnabled') ?? true;
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

  Future<void> _toggleBell(bool value) async {
    HapticFeedback.lightImpact();
    setState(() => _soundEnabled = value);
    final prefs = await PrefsManager.instance;
    await prefs.setBool('settings.soundEnabled', value);
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

  Future<void> _openGoalSheet() async {
    var temp = _goalMalas;
    final result = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) {
        final bottomInset = MediaQuery.of(sheetContext).viewInsets.bottom;
        return Padding(
          padding: EdgeInsets.fromLTRB(24, 24, 24, bottomInset + 24),
          child: StatefulBuilder(
            builder: (context, setModalState) {
              final label = _formatGoalLabel(context, temp);
              const quickOptions = [0, 1, 2, 3, 5, 8, 10];
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    context.tr('settings.goal.title'),
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    context.tr('settings.goal.subtitle'),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 20),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: quickOptions.map((option) {
                      final optionLabel = _formatGoalLabel(context, option);
                      return ChoiceChip(
                        label: Text(optionLabel),
                        selected: temp == option,
                        onSelected: (_) {
                          HapticFeedback.selectionClick();
                          setModalState(() => temp = option);
                        },
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 16),
                  Slider(
                    min: 0,
                    max: 20,
                    divisions: 20,
                    value: temp.toDouble(),
                    label: '$temp',
                    onChanged: (value) {
                      HapticFeedback.lightImpact();
                      setModalState(() => temp = value.round());
                    },
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: Text(
                      label,
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: Text(context.tr('common.cancel')),
                      ),
                      const SizedBox(width: 12),
                      FilledButton(
                        onPressed: () => Navigator.pop<int>(context, temp),
                        child: Text(context.tr('common.save')),
                      ),
                    ],
                  ),
                ],
              );
            },
          ),
        );
      },
    );

    if (result == null) return;

    setState(() => _goalMalas = result);
    final gs = await GoalStore.create();
    await gs.setDailyMalasGoal(result);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(context.tr('settings.goal.updated')),
        duration: const Duration(seconds: 1),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = widget.themeMode == ThemeMode.dark;
    final language = widget.language;
    final goalLabel = _formatGoalLabel(context, _goalMalas);

    return Scaffold(
      appBar: AppBar(title: Text(context.tr('settings.title'))),
      body: SafeArea(
        child: ListView(
          padding: EdgeInsets.fromLTRB(
            16,
            16,
            16,
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
            _SettingsSection(
              icon: Icons.music_note,
              title: context.tr('settings.sound'),
              children: [
                _SettingsSwitchTile(
                  icon: Icons.music_note_outlined,
                  title: context.tr('settings.sound.malaBell'),
                  subtitle: context.tr('settings.sound.action'),
                  value: _soundEnabled,
                  onChanged: _toggleBell,
                ),
              ],
            ),
            const SizedBox(height: 16),
            _SettingsSection(
              icon: Icons.flag,
              title: context.tr('settings.goal'),
              children: [
                _SettingsActionTile(
                  icon: Icons.flag_outlined,
                  title: context.tr('settings.goal.title'),
                  subtitle: context.tr('settings.goal.subtitle'),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _ValuePill(label: goalLabel),
                      const SizedBox(width: 8),
                      const Icon(Icons.chevron_right),
                    ],
                  ),
                  onTap: _openGoalSheet,
                ),
              ],
            ),
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
        ),
      ),
    );
  }

  String _formatGoalLabel(BuildContext context, int value) {
    if (value == 0) return context.tr('common.off');
    final language = widget.language;
    if (language == 'hi') {
      return '$value माला${value == 1 ? '' : 'एँ'}';
    }
    return '$value mala${value == 1 ? '' : 's'}';
  }

  Widget _aboutFooter(BuildContext context) {
    final style = Theme.of(context).textTheme.bodySmall;
    return FutureBuilder<PackageInfo>(
      future: PackageInfo.fromPlatform(),
      builder: (context, snapshot) {
        final ver = snapshot.data?.version ?? '';
        final build = snapshot.data?.buildNumber ?? '';
        final versionLabel = ver.isEmpty ? '' : ' • v$ver+$build';
        return Padding(
          padding: const EdgeInsets.only(bottom: 28),
          child: Column(
            children: [
              Text('Naam Jap Counter : Sadhna$versionLabel', style: style),
              const SizedBox(height: 4),
              Text('Made with devotion in India', style: style),
            ],
          ),
        );
      },
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
    return GlowCard(
      margin: EdgeInsets.zero,
      padding: const EdgeInsets.all(18),
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
