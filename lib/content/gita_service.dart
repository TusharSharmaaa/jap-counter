import 'dart:convert';
import 'package:http/http.dart' as http;

class GitaVerse {
  final int chapter;
  final int verse;
  final String sanskrit; // "slok"
  final String hindi;    // choose Tejomayananda's Hindi ("tej.ht")

  GitaVerse({
    required this.chapter,
    required this.verse,
    required this.sanskrit,
    required this.hindi,
  });

  factory GitaVerse.fromJson(Map<String, dynamic> json) {
    // API shape per https://vedicscriptures.github.io/slok/1/1
    // keys: chapter, verse, slok, transliteration, and multiple translators (tej, siva, etc.)
    final Map<String, dynamic>? tej = json['tej'] as Map<String, dynamic>?;
    final String hindi = (tej?['ht'] as String?)?.trim() ?? '';

    return GitaVerse(
      chapter: (json['chapter'] as num?)?.toInt() ?? 1,
      verse: (json['verse'] as num?)?.toInt() ?? 1,
      sanskrit: (json['slok'] as String?)?.trim() ?? '',
      hindi: hindi,
    );
  }
}

class GitaService {
  static const String _base = 'https://vedicscriptures.github.io';

  static Future<GitaVerse?> fetchVerse(int chapter, int verse) async {
    try {
      final url = Uri.parse('$_base/slok/$chapter/$verse');
      final res = await http.get(url);
      if (res.statusCode == 200) {
        final data = json.decode(res.body) as Map<String, dynamic>;
        return GitaVerse.fromJson(data);
      }
    } catch (_) {}
    return null;
  }
}
