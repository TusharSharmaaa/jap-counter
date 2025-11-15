import 'package:flutter/material.dart';

class TermsConditionsPage extends StatelessWidget {
  const TermsConditionsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    
    // Theme-aware text colors
    final titleColor = colorScheme.onSurface;
    final bodyColor = colorScheme.onSurface;
    final subtitleColor = colorScheme.onSurfaceVariant;
    
    return Scaffold(
      appBar: AppBar(title: const Text('Terms & Conditions')),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        children: [
          // Title
          Text(
            'Terms & Conditions',
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
            'By using the Naam Jap Counter : Sadhna app, you agree to the following terms and conditions.',
            style: theme.textTheme.bodyLarge?.copyWith(
              fontSize: 16,
              color: bodyColor,
              height: 1.6,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 32),
          
          // Terms
          _buildTermItem(
            context: context,
            number: '1',
            title: 'Purpose',
            content: 'The app is designed to assist in devotional jap counting and meditation reminders. It is a spiritual utility, not a commercial service.',
            titleColor: titleColor,
            bodyColor: bodyColor,
          ),
          const SizedBox(height: 20),
          
          _buildTermItem(
            context: context,
            number: '2',
            title: 'Usage',
            content: 'You may use the app freely for personal spiritual practice. Commercial use, reselling, or modification for redistribution is prohibited.',
            titleColor: titleColor,
            bodyColor: bodyColor,
          ),
          const SizedBox(height: 20),
          
          _buildTermItem(
            context: context,
            number: '3',
            title: 'Data',
            content: 'All your jap counts, meditation minutes, and settings are stored locally on your device. We do not access, share, or upload your data.',
            titleColor: titleColor,
            bodyColor: bodyColor,
          ),
          const SizedBox(height: 20),
          
          _buildTermItem(
            context: context,
            number: '4',
            title: 'Advertising',
            content: 'The app may display Google AdMob ads. These are used ethically to support app development. Ad behavior and targeting are controlled by Google.',
            titleColor: titleColor,
            bodyColor: bodyColor,
          ),
          const SizedBox(height: 20),
          
          _buildTermItem(
            context: context,
            number: '5',
            title: 'Liability',
            content: 'We are not responsible for any device issues, missed notifications, or data loss arising from app use.',
            titleColor: titleColor,
            bodyColor: bodyColor,
          ),
          const SizedBox(height: 20),
          
          _buildTermItem(
            context: context,
            number: '6',
            title: 'Updates',
            content: 'App features and terms may change over time. Continued use signifies acceptance of the updated terms.',
            titleColor: titleColor,
            bodyColor: bodyColor,
          ),
          const SizedBox(height: 20),
          
          _buildTermItem(
            context: context,
            number: '7',
            title: 'Contact',
            content: 'For feedback or concerns, you may contact us via the Play Store listing.',
            titleColor: titleColor,
            bodyColor: bodyColor,
          ),
          const SizedBox(height: 32),
          
          // Closing message
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: colorScheme.primary.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              'Thank you for using Naam Jap Counter : Sadhna. May your sadhna bring peace and devotion.',
              style: theme.textTheme.bodyMedium?.copyWith(
                fontSize: 15,
                color: bodyColor,
                height: 1.6,
                fontStyle: FontStyle.italic,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildTermItem({
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
            color: theme.colorScheme.primary.withOpacity(0.15),
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