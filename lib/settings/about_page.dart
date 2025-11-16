import 'package:flutter/material.dart';
import '../theme/design_system.dart';

class AboutPage extends StatelessWidget {
  const AboutPage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    
    // Theme-aware text colors
    final titleColor = colorScheme.onSurface;
    final bodyColor = colorScheme.onSurface;
    final subtitleColor = colorScheme.onSurfaceVariant;
    
    return Scaffold(
      appBar: AppBar(title: const Text('About App')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // App Icon
            Container(
                  width: 100,
                  height: 100,
                  decoration: BoxDecoration(
                  color: colorScheme.primary.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.self_improvement,
                    size: 56,
                    color: colorScheme.primary,
                  ),
            ),
            const SizedBox(height: 24),
            
            // App Name
            Text(
                  'Naam Jap Counter : Sadhna',
                  style: theme.textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    fontSize: 24,
                    color: titleColor,
                    height: 1.2,
                  ),
                  textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            
            // Version
            Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                  color: colorScheme.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    'Version 1.0',
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontSize: 13,
                      color: colorScheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
            ),
            const SizedBox(height: 32),
            
            // Description
            Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: colorScheme.surface.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: colorScheme.primary.withValues(alpha: 0.2),
                      width: 1,
                    ),
                  ),
                  child: Column(
                    children: [
                      Text(
                        'A peaceful jap and meditation companion for your daily bhakti journey.',
                        style: theme.textTheme.bodyLarge?.copyWith(
                          fontSize: 16,
                          color: bodyColor,
                          height: 1.6,
                          letterSpacing: 0.2,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Made with devotion and technology.',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontSize: 15,
                          color: subtitleColor,
                          height: 1.5,
                          fontStyle: FontStyle.italic,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
            ),
            const SizedBox(height: 40),
            
            // Features Section
            _buildFeatureItem(
                  context: context,
                  icon: Icons.countertops,
                  title: 'Jap Counting',
                  description: 'Track your daily naam jap with ease',
                  titleColor: titleColor,
                  bodyColor: bodyColor,
                ),
                const SizedBox(height: 16),
                _buildFeatureItem(
                  context: context,
                  icon: Icons.timer,
                  title: 'Meditation Timer',
                  description: 'Focus on your sadhna with guided sessions',
                  titleColor: titleColor,
                  bodyColor: bodyColor,
                ),
                const SizedBox(height: 16),
                _buildFeatureItem(
                  context: context,
                  icon: Icons.notifications_active,
                  title: 'Daily Reminders',
                  description: 'Stay consistent with spiritual practice',
                  titleColor: titleColor,
                  bodyColor: bodyColor,
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }
  
  Widget _buildFeatureItem({
    required BuildContext context,
    required IconData icon,
    required String title,
    required String description,
    required Color titleColor,
    required Color bodyColor,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    
    return Row(
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: colorScheme.primary.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(
            icon,
            color: colorScheme.primary,
            size: 24,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  fontSize: 16,
                  color: titleColor,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                description,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontSize: 13,
                  color: bodyColor,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

