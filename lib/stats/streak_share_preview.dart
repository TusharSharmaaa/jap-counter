import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:intl/intl.dart';

import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'dedication_store.dart';

class StreakSharePreviewPage extends StatefulWidget {
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
  State<StreakSharePreviewPage> createState() => _StreakSharePreviewPageState();
}

class _StreakSharePreviewPageState extends State<StreakSharePreviewPage> {
  final GlobalKey _cardKey = GlobalKey();
  bool _sharing = false;

  Future<void> _shareCard() async {
    if (_sharing) return;
    setState(() => _sharing = true);

    try {
      // 1) Capture widget to image
      final boundary = _cardKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) throw Exception('Capture boundary not found');
      final ui.Image image = await boundary.toImage(pixelRatio: 3.0);
      final ByteData? byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) throw Exception('Failed to encode PNG');
      final Uint8List pngBytes = byteData.buffer.asUint8List();

      // 2) Write to cache
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/radha_jap_streak.png');
      await file.writeAsBytes(pngBytes, flush: true);

      // 3) Launch share sheet
      final xFile = XFile(file.path, mimeType: 'image/png', name: 'radha_jap_streak.png');
      await Share.shareXFiles(
        [xFile],
        text: '🕉️ Radha Jap Counter — मेरी साधना स्ट्रीक',
        subject: 'Radha Jap Counter',
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text('Could not share image: $e'),
            behavior: SnackBarBehavior.floating,
          ),
        );
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final todayJaps = widget.todayJaps;
    final lifetimeMalas = widget.lifetimeMalas;
    final streakDays = widget.streakDays;

    return Scaffold(
      appBar: AppBar(
        title: const Text("Share My Streak"),
        actions: [
          IconButton(
            onPressed: _sharing ? null : _shareCard,
            icon: _sharing
                ? const SizedBox(
              width: 20, height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
                : const Icon(Icons.ios_share),
            tooltip: 'Share',
          ),
        ],
      ),
      body: Center(
        child: RepaintBoundary(
          key: _cardKey,
          child: Container(
            width: 320,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Theme.of(context).dividerColor),
              gradient: LinearGradient(
                colors: [
                  Theme.of(context).colorScheme.surface,
                  Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.5),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '🔥 ${widget.streakDays} day${widget.streakDays == 1 ? '' : 's'} streak',
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text("Today’s Japs: $todayJaps"),
                Text("Lifetime Malas: $lifetimeMalas"),
                Text("Streak: $streakDays days"),
                FutureBuilder<String>(
                  future: DedicationStore.get(),
                  builder: (context, snap) {
                    final dedication = snap.data ?? '';
                    if (dedication.isEmpty) return const SizedBox.shrink();
                    return Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(
                        '💠 समर्पण: $dedication',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontStyle: FontStyle.italic,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 8),
                const Text(
                  "Preview — share opens image",
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
