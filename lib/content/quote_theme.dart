import 'package:flutter/material.dart';

class QuoteTheme {
  final String id;
  final String name;
  final LinearGradient background;
  final Color textColor;
  final Color accentColor;
  final Color badgeColor;

  const QuoteTheme({
    required this.id,
    required this.name,
    required this.background,
    required this.textColor,
    required this.accentColor,
    required this.badgeColor,
  });

  static List<QuoteTheme> presets() {
    return const [
      QuoteTheme(
        id: 'dawn',
        name: 'Dawn',
        background: LinearGradient(
          colors: [Color(0xFFFFF4E0), Color(0xFFFFD7C2)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        textColor: Color(0xFF4A3427),
        accentColor: Color(0xFFFF8A65),
        badgeColor: Color(0xFFFFB74D),
      ),
      QuoteTheme(
        id: 'lotus',
        name: 'Lotus',
        background: LinearGradient(
          colors: [Color(0xFFFCE4EC), Color(0xFFF8BBD0)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
        textColor: Color(0xFF5D275D),
        accentColor: Color(0xFFE91E63),
        badgeColor: Color(0xFFBA68C8),
      ),
      QuoteTheme(
        id: 'river',
        name: 'River',
        background: LinearGradient(
          colors: [Color(0xFFE0F7FA), Color(0xFFB2EBF2)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        textColor: Color(0xFF004D40),
        accentColor: Color(0xFF00BCD4),
        badgeColor: Color(0xFF4DB6AC),
      ),
      QuoteTheme(
        id: 'ember',
        name: 'Ember',
        background: LinearGradient(
          colors: [Color(0xFFFFE3E0), Color(0xFFFFC9B6)],
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
        ),
        textColor: Color(0xFF5D4037),
        accentColor: Color(0xFFFF7043),
        badgeColor: Color(0xFFFFA270),
      ),
    ];
  }
}

