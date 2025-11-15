import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../theme/design_system.dart';

class AboutPage extends StatelessWidget {
  const AboutPage({super.key});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<PackageInfo>(
      future: PackageInfo.fromPlatform(),
      builder: (context, snapshot) {
        final version = snapshot.data?.version ?? '';
        return Scaffold(
          backgroundColor: DesignSystem.backgroundLight,
          appBar: AppBar(
            title: const Text('About App'),
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
            child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Icon(
                  Icons.self_improvement,
                  size: 72,
                  color: Theme.of(context).colorScheme.primary.withOpacity(0.8),
                ),
                const SizedBox(height: 12),
                ShaderMask(
                  shaderCallback: (rect) => LinearGradient(
                    colors: [
                      Theme.of(context).colorScheme.primary,
                      Theme.of(context).colorScheme.tertiary,
                    ],
                  ).createShader(rect),
                  child: const Text(
                    'Naam Jap Counter : Sadhna',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 22,
                      color: Color(0xFF1A1A1A),
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Text('Version $version', style: const TextStyle(fontSize: 12)),
                const SizedBox(height: 24),
                const Text(
                  'A peaceful jap and meditation companion for your daily bhakti journey.\n\nMade with devotion and technology.',
                  textAlign: TextAlign.center,
                  style: TextStyle(height: 1.4),
                ),
                const Spacer(),
                const Text(
                  '© 2025 Wearit Global Spiritual Apps',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
            ),
          ),
        );
      },
    );
  }
}

