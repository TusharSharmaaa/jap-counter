import 'dart:async';
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart';

import '../core/app_constants.dart';
import '../data/activity_store.dart';
import '../data/counter_store.dart';

class WeeklyChartData {
  // Cache for chart data to improve performance
  static List<Map<String, dynamic>>? _cachedChartData;
  static DateTime? _cachedChartDate;
  static int? _cachedTodayJaps;
  
  // Cache DateFormat instances - will be initialized with locale when needed
  static DateFormat? _dateFormat;
  static DateFormat? _dayFormat;
  static DateFormat? _dateLabelFormat;
  static String? _lastLocale;
  
  // Debounce timer for cache invalidation to avoid excessive invalidations
  static Timer? _invalidationTimer;

  // Initialize date formats with locale
  static Future<void> _initializeFormats(String locale) async {
    if (_lastLocale == locale && _dateFormat != null) return;
    
    // Initialize locale data before using DateFormat with locale
    try {
      await initializeDateFormatting(locale);
    } catch (e) {
      // If locale initialization fails, try with default locale
      try {
        await initializeDateFormatting('en');
        locale = 'en'; // Fallback to English
      } catch (_) {
        // If even English fails, use default (no locale)
        locale = 'en';
      }
    }
    
    _dateFormat = DateFormat('yyyy-MM-dd', locale);
    _dayFormat = DateFormat('E', locale); // Short day name (Mon, Tue, etc.)
    _dateLabelFormat = DateFormat('d', locale); // Day of month
    _lastLocale = locale;
  }

  static Future<List<Map<String, dynamic>>> build({String locale = 'en'}) async {
    // Initialize formats with locale (default to 'en' if not provided)
    await _initializeFormats(locale);
    
    final today = DateTime.now();
    // Normalize to start of day for consistent comparison (strip time)
    final todayNormalized = DateTime(today.year, today.month, today.day);
    final todayKey = _dateFormat!.format(todayNormalized);
    
    final counter = await CounterStore.create();
    final todayJaps = counter.todayJaps;
    final todayMalasLive = todayJaps ~/ AppConstants.japsPerMala;
    
    // Check cache - invalidate if day changed, counter changed, or locale changed
    // Compare dates by day/month/year directly instead of using DateFormat to avoid locale issues
    if (_cachedChartData != null && 
        _cachedChartDate != null &&
        _cachedChartDate!.year == todayNormalized.year &&
        _cachedChartDate!.month == todayNormalized.month &&
        _cachedChartDate!.day == todayNormalized.day &&
        _cachedTodayJaps == todayJaps &&
        _lastLocale == locale) {
      return _cachedChartData!;
    }
    
    final history = await ActivityStore.getDailyHistory();
    final out = <Map<String, dynamic>>[];

    // Generate dates for last 7 days (including today)
    // i=0: 6 days ago, i=1: 5 days ago, ..., i=6: today
    for (int i = 0; i < 7; i++) {
      final date = todayNormalized.subtract(Duration(days: 6 - i));
      final dateNormalized = DateTime(date.year, date.month, date.day);
      final key = _dateFormat!.format(dateNormalized);
      final entry = history[key];
      
      var malas = switch (entry) {
        Map<String, dynamic> m => (m['malas'] as num?)?.round() ?? 0,
        _ => 0,
      };
      
      // Use live counter data for today if available
      final isToday = dateNormalized.year == todayNormalized.year &&
          dateNormalized.month == todayNormalized.month &&
          dateNormalized.day == todayNormalized.day;
      
      if (isToday) {
        // Always use live counter for today
        malas = todayMalasLive;
      }

      out.add({
        'day': _dayFormat!.format(dateNormalized),
        'dateLabel': _dateLabelFormat!.format(dateNormalized),
        'value': malas < 0 ? 0 : malas,
      });
    }

    // Cache the result
    _cachedChartData = out;
    _cachedChartDate = todayNormalized;
    _cachedTodayJaps = todayJaps;
    return out;
  }
  
  /// Invalidate chart cache (call when counter increments or day changes).
  /// Uses debouncing to avoid excessive invalidations on rapid taps.
  static void invalidateCache() {
    // Cancel existing timer
    _invalidationTimer?.cancel();
    
    // Schedule invalidation after debounce delay
    _invalidationTimer = Timer(
      const Duration(milliseconds: AppConstants.chartCacheDebounceMs),
      () {
        _cachedChartData = null;
        _cachedChartDate = null;
        _cachedTodayJaps = null;
        // Keep format instances but reset locale tracking
        _lastLocale = null;
      },
    );
  }
  
  /// Force immediate cache invalidation (no debouncing).
  /// Use when day changes or explicit refresh is needed.
  static void invalidateCacheImmediate() {
    _invalidationTimer?.cancel();
    _invalidationTimer = null;
    _cachedChartData = null;
    _cachedChartDate = null;
    _cachedTodayJaps = null;
    _lastLocale = null;
  }
}
