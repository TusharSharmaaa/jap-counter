import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../theme/neumorph.dart';

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
  String _version = '';

  @override
  void initState() {
    super.initState();
    _loadVersion();
  }

  Future<void> _loadVersion() async {
    final info = await PackageInfo.fromPlatform();
    if (!mounted) return;
    setState(() => _version = info.version);
  }

  Future<void> _rateApp() async {
    const pkg = 'com.example.jap_counter';
    final marketUri = Uri.parse('market://details?id=$pkg');
    final webUri = Uri.parse('https://play.google.com/store/apps/details?id=$pkg');

    bool launched = false;
    if (await canLaunchUrl(marketUri)) {
      launched = await launchUrl(marketUri);
    }
    if (!launched) {
      launched = await launchUrl(webUri, mode: LaunchMode.externalApplication);
    }

    if (!launched && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to open Play Store.')),
      );
    }
  }

  Future<void> _shareApp() async {
    const pkg = 'com.example.jap_counter';
    final link = 'https://play.google.com/store/apps/details?id=$pkg';
    await SharePlus.instance.share(
      ShareParams(text: 'मैं Radha Jap Counter ऐप इस्तेमाल कर रहा/रही हूँ — $link'),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mode = widget.themeMode;

    return Scaffold(
      appBar: AppBar(
        title: const Text('सेटिंग्स'),
        centerTitle: true,
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              theme.colorScheme.surface,
              theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: Neo.card(context),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('थीम मोड', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 12),
                  SegmentedButton<ThemeMode>(
                    segments: const [
                      ButtonSegment(value: ThemeMode.light, label: Text('Light')),
                      ButtonSegment(value: ThemeMode.dark, label: Text('Dark')),
                      ButtonSegment(value: ThemeMode.system, label: Text('Auto')),
                    ],
                    selected: {mode},
                    onSelectionChanged: (selection) {
                      widget.onThemeModeChanged(selection.first);
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: Neo.card(context),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('साझा करें', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 8),
                  ListTile(
                    leading: const Icon(Icons.star_rate_rounded),
                    title: const Text('रेट करें'),
                    subtitle: const Text('आपका एक रेटिंग हमें प्रेरित करता है'),
                    onTap: _rateApp,
                  ),
                  ListTile(
                    leading: const Icon(Icons.share),
                    title: const Text('शेयर करें'),
                    subtitle: const Text('दोस्तों के साथ साधना बांटें'),
                    onTap: _shareApp,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            Center(
              child: Column(
                children: [
                  Icon(Icons.favorite, color: theme.colorScheme.primary, size: 40),
                  const SizedBox(height: 6),
                  const Text('Made with ❤️ for Bhakti'),
                  const SizedBox(height: 4),
                  Text('Version $_version', style: theme.textTheme.labelMedium),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

