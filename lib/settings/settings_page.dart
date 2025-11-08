import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:share_plus/share_plus.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../notifications/notification_service.dart';
import '../legal/privacy_policy.dart';
import '../legal/terms_conditions.dart';
import '../ui/glow_card.dart';
import '../utils/backup_manager.dart';

class SettingsPage extends StatefulWidget {
  final ThemeMode themeMode;
  final ValueChanged<ThemeMode> onThemeModeChanged;

  const SettingsPage({
    super.key,
    required this.themeMode,
    required this.onThemeModeChanged,
  });

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool _reminders = false;
  bool _soundHaptics = true; // UI only; wire up when preferences exist

  static const _keyReminders = 'notificationsEnabled';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _reminders = prefs.getBool(_keyReminders) ?? true;
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
                titlePadding: const EdgeInsetsDirectional.only(start: 16, bottom: 12),
                title: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Settings',
                      style: Theme.of(context)
                          .textTheme
                          .titleLarge
                          ?.copyWith(color: scheme.primary, fontWeight: FontWeight.w700),
                    ),
                    Text(
                      'Customize your experience',
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
                  _sectionHeader(context, Icons.notifications_active, 'Notifications'),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              "Daily Reminders",
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              "Get reminded to maintain your streak",
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
                  _sectionHeader(context, Icons.volume_up, 'Sound'),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          "Play sound feedback on actions",
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ),
                      Switch(
                        value: _soundHaptics,
                        onChanged: (value) => setState(() => _soundHaptics = value),
                      ),
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
                  _sectionHeader(context, Icons.info_outline, 'About'),
                  const SizedBox(height: 12),
                  _pillButton(
                    context,
                    label: 'Privacy Policy',
                    onTap: () => Navigator.of(context)
                        .push(MaterialPageRoute(builder: (_) => const PrivacyPolicyPage())),
                  ),
                  const SizedBox(height: 10),
                  _pillButton(
                    context,
                    label: 'Terms & Conditions',
                    onTap: () => Navigator.of(context)
                        .push(MaterialPageRoute(builder: (_) => const TermsConditionsPage())),
                  ),
                  const SizedBox(height: 12),
                  ListTile(
                    leading: const Icon(Icons.backup),
                    title: const Text('Export Backup'),
                    subtitle: const Text('Save your jap progress locally'),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    onTap: () async {
                      final path = await BackupManager.exportBackup();
                      await Share.shareXFiles(
                        [XFile(path)],
                        text: 'मेरा Radha Jap Counter बैकअप',
                      );
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.restore),
                    title: const Text('Import Backup'),
                    subtitle: const Text('Restore from a saved JSON file'),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    onTap: () async {
                      final picker = FilePicker.platform;
                      final file = await picker.pickFiles(type: FileType.any);
                      if (file != null && file.files.single.path != null) {
                        try {
                          await BackupManager.importBackup(File(file.files.single.path!));
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Backup restored successfully 🌸')),
                            );
                          }
                        } catch (e) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Backup restore failed: $e')),
                            );
                          }
                        }
                      }
                    },
                  ),
                  const SizedBox(height: 16),
                  _rateCard(context),
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
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  onPressed: () async {
                    const pkg = 'com.example.jap_counter';
                    final link = 'https://play.google.com/store/apps/details?id=$pkg';
                    await SharePlus.instance.share(
                      ShareParams(text: link, subject: 'Radha Jap Counter'),
                    );
                  },
                  child: const Text('Share App'),
                ),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 28),
              child: SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: false, label: Text('Light'), icon: Icon(Icons.wb_sunny)),
                  ButtonSegment(value: true, label: Text('Dark'), icon: Icon(Icons.dark_mode)),
                ],
                selected: {isDark},
                onSelectionChanged: (selection) {
                  final dark = selection.first;
                  widget.onThemeModeChanged(dark ? ThemeMode.dark : ThemeMode.light);
                },
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
          style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
        ),
      ],
    );
  }

  Widget _pillButton(BuildContext context, {required String label, required VoidCallback onTap}) {
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
            style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 44,
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: () async {
                const pkg = 'com.example.jap_counter';
                final marketUri = Uri.parse('market://details?id=$pkg');
                final webUri = Uri.parse('https://play.google.com/store/apps/details?id=$pkg');
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

