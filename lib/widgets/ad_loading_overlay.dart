import 'package:flutter/material.dart';

/// A minimal overlay shown while loading or preparing an ad.
/// Call [showAdLoadingOverlay] before starting an ad load or rewarded ad show.
void showAdLoadingOverlay(BuildContext context) {
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (_) => const _AdLoadingOverlay(),
  );
}

/// Dismisses the loading overlay if visible.
void hideAdLoadingOverlay(BuildContext context) {
  if (Navigator.of(context, rootNavigator: true).canPop()) {
    Navigator.of(context, rootNavigator: true).pop();
  }
}

class _AdLoadingOverlay extends StatelessWidget {
  const _AdLoadingOverlay();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: const Duration(milliseconds: 220),
      builder: (context, opacity, child) {
        return Opacity(
          opacity: opacity,
          child: Dialog(
            backgroundColor: theme.colorScheme.surface.withValues(alpha: 0.95),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 16),
                  Text(
                    'Preparing Ad…',
                    style: theme.textTheme.titleMedium,
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