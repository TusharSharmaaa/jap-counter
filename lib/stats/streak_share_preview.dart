import 'package:flutter/material.dart';

class StreakSharePreviewPage extends StatelessWidget {
  final int todayJaps;
  final int lifetimeMalas;
  final int streakDays; // placeholder for now

  const StreakSharePreviewPage({
    super.key,
    required this.todayJaps,
    required this.lifetimeMalas,
    required this.streakDays,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Share My Streak")),
      body: Center(
        child: Container(
          width: 320,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Theme.of(context).dividerColor),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text("Radha Jap Counter",
                  style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              Text("🌸 जप की ये लड़ी कभी टूटे ना 🌸",
                  textAlign: TextAlign.center),
              const SizedBox(height: 12),
              Text("Today’s Japs: $todayJaps"),
              Text("Lifetime Malas: $lifetimeMalas"),
              Text("Streak: $streakDays days"),
              const SizedBox(height: 16),
              const Text(
                "Preview only — image export & WhatsApp share coming next",
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
