import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/quote_image_generator.dart';

// Ads + API
import 'package:jap_counter/ads/test_native.dart';
import 'package:jap_counter/content/gita_service.dart';

class ContentPage extends StatefulWidget {
  const ContentPage({super.key});

  @override
  State<ContentPage> createState() => _ContentPageState();
}

class _ContentPageState extends State<ContentPage> with TickerProviderStateMixin {
  static const _quotesPrefKey = 'content.daily_quotes';

  late final TabController _tabs;

  // ---------------- QUOTES STATE ----------------
  int _quoteIndex = 0;
  final List<String> _quotes = [
    "ख़ामोशी में ही सबसे गहरी प्रार्थना होती है।",
    "जप की डोरी पकड़ लो, मन अपने आप शांत हो जाएगा।",
    "जो मिला है, वही प्रभु का प्रसाद है — कृतज्ञ रहो।",
    "हर साँस में राधा-नाम, हर क्षण में माधुर्य।",
    "चलते-फिरते, उठते-बैठते — जप रुकना नहीं चाहिए।",
  ];

  // ---------------- GITA STATE ----------------
  final int _chapter = 1;
  int _verse = 1;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    _loadLocalQuotes();
    _maybeRefreshFromFirebase();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  // -------- QUOTES HELPERS --------
  String get _currentQuote => _quotes.isEmpty
      ? 'साधना की शुरुआत अभी भी सुंदर है।'
      : _quotes[_quoteIndex % _quotes.length];

  void _prevQuote() {
    if (_quotes.isEmpty) return;
    setState(() => _quoteIndex = (_quoteIndex - 1) < 0 ? _quotes.length - 1 : _quoteIndex - 1);
  }

  void _nextQuote() {
    if (_quotes.isEmpty) return;
    setState(() => _quoteIndex = (_quoteIndex + 1) % _quotes.length);
  }

  Future<void> _shareQuote() async {
    final text = "🌸 $_currentQuote\n— Radha Jap Counter";
    await SharePlus.instance.share(
      ShareParams(text: text),
    );
  }

  Future<void> _shareQuoteImage(String quote, String reference) async {
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    const size = ui.Size(1080, 1080);

    final background = ui.Paint()..color = const Color(0xFFFFF8E1);
    canvas.drawRect(ui.Offset.zero & size, background);

    final quotePainter = TextPainter(
      text: TextSpan(
        text: quote,
        style: const TextStyle(
          fontSize: 44,
          color: Colors.black87,
          height: 1.5,
          fontFamily: 'NotoSansDevanagari',
        ),
      ),
      textDirection: TextDirection.ltr,
    )
      ..layout(maxWidth: size.width - 160);
    quotePainter.paint(canvas, const ui.Offset(80, 260));

    final refPainter = TextPainter(
      text: TextSpan(
        text: reference,
        style: const TextStyle(fontSize: 36, color: Colors.black54),
      ),
      textDirection: TextDirection.ltr,
    )
      ..layout(maxWidth: size.width - 160);
    refPainter.paint(canvas, const ui.Offset(80, 920));

    final footerPainter = TextPainter(
      text: const TextSpan(
        text: 'Radha Jap Counter',
        style: TextStyle(fontSize: 34, color: Colors.brown, fontWeight: FontWeight.w600),
      ),
      textDirection: TextDirection.ltr,
    )
      ..layout();
    footerPainter.paint(canvas, const ui.Offset(80, 980));

    final picture = recorder.endRecording();
    final image = await picture.toImage(size.width.toInt(), size.height.toInt());
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    final pngBytes = byteData!.buffer.asUint8List();

    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/gita_quote_${DateTime.now().millisecondsSinceEpoch}.png');
    await file.writeAsBytes(pngBytes);

    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path)],
        text: '📖 श्रीमद् भगवद् गीता से प्रेरणा',
      ),
    );
  }
  Future<void> _loadLocalQuotes() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getStringList(_quotesPrefKey);
    if (stored != null && stored.isNotEmpty) {
      setState(() {
        _quotes
          ..clear()
          ..addAll(stored);
        _quoteIndex = 0;
      });
    }
  }

  Future<void> _maybeRefreshFromFirebase() async {
    final conn = await Connectivity().checkConnectivity();
    final hasConnection = conn.any((result) => result != ConnectivityResult.none);
    if (!hasConnection) return;
    try {
      final snap = await FirebaseFirestore.instance.collection('daily_quotes').limit(10).get();
      for (final doc in snap.docs) {
        await _saveQuoteLocally(doc.data());
      }
      await _loadLocalQuotes();
      if (kDebugMode) {
        debugPrint('[Content] Quotes refreshed from Firebase');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[Content] Firebase refresh failed: $e');
      }
    }
  }

  Future<void> _saveQuoteLocally(Map<String, dynamic> data) async {
    final prefs = await SharedPreferences.getInstance();
    final text = (data['text'] ?? data['quote'] ?? data['message'] ?? '').toString().trim();
    if (text.isEmpty) return;
    final current = prefs.getStringList(_quotesPrefKey) ?? <String>[];
    if (!current.contains(text)) {
      current.insert(0, text);
      if (current.length > 20) {
        current.removeRange(20, current.length);
      }
      await prefs.setStringList(_quotesPrefKey, current);
    }
  }

  // -------- GITA HELPERS (cached service + prefetch) --------
  Future<GitaVerse?> _fetchCurrentVerse() {
    return GitaService.fetchVerse(_chapter, _verse);
  }

  void _prefetchNext() {
    // naive prefetch: next verse in same chapter
    GitaService.prefetch(_chapter, _verse + 1);
  }

  void _prevVerse() {
    setState(() {
      if (_verse > 1) {
        _verse--;
      } else {
        _verse = 1; // later: roll to previous chapter's last verse
      }
    });
  }

  void _nextVerse() {
    setState(() {
      _verse++; // later: add bounds + chapter roll
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Content"),
        bottom: TabBar(
          controller: _tabs,
          tabs: const [
            Tab(text: "Quotes"),
            Tab(text: "Gita"),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          // ================= QUOTES TAB =================
          Column(
            children: [
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Theme.of(context).dividerColor),
                  ),
                  child: Text(
                    _currentQuote,
                    style: Theme.of(context).textTheme.titleMedium,
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _prevQuote,
                        icon: const Icon(Icons.chevron_left),
                        label: const Text("Previous"),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _nextQuote,
                        icon: const Icon(Icons.chevron_right),
                        label: const Text("Next"),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: SizedBox(
                  width: double.infinity,
                  height: 44,
                  child: FilledButton.icon(
                    onPressed: _shareQuote,
                    icon: const Icon(Icons.share),
                    label: const Text("Share on WhatsApp"),
                  ),
                ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    icon: const Icon(Icons.image),
                    tooltip: 'Share as Image',
                    onPressed: () async {
                      final path = await QuoteImageGenerator.generate(_currentQuote);
                      await Share.shareXFiles(
                        [XFile(path)],
                        text: 'Radha Jap Counter से आज का प्रेरक संदेश 🌸',
                      );
                    },
                  ),
                ],
              ),
              const SizedBox(height: 16),
              // Native Ad below quotes
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: const TestNativeAd(),
                ),
              ),
            ],
          ),

          // ================= GITA TAB (LIVE + CACHED) =================
          FutureBuilder<GitaVerse?>(
            future: _fetchCurrentVerse(),
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return const _VerseSkeleton(); // smoother than spinner
              }
              if (!snap.hasData || snap.data == null) {
                return Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text("Unable to load verse."),
                      const SizedBox(height: 12),
                      SizedBox(
                        height: 44,
                        child: OutlinedButton.icon(
                          onPressed: () => setState(() {}), // retry
                          icon: const Icon(Icons.refresh),
                          label: const Text("Retry"),
                        ),
                      ),
                    ],
                  ),
                );
              }

              final v = snap.data!;
              _prefetchNext(); // warm the next verse

              return ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Text(
                    "अध्याय ${v.chapter}, श्लोक ${v.verse}",
                    style: Theme.of(context).textTheme.titleMedium,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    v.sanskrit,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    v.hindi,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _prevVerse,
                          icon: const Icon(Icons.chevron_left),
                          label: const Text("Previous"),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _nextVerse,
                          icon: const Icon(Icons.chevron_right),
                          label: const Text("Next"),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    height: 44,
                    child: FilledButton.icon(
                      onPressed: () async {
                        await SharePlus.instance.share(
                          ShareParams(
                            text: "अध्याय ${v.chapter}, श्लोक ${v.verse} — Radha Jap Counter",
                          ),
                        );
                      },
                      icon: const Icon(Icons.share),
                      label: const Text("Share"),
                    ),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.image),
                        tooltip: 'Share as Image',
                        onPressed: () async {
                          final reference = "अध्याय ${v.chapter}, श्लोक ${v.verse}";
                          await _shareQuoteImage(v.hindi, reference);
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const _NativeAdReserve(), // keep a slot here too (optional)
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _NativeAdReserve extends StatelessWidget {
  const _NativeAdReserve();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 140,
      width: double.infinity,
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: const Center(child: Text("Native Ad (reserved)")),
    );
  }
}

class _VerseSkeleton extends StatelessWidget {
  const _VerseSkeleton();

  @override
  Widget build(BuildContext context) {
    Widget bar(double h) => Container(
      height: h,
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(8),
      ),
    );

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          bar(18),
          const SizedBox(height: 8),
          bar(80),
          bar(80),
          const SizedBox(height: 8),
          bar(60),
        ],
      ),
    );
  }
}
