import 'package:flutter/material.dart';

class TermsConditionsPage extends StatelessWidget {
  const TermsConditionsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Terms & Conditions')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Terms & Conditions',
            style: theme.textTheme.headlineSmall?.copyWith(
              color: const Color(0xFF1A1A1A), // Explicit dark color
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Effective Date: 06-Oct-2025',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: const Color(0xFF666666), // Explicit dark color
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'By using the Naam Jap Counter : Sadhna app, you agree to the following terms and conditions.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: const Color(0xFF1A1A1A), // Explicit dark color
            ),
          ),
          const SizedBox(height: 12),
          Text(
            '1. Purpose: The app is designed to assist in devotional jap counting and meditation reminders. It is a spiritual utility, not a commercial service.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: const Color(0xFF1A1A1A), // Explicit dark color
            ),
          ),
          const SizedBox(height: 12),
          Text(
            '2. Usage: You may use the app freely for personal spiritual practice. Commercial use, reselling, or modification for redistribution is prohibited.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: const Color(0xFF1A1A1A), // Explicit dark color
            ),
          ),
          const SizedBox(height: 12),
          Text(
            '3. Data: All your jap counts, meditation minutes, and settings are stored locally on your device. We do not access, share, or upload your data.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: const Color(0xFF1A1A1A), // Explicit dark color
            ),
          ),
          const SizedBox(height: 12),
          Text(
            '4. Ads: The app may display Google AdMob ads. These are used ethically to support app development. Ad behavior and targeting are controlled by Google.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: const Color(0xFF1A1A1A), // Explicit dark color
            ),
          ),
          const SizedBox(height: 12),
          Text(
            '5. Liability: We are not responsible for any device issues, missed notifications, or data loss arising from app use.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: const Color(0xFF1A1A1A), // Explicit dark color
            ),
          ),
          const SizedBox(height: 12),
          Text(
            '6. Updates: App features and terms may change over time. Continued use signifies acceptance of the updated terms.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: const Color(0xFF1A1A1A), // Explicit dark color
            ),
          ),
          const SizedBox(height: 12),
          Text(
            '7. Contact: For feedback or concerns, you may contact us via the Play Store listing.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: const Color(0xFF1A1A1A), // Explicit dark color
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Thank you for using Naam Jap Counter : Sadhna. May your sadhna bring peace and devotion.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: const Color(0xFF1A1A1A), // Explicit dark color
            ),
          ),
        ],
      ),
    );
  }
}