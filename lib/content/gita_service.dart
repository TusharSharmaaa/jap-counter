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
  static const int _maxCacheSize = 100;

  /// LRU in-memory cache: { "<ch>-<vs>": GitaVerse }
  static final Map<String, GitaVerse> _cache = {};
  static final List<String> _cacheOrder = [];

  static String _key(int ch, int vs) => '$ch-$vs';

  static Future<GitaVerse?> fetchVerse(int chapter, int verse) async {
    final k = _key(chapter, verse);

    // 1) Serve from memory cache if available (LRU: move to end)
    final cached = _cache[k];
    if (cached != null) {
      _cacheOrder.remove(k);
      _cacheOrder.add(k);
      return cached;
    }

    // 2) Fetch from API
    try {
      final url = Uri.parse('$_base/slok/$chapter/$verse');
      final res = await http.get(url);
      if (res.statusCode == 200) {
        final data = json.decode(res.body) as Map<String, dynamic>;
        final v = GitaVerse.fromJson(data);
        
        // 3) Add to cache with size limit (LRU eviction)
        if (_cache.length >= _maxCacheSize) {
          final oldest = _cacheOrder.removeAt(0);
          _cache.remove(oldest);
        }
        _cache[k] = v;
        _cacheOrder.add(k);
        return v;
      }
    } catch (_) {}
    return null;
  }

  /// Prefetch next N verses in background for better performance.
  /// Non-blocking, ignores errors.
  static Future<void> prefetch(int chapter, int verse, {int count = 3}) async {
    // Prefetch next N verses in background
    for (int i = 1; i <= count; i++) {
      final nextVerse = verse + i;
      // Only prefetch if not already cached
      final key = _key(chapter, nextVerse);
      if (!_cache.containsKey(key)) {
        // Fire and forget - don't await to avoid blocking
        fetchVerse(chapter, nextVerse).catchError((_) {
          // Silently ignore prefetch errors
        });
      }
    }
  }
}
