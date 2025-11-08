import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'dedication_store.dart';

class StreakSharePreviewPage extends StatefulWidget {
  final int todayJaps;
  final int lifetimeMalas;
  final int streakDays;

  const StreakSharePreviewPage({
    super.key,
    required this.todayJaps,
    required this.lifetimeMalas,
    required this.streakDays,
  });

  @override
  State<StreakSharePreviewPage> createState() => _StreakSharePreviewPageState();
}

class _StreakSharePreviewPageState extends State<StreakSharePreviewPage>
    with SingleTickerProviderStateMixin {
  final GlobalKey _cardKey = GlobalKey();
  bool _sharing = false;
  String? _dedication;
  bool _localeReady = false;
  late final AnimationController _glowCtl;

  @override
  void initState() {
    super.initState();
    _glowCtl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
      lowerBound: 0.0,
      upperBound: 1.0,
    )..repeat(reverse: true);
    _init();
  }

  Future<void> _init() async {
    await initializeDateFormatting('hi_IN');
    await _loadDedication();
    if (mounted) setState(() => _localeReady = true);
  }

  @override
  void dispose() {
    _glowCtl.dispose();
    super.dispose();
  }

  Future<void> _loadDedication() async {
    final d = await DedicationStore.get();
    if (mounted) setState(() => _dedication = d);
  }

  Future<void> _shareCard() async {
    try {
      setState(() => _sharing = true);
      final boundary =
          _cardKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 3.0);
      final byteData = await image.toByteData(format: ImageByteFormat.png);
      final pngBytes = byteData!.buffer.asUint8List();

      final dir = await getTemporaryDirectory();
      final file = File(
        '${dir.path}/streak_share_${DateTime.now().millisecondsSinceEpoch}.png',
      );
      await file.writeAsBytes(pngBytes);

      await Share.shareXFiles(
        [XFile(file.path)],
        text: '🌸 मेरी साधना की झलक — Radha Jap Counter के साथ।',
      );
    } catch (e) {
      if (kDebugMode) debugPrint('[SharePreview] Share failed: $e');
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final now = (_localeReady)
        ? DateFormat('d MMMM yyyy', 'hi_IN').format(DateTime.now())
        : DateFormat.yMMMMd().format(DateTime.now());

    return Scaffold(
      appBar: AppBar(
        title: const Text('Share My Streak'),
        centerTitle: true,
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFFFFE0B2), Color(0xFFFFF3E0)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              RepaintBoundary(
                key: _cardKey,
                child: AnimatedBuilder(
                  animation: _glowCtl,
                  builder: (context, _) {
                    return Container(
                      width: double.infinity,
                      margin: const EdgeInsets.symmetric(horizontal: 20),
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(20),
                        gradient: const LinearGradient(
                          colors: [Color(0xFFFFD54F), Color(0xFFFFB300)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.amber.withOpacity(
                              0.25 + 0.25 * _glowCtl.value,
                            ),
                            blurRadius: 14 + 6 * _glowCtl.value,
                            spreadRadius: 1 + 1 * _glowCtl.value,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '🌸 मेरा साधना सफर 🌸',
                            style: theme.textTheme.headlineSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: Colors.brown.shade800,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            now,
                            style: theme.textTheme.labelLarge?.copyWith(
                              color: Colors.brown.shade700,
                            ),
                          ),
                          const Divider(thickness: 1, height: 24),
                          _statRow('आज के जाप', widget.todayJaps.toString()),
                          _statRow(
                            'जीवन भर के माला',
                            widget.lifetimeMalas.toString(),
                          ),
                          _statRow('अभ्यास के दिन', widget.streakDays.toString()),
                          const SizedBox(height: 16),
                          if (_dedication != null && _dedication!.isNotEmpty)
                            Text(
                              '💠 समर्पण: ${_dedication!}',
                              textAlign: TextAlign.center,
                              style: theme.textTheme.bodyLarge?.copyWith(
                                color: Colors.deepOrange.shade900,
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                          const SizedBox(height: 16),
                          Text(
                            'साधना निरंतर 🌼',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w500,
                              color: Colors.brown.shade700,
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Radha Jap Counter',
                            style: theme.textTheme.labelLarge?.copyWith(
                              color: Colors.brown.shade800.withOpacity(0.7),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 32),
              ElevatedButton.icon(
                onPressed: _sharing ? null : _shareCard,
                icon: const Icon(Icons.share),
                label: Text(_sharing ? 'Preparing...' : 'Share Image'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 32,
                    vertical: 14,
                  ),
                  backgroundColor: Colors.deepOrangeAccent,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _statRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
          ),
          Text(
            value,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }
}
