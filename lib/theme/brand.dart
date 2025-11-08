import 'package:flutter/material.dart';

class BrandGradients {
  static BoxDecoration timerBackground(BuildContext context, {required bool isRunning}) {
    final cs = Theme.of(context).colorScheme;
    return BoxDecoration(
      gradient: RadialGradient(
        center: const Alignment(0, -0.4),
        radius: 1.2,
        colors: isRunning
            ? [cs.primary.withValues(alpha: 0.15), cs.surface]
            : [cs.surface, cs.surface],
      ),
    );
  }

  static LinearGradient shareCard() => const LinearGradient(
        colors: [Color(0xFFFFD54F), Color(0xFFFFB300)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      );
}

