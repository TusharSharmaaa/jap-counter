import 'package:flutter/material.dart';

class PrivacyPolicyPage extends StatelessWidget {
  const PrivacyPolicyPage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    
    // Theme-aware text colors
    final titleColor = colorScheme.onSurface;
    final bodyColor = colorScheme.onSurface;
    final subtitleColor = colorScheme.onSurfaceVariant;
    
    return Scaffold(
      appBar: AppBar(title: const Text('Privacy Policy')),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        children: [
          // Title
          Text(
            'Privacy Policy',
            style: theme.textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.bold,
              fontSize: 28,
              color: titleColor,
              height: 1.2,
            ),
          ),
          const SizedBox(height: 8),
          
          // Effective Date
          Text(
            'Effective Date: 20 Nov, 2025',
            style: theme.textTheme.bodyMedium?.copyWith(
              fontSize: 14,
              color: subtitleColor,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 32),
          
          // Introduction
          Text(
            'Naam Jap Counter : Sadhna respects your privacy. This privacy policy explains how we handle your data.',
            style: theme.textTheme.bodyLarge?.copyWith(
              fontSize: 16,
              color: bodyColor,
              height: 1.6,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 32),
          
          // Privacy Policy Items
          _buildPrivacyItem(
            context: context,
            number: '1',
            title: 'Data Collection',
            content: 'This app stores your jap counts, meditation minutes, and preferences locally on your device. We do not collect personal information like name, email, or phone number.',
            titleColor: titleColor,
            bodyColor: bodyColor,
          ),
          const SizedBox(height: 20),
          
          _buildPrivacyItem(
            context: context,
            number: '2',
            title: 'Advertising',
            content: 'This app uses Google AdMob to show test/production ads. AdMob may collect device identifiers and performance data as per Google\'s policies.',
            titleColor: titleColor,
            bodyColor: bodyColor,
          ),
          const SizedBox(height: 20),
          
          _buildPrivacyItem(
            context: context,
            number: '3',
            title: 'Permissions',
            content: 'Notifications are used to remind you at 7 AM, 12 PM, and 6 PM. You can disable reminders in Settings.',
            titleColor: titleColor,
            bodyColor: bodyColor,
          ),
          const SizedBox(height: 20),
          
          _buildPrivacyItem(
            context: context,
            number: '4',
            title: 'Data Storage',
            content: 'Jap counts and settings are stored locally (SharedPreferences). Optional cloud features may be added later; you will be informed and can opt out.',
            titleColor: titleColor,
            bodyColor: bodyColor,
          ),
          const SizedBox(height: 20),
          
          _buildPrivacyItem(
            context: context,
            number: '5',
            title: 'Contact',
            content: 'For any concerns, you may leave a review on the Play Store. We do not collect or display an email address in the app.',
            titleColor: titleColor,
            bodyColor: bodyColor,
          ),
          const SizedBox(height: 20),
          
          _buildPrivacyItem(
            context: context,
            number: '6',
            title: 'Policy Updates',
            content: 'We may update this policy as features evolve. Continued use of the app means you accept the updated policy.',
            titleColor: titleColor,
            bodyColor: bodyColor,
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
  
  Widget _buildPrivacyItem({
    required BuildContext context,
    required String number,
    required String title,
    required String content,
    required Color titleColor,
    required Color bodyColor,
  }) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Number badge
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: theme.colorScheme.primary.withValues(alpha: 0.15),
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: Text(
            number,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: theme.colorScheme.primary,
              fontSize: 16,
            ),
          ),
        ),
        const SizedBox(width: 16),
        // Content
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  fontSize: 17,
                  color: titleColor,
                  height: 1.3,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                content,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontSize: 15,
                  color: bodyColor,
                  height: 1.6,
                  letterSpacing: 0.2,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}