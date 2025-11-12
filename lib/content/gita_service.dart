import 'dart:collection';
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

  /// LRU in-memory cache using LinkedHashMap for O(1) operations
  static final LinkedHashMap<String, GitaVerse> _cache = LinkedHashMap();

  static String _key(int ch, int vs) => '$ch-$vs';

  static Future<GitaVerse?> fetchVerse(int chapter, int verse) async {
    final k = _key(chapter, verse);

    // 1) Serve from memory cache if available (LRU: move to end - O(1) operation)
    final cached = _cache.remove(k); // O(1) remove from middle
    if (cached != null) {
      _cache[k] = cached; // O(1) add to end (moves to end for LRU)
      return cached;
    }

    // 2) Fetch from API
    try {
      final url = Uri.parse('$_base/slok/$chapter/$verse');
      final res = await http.get(url);
      if (res.statusCode == 200) {
        final data = json.decode(res.body) as Map<String, dynamic>;
        final v = GitaVerse.fromJson(data);
        
        // 3) Add to cache with size limit (LRU eviction - O(1) operation)
        if (_cache.length >= _maxCacheSize) {
          _cache.remove(_cache.keys.first); // O(1) remove oldest
        }
        _cache[k] = v; // O(1) add to end
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
          return null;
        });
      }
    }
  }
}
