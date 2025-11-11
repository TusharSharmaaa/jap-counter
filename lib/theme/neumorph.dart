import 'package:flutter/material.dart';

class Neo {
  static BoxDecoration card(BuildContext context) {
    final surface = Theme.of(context).colorScheme.surface;
    return BoxDecoration(
      color: surface,
      borderRadius: BorderRadius.circular(16),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.06),
          blurRadius: 14,
          offset: const Offset(0, 6),
        ),
        BoxShadow(
          color: Colors.white.withValues(alpha: 0.75),
          blurRadius: 8,
          offset: const Offset(-3, -3),
          blurStyle: BlurStyle.inner,
        ),
      ],
      border: Border.all(
        color: Theme.of(context).dividerColor.withValues(alpha: 0.5),
      ),
    );
  }

  static BoxDecoration pill(BuildContext context) {
    final surface = Theme.of(context).colorScheme.surface;
    return BoxDecoration(
      color: surface,
      borderRadius: BorderRadius.circular(30),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.06),
          blurRadius: 12,
          offset: const Offset(0, 5),
        ),
        BoxShadow(
          color: Colors.white.withValues(alpha: 0.6),
          blurRadius: 6,
          offset: const Offset(-2, -2),
          blurStyle: BlurStyle.inner,
        ),
      ],
      border: Border.all(
        color: Theme.of(context).dividerColor.withValues(alpha: 0.5),
      ),
    );
  }
}

