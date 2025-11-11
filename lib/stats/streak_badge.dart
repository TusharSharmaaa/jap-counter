import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';

class StreakBadge extends StatelessWidget {
  final int streakDays;

  const StreakBadge({super.key, required this.streakDays});

  @override
  Widget build(BuildContext context) {
    final (labelKey, color) = _badgeFor(streakDays);
    return Chip(
      label: Text(
        context.tr(labelKey),
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w600,
        ),
      ),
      backgroundColor: color,
      avatar: const Icon(
        Icons.local_fire_department,
        color: Colors.white,
        size: 18,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
  }

  (String, Color) _badgeFor(int days) {
    if (days >= 40) return ('badge.platinum', Colors.deepPurple);
    if (days >= 21) return ('badge.gold', Colors.amber.shade700);
    if (days >= 7) return ('badge.silver', Colors.blueGrey);
    if (days >= 3) return ('badge.bronze', Colors.brown);
    return ('badge.new', Colors.grey);
  }
}
