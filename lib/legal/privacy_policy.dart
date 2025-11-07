import 'package:flutter/material.dart';

class PrivacyPolicyPage extends StatelessWidget {
  const PrivacyPolicyPage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Privacy Policy')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Privacy Policy', style: theme.textTheme.headlineSmall),
          const SizedBox(height: 12),
          Text(
            'Effective Date: 06-Oct-2025',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          Text(
            'Radha Jap Counter respects your privacy. This app stores your jap counts, meditation minutes, '
                'and preferences locally on your device. We do not collect personal information like name, email, or phone number.',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 12),
          Text(
            'Advertising: This app uses Google AdMob to show test/production ads. AdMob may collect device identifiers and performance data as per Google’s policies.',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 12),
          Text(
            'Permissions: Notifications are used to remind you at 7 AM, 12 PM, and 6 PM. You can disable reminders in Settings.',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 12),
          Text(
            'Data Storage: Jap counts and settings are stored locally (SharedPreferences). Optional cloud features may be added later; you will be informed and can opt out.',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 12),
          Text(
            'Contact: For any concerns, you may leave a review on the Play Store. We do not collect or display an email address in the app.',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          Text(
            'Changes: We may update this policy as features evolve. Continued use of the app means you accept the updated policy.',
            style: theme.textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }
}