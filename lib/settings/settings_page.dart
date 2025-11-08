import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:share_plus/share_plus.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../notifications/notification_service.dart';
import '../data/goal_store.dart';
import '../data/counter_store.dart';
import '../data/activity_store.dart';
import '../data/meditation_store.dart';
import '../data/session_store.dart';
import '../data/dedication_store.dart';
import '../data/backup_service.dart';
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
  bool _soundHaptics = true; // UI only; wire up when preferences exist
  int _goalMalas = 1;
  bool _soundEnabled = true;

  static const _keyReminders = 'notificationsEnabled';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final gs = await GoalStore.create();
    if (!mounted) return;
    setState(() {
      _reminders = prefs.getBool(_keyReminders) ?? true;
      _goalMalas = gs.dailyMalasGoal;
      _soundEnabled = prefs.getBool('settings.soundEnabled') ?? true;
    });
  }

  Future<void> _toggleReminders(bool value) async {
    setState(() => _reminders = value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyReminders, value);

    final ns = NotificationService();
    if (value) {
      await ns.init();
      final allowed = await ns.requestPermission();
      if (allowed) await ns.scheduleDefaults();
    } else {
      final plugin = FlutterLocalNotificationsPlugin();
      await plugin.cancelAll();
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = widget.themeMode == ThemeMode.dark;

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            expandedHeight: 140,
            backgroundColor: scheme.surface,
            flexibleSpace: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    scheme.primary.withValues(alpha: 0.16),
                    scheme.secondary.withValues(alpha: 0.10),
                    scheme.surface,
                  ],
                ),
              ),
              child: FlexibleSpaceBar(
                titlePadding: const EdgeInsetsDirectional.only(
                  start: 16,
                  bottom: 12,
                ),
                title: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.tr('settings.title'),
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: scheme.primary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      context.tr('settings.subtitle'),
                      style: Theme.of(context).textTheme.labelMedium,
                    ),
                  ],
                ),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: GlowCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _sectionHeader(
                    context,
                    Icons.notifications_active,
                    context.tr('settings.notifications'),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              context.tr('settings.notifications.daily'),
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              context.tr('settings.notifications.desc'),
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                      Switch(value: _reminders, onChanged: _toggleReminders),
                    ],
                  ),
                ],
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: GlowCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _sectionHeader(
                    context,
                    Icons.flag,
                    context.tr('settings.goal'),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              context.tr('settings.goal.title'),
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              context.tr('settings.goal.subtitle'),
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                      Text('$_goalMalas'),
                    ],
                  ),
                  Slider(
                    min: 0,
                    max: 20,
                    divisions: 20,
                    value: _goalMalas.toDouble(),
                    label: '$_goalMalas',
                    onChanged: (v) => setState(() => _goalMalas = v.round()),
                    onChangeEnd: (v) async {
                      final gs = await GoalStore.create();
                      await gs.setDailyMalasGoal(v.round());
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(context.tr('settings.goal.updated')),
                            duration: const Duration(seconds: 1),
                          ),
                        );
                      }
                    },
                  ),
                ],
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: GlowCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _sectionHeader(
                    context,
                    Icons.volume_up,
                    context.tr('settings.sound'),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          context.tr('settings.sound.action'),
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ),
                      Switch(
                        value: _soundHaptics,
                        onChanged: (value) =>
                            setState(() => _soundHaptics = value),
                      ),
                    ],
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(context.tr('settings.sound.malaBell')),
                    value: _soundEnabled,
                    onChanged: (v) async {
                      setState(() => _soundEnabled = v);
                      final prefs = await SharedPreferences.getInstance();
                      await prefs.setBool('settings.soundEnabled', v);
                    },
                  ),
                ],
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: GlowCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _sectionHeader(
                    context,
                    Icons.language,
                    context.tr('settings.language'),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    context.tr('settings.language.subtitle'),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 12),
                  SegmentedButton<String>(
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
                      widget.onLanguageChanged(value);
                    },
                  ),
                ],
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: GlowCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _sectionHeader(
                    context,
                    Icons.info_outline,
                    context.tr('settings.about'),
                  ),
                  const SizedBox(height: 12),
                  _pillButton(
                    context,
                    label: context.tr('settings.privacy'),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const PrivacyPolicyPage(),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  _pillButton(
                    context,
                    label: context.tr('settings.terms'),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const TermsConditionsPage(),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  ListTile(
                    leading: const Icon(Icons.info_outline),
                    title: Text(context.tr('settings.aboutApp')),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const AboutPage()),
                    ),
                  ),
                  const SizedBox(height: 16),
                  _rateCard(context),
                ],
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: GlowCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _sectionHeader(
                    context,
                    Icons.backup,
                    context.tr('settings.data'),
                  ),
                  const SizedBox(height: 8),
                  FilledButton.icon(
                    icon: const Icon(Icons.cloud_upload),
                    label: Text(context.tr('settings.data.export')),
                    onPressed: () async {
                      await BackupService.exportToJson();
                    },
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.delete_forever),
                    label: Text(context.tr('settings.data.reset')),
                    onPressed: () async {
                      final confirmed = await showDialog<bool>(
                        context: context,
                        builder: (_) => AlertDialog(
                          title: Text(context.tr('settings.data.resetConfirm')),
                          content: Text(
                            context.tr('settings.data.resetMessage'),
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(context, false),
                              child: Text(context.tr('common.cancel')),
                            ),
                            FilledButton(
                              onPressed: () => Navigator.pop(context, true),
                              child: Text(context.tr('common.reset')),
                            ),
                          ],
                        ),
                      );
                      if (confirmed != true) return;

                      final counter = await CounterStore.create();
                      await counter.resetAll();
                      await ActivityStore.resetAll();
                      final meditation = await MeditationStore.create();
                      await meditation.resetAll();
                      final sessions = await SessionStore.create();
                      await sessions.clear();
                      final goal = await GoalStore.create();
                      await goal.setDailyMalasGoal(1);
                      final dedication = await DedicationStore.create();
                      await dedication.setNote('');

                      if (!mounted) return;
                      await _load();
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            context.tr('settings.data.resetSuccess'),
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
              child: SizedBox(
                height: 54,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  onPressed: () async {
                    const pkg = 'com.example.jap_counter';
                    final link =
                        'https://play.google.com/store/apps/details?id=$pkg';
                    await SharePlus.instance.share(
                      ShareParams(text: link, subject: 'Radha Jap Counter'),
                    );
                  },
                  child: Text(context.tr('common.shareApp')),
                ),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    context.tr('settings.theme'),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 12),
                  SegmentedButton<bool>(
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
                      widget.onThemeModeChanged(
                        dark ? ThemeMode.dark : ThemeMode.light,
                      );
                },
                  ),
                ],
              ),
            ),
          ),
          SliverToBoxAdapter(child: _aboutFooter(context)),
        ],
      ),
    );
  }

  Widget _sectionHeader(BuildContext context, IconData icon, String title) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: cs.primary.withValues(alpha: 0.12),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: cs.primary),
        ),
        const SizedBox(width: 12),
        Text(
          title,
          style: Theme.of(
            context,
          ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
        ),
      ],
    );
  }

  Widget _pillButton(
    BuildContext context, {
    required String label,
    required VoidCallback onTap,
  }) {
    final divider = Theme.of(context).dividerColor.withValues(alpha: 0.5);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        height: 48,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          color: Theme.of(context).colorScheme.surface,
          border: Border.all(color: divider),
        ),
        alignment: Alignment.center,
        child: Text(label, style: Theme.of(context).textTheme.titleMedium),
      ),
    );
  }

  Widget _rateCard(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.primary.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.primary.withValues(alpha: 0.18)),
      ),
      child: Column(
        children: [
          Text(
            'Rate on Play Store — Radha Jap Counter',
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 44,
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onPressed: () async {
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
              },
              child: const Text('Rate on Play Store'),
            ),
          ),
        ],
      ),
    );
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
              Text('Radha Jap Counter$versionLabel', style: style),
              const SizedBox(height: 4),
              Text('Made with devotion in India', style: style),
            ],
          ),
        );
      },
    );
  }
}
