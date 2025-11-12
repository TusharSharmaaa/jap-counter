import 'dart:convert';
import 'package:http/http.dart' as http;

class GitaVerse {
  final int chapter;
  final int verse;
  final String sanskrit; // "slok"
  final String hindi;    // Tejomayananda Hindi ("tej.ht")

  GitaVerse({
    required this.chapter,
    required this.verse,
    required this.sanskrit,
    required this.hindi,
  });

  factory GitaVerse.fromJson(Map<String, dynamic> json) {
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

  /// Simple in-memory cache: { "<ch>-<vs>": GitaVerse }
  static final Map<String, GitaVerse> _cache = {};

  static String _key(int ch, int vs) => '$ch-$vs';

  static Future<GitaVerse?> fetchVerse(int chapter, int verse) async {
    final k = _key(chapter, verse);

    // 1) Serve from memory cache if available
    final cached = _cache[k];
    if (cached != null) return cached;

    // 2) Fetch from API
    try {
      final url = Uri.parse('$_base/slok/$chapter/$verse');
      final res = await http.get(url);
      if (res.statusCode == 200) {
        final data = json.decode(res.body) as Map<String, dynamic>;
        final v = GitaVerse.fromJson(data);
        _cache[k] = v; // 3) Save to cache
        return v;
      }
    } catch (_) {}
    return null;
  }

  /// Optional: prefetch next verse (non-blocking, ignore errors)
  static Future<void> prefetch(int chapter, int verse) async {
    try {
      await fetchVerse(chapter, verse);
    } catch (_) {
      // Silently ignore prefetch errors
    }
  }
}
