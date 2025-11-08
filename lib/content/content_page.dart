import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:share_plus/share_plus.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/quote_image_generator.dart';
import 'quote_theme.dart';

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
  late final PageController _quoteController;
  late final List<QuoteTheme> _themes;
  int _selectedThemeIndex = 0;
  final TextEditingController _noteController = TextEditingController();

  // ---------------- GITA STATE ----------------
  final int _chapter = 1;
  int _verse = 1;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    _quoteController = PageController(viewportFraction: 0.88);
    _themes = QuoteTheme.presets();
    _loadLocalQuotes();
    _maybeRefreshFromFirebase();
  }

  @override
  void dispose() {
    _tabs.dispose();
    _quoteController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  // -------- QUOTES HELPERS --------
  String get _currentQuote => _quotes.isEmpty
      ? 'साधना की शुरुआत अभी भी सुंदर है।'
      : _quotes[_quoteIndex % _quotes.length];

  String get _currentShareLink =>
      'https://play.google.com/store/apps/details?id=com.example.jap_counter';

  void _prevQuote() {
    if (_quotes.isEmpty) return;
    final target = (_quoteIndex - 1) < 0 ? _quotes.length - 1 : _quoteIndex - 1;
    _quoteController.animateToPage(
      target,
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeInOut,
    );
  }

  void _nextQuote() {
    if (_quotes.isEmpty) return;
    final target = (_quoteIndex + 1) % _quotes.length;
    _quoteController.animateToPage(
      target,
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeInOut,
    );
  }

  Future<void> _shareQuoteText({String? note, bool includeLink = true}) async {
    final buffer = StringBuffer('🌸 $_currentQuote');
    if (note != null && note.trim().isNotEmpty) {
      buffer.writeln('\n$note');
    }
    buffer.writeln('\n— Radha Jap Counter');
    if (includeLink) {
      buffer.writeln('\n$_currentShareLink');
    }
    await SharePlus.instance.share(ShareParams(text: buffer.toString()));
  }

  Future<void> _shareQuoteImage({
    required QuoteTheme theme,
    String? note,
    bool includeLink = true,
  }) async {
    final path = await QuoteImageGenerator.generate(
      _currentQuote,
      theme: theme,
      note: note,
      includeLink: includeLink,
      shareLink: _currentShareLink,
    );
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(path)],
        text: '${note != null && note.trim().isNotEmpty ? '$note\n\n' : ''}${_currentShareLink}',
      ),
    );
  }

  Future<void> _saveQuoteImage({
    required QuoteTheme theme,
    String? note,
    bool includeLink = true,
  }) async {
    final path = await QuoteImageGenerator.generate(
      _currentQuote,
      theme: theme,
      note: note,
      includeLink: includeLink,
      shareLink: _currentShareLink,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Saved share card to $path'),
        action: SnackBarAction(
          label: 'Share',
          onPressed: () => SharePlus.instance.share(ShareParams(files: [XFile(path)])),
        ),
      ),
    );
  }

  void _copyQuoteToClipboard() {
    Clipboard.setData(ClipboardData(text: _currentQuote));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Quote copied to clipboard')),
    );
  }

  void _openShareSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      builder: (ctx) {
        int themeIndex = _selectedThemeIndex;
        bool includeLink = true;
        final controller = TextEditingController(text: _noteController.text);
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 24,
                bottom: MediaQuery.of(context).viewInsets.bottom + 24,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Customize Share Card',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 42,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: _themes.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 8),
                      itemBuilder: (context, index) {
                        final theme = _themes[index];
                        final selected = themeIndex == index;
                        return ChoiceChip(
                          label: Text(theme.name),
                          selected: selected,
                          onSelected: (_) {
                            setModalState(() => themeIndex = index);
                          },
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: controller,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: 'Add a personal note (optional)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: includeLink,
                    onChanged: (value) => setModalState(() => includeLink = value),
                    title: const Text('Include Play Store link'),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: () async {
                            Navigator.pop(context);
                            _selectedThemeIndex = themeIndex;
                            _noteController.text = controller.text;
                            await _shareQuoteImage(
                              theme: _themes[themeIndex],
                              note: controller.text.trim().isEmpty ? null : controller.text.trim(),
                              includeLink: includeLink,
                            );
                          },
                          icon: const Icon(Icons.image),
                          label: const Text('Share as Image'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () async {
                            Navigator.pop(context);
                            _selectedThemeIndex = themeIndex;
                            _noteController.text = controller.text;
                            await _shareQuoteText(
                              note: controller.text.trim().isEmpty ? null : controller.text.trim(),
                              includeLink: includeLink,
                            );
                          },
                          icon: const Icon(Icons.text_fields),
                          label: const Text('Share as Text'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        tooltip: 'Save Image',
                        onPressed: () async {
                          _selectedThemeIndex = themeIndex;
                          _noteController.text = controller.text;
                          await _saveQuoteImage(
                            theme: _themes[themeIndex],
                            note: controller.text.trim().isEmpty ? null : controller.text.trim(),
                            includeLink: includeLink,
                          );
                        },
                        icon: const Icon(Icons.download),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
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
        backgroundColor: Colors.transparent,
        elevation: 0,
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                Theme.of(context).colorScheme.primary.withOpacity(0.3),
                Colors.transparent,
              ],
            ),
          ),
        ),
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
          LayoutBuilder(
            builder: (context, constraints) {
              final safeTop = 16.0;
              final availableHeight = constraints.maxHeight - safeTop - 220;
              final cardHeight = availableHeight.clamp(220.0, 320.0);
              return Column(
                children: [
                  SizedBox(
                    height: cardHeight,
                    child: PageView.builder(
                  controller: _quoteController,
                  itemCount: _quotes.isEmpty ? 1 : _quotes.length,
                  onPageChanged: (index) {
                    setState(() => _quoteIndex = _quotes.isEmpty ? 0 : index % _quotes.length);
                  },
                  itemBuilder: (context, index) {
                    final quote = _quotes.isEmpty ? _currentQuote : _quotes[index % _quotes.length];
                    return Align(
                      alignment: Alignment.topCenter,
                      child: _QuotePreviewCard(
                        quote: quote,
                        theme: _themes[_selectedThemeIndex],
                      ),
                    );
                  },
                ),
              ),
                  if (_quotes.length > 1)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: List.generate(_quotes.length, (i) {
                          final active = i == (_quoteIndex % _quotes.length);
                          return AnimatedContainer(
                            duration: const Duration(milliseconds: 250),
                            margin: const EdgeInsets.symmetric(horizontal: 4),
                            width: active ? 12 : 8,
                            height: active ? 12 : 8,
                            decoration: BoxDecoration(
                              color: active
                                  ? Theme.of(context).colorScheme.primary
                                  : Theme.of(context).colorScheme.primary.withOpacity(0.3),
                              shape: BoxShape.circle,
                            ),
                          );
                        }),
                      ),
                    ),
                  const SizedBox(height: 20),
                  SizedBox(
                    height: 42,
                    child: ListView.separated(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      scrollDirection: Axis.horizontal,
                      itemCount: _themes.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 8),
                      itemBuilder: (context, index) {
                        final theme = _themes[index];
                        final selected = index == _selectedThemeIndex;
                        return ChoiceChip(
                          label: Text(theme.name),
                          selected: selected,
                          onSelected: (_) {
                            setState(() => _selectedThemeIndex = index);
                          },
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 16),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: FilledButton.icon(
                        onPressed: _openShareSheet,
                        icon: const Icon(Icons.auto_awesome),
                        label: const Text('Create Share Card'),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _copyQuoteToClipboard,
                            icon: const Icon(Icons.copy),
                            label: const Text('Copy'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _nextQuote,
                            icon: const Icon(Icons.refresh),
                            label: const Text('Inspire me'),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Spacer(),
                  const SizedBox(
                    height: 60,
                    child: _BannerReserve(),
                  ),
                ],
              );
            },
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
                          await _shareQuoteImage(
                            theme: _themes[_selectedThemeIndex],
                            note: reference,
                            includeLink: true,
                          );
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const _BannerReserve(),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _BannerReserve extends StatelessWidget {
  const _BannerReserve();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Container(
          height: 60,
          color: Theme.of(context).colorScheme.surfaceVariant,
          alignment: Alignment.center,
          child: Text(
            'Banner Ad (reserved)',
            style: Theme.of(context).textTheme.labelMedium,
          ),
        ),
      ),
    );
  }
}
class _QuotePreviewCard extends StatelessWidget {
  final QuoteTheme theme;
  final String quote;

  const _QuotePreviewCard({
    required this.theme,
    required this.quote,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      decoration: BoxDecoration(
        gradient: theme.background,
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: theme.accentColor.withOpacity(0.2),
            blurRadius: 22,
            spreadRadius: 4,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: Alignment.topRight,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: theme.badgeColor.withOpacity(0.25),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.auto_awesome, size: 16, color: theme.accentColor),
                  const SizedBox(width: 6),
                  Text(
                    theme.name,
                    style: TextStyle(
                      color: theme.textColor.withOpacity(0.75),
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final textStyle = TextStyle(
                      color: theme.textColor,
                      fontSize: constraints.maxHeight < 140 ? 18 : 20,
                      height: 1.4,
                      fontWeight: FontWeight.w600,
                    );
                    final quoteText = quote.length > 90 && constraints.maxHeight < 150
                        ? '${quote.substring(0, 90)}…'
                        : quote;
                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '“',
                          style: TextStyle(
                            color: theme.accentColor,
                            fontSize: 32,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          quoteText,
                          textAlign: TextAlign.center,
                          style: textStyle,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '”',
                          style: TextStyle(
                            color: theme.accentColor,
                            fontSize: 30,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
          Divider(color: theme.textColor.withOpacity(0.15)),
          const SizedBox(height: 4),
          Text(
            'Radha Jap Counter',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: theme.textColor.withOpacity(0.7),
              fontWeight: FontWeight.w600,
              letterSpacing: 0.4,
            ),
          ),
        ],
      ),
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
