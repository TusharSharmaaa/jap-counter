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
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

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
      final ctx = _cardKey.currentContext;
      if (ctx == null) return;
      final boundary = ctx.findRenderObject() as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 3.5); // crisper share
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

  Future<void> _saveCardPng() async {
    try {
      setState(() => _sharing = true);
      final ctx = _cardKey.currentContext;
      if (ctx == null) return;
      final boundary = ctx.findRenderObject() as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 3.5);
      final byteData = await image.toByteData(format: ImageByteFormat.png);
      final pngBytes = byteData!.buffer.asUint8List();

      final dir = await getTemporaryDirectory();
      final file =
          File('${dir.path}/rjc_streak_${DateTime.now().millisecondsSinceEpoch}.png');
      await file.writeAsBytes(pngBytes);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Saved image to: ${file.path}')),
      );
    } catch (e) {
      if (kDebugMode) debugPrint('[SharePreview] Save failed: $e');
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  Future<void> _shareWhatsAppText() async {
    const pkg = 'com.whatsapp';
    final msg = Uri.encodeComponent('🌸 मेरी साधना की झलक — Radha Jap Counter के साथ।');
    final waUri = Uri.parse('whatsapp://send?text=$msg');
    try {
      final can = await canLaunchUrl(waUri);
      if (can) {
        await launchUrl(waUri, mode: LaunchMode.externalApplication);
        return;
      }
    } catch (_) {}

    await Share.share('🌸 मेरी साधना की झलक — Radha Jap Counter के साथ।');
  }

  @override
  Widget build(BuildContext context) {
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
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      maxWidth: 720,
                    ),
                    child: AspectRatio(
                      aspectRatio: 4 / 5,
                      child: AnimatedBuilder(
                        animation: _glowCtl,
                        builder: (context, _) {
                          return Container(
                            margin: const EdgeInsets.symmetric(horizontal: 20),
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(24),
                              gradient: const LinearGradient(
                                colors: [Color(0xFFFFD54F), Color(0xFFFFB300)],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              border: Border.all(color: Colors.amber, width: 2),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.amber.withOpacity(0.25 + 0.25 * _glowCtl.value),
                                  blurRadius: 14 + 6 * _glowCtl.value,
                                  spreadRadius: 1 + 1 * _glowCtl.value,
                                  offset: const Offset(0, 6),
                                ),
                              ],
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.max,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  '🌸 मेरा साधना सफर 🌸',
                                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                                        fontWeight: FontWeight.bold,
                                        color: Colors.brown.shade800,
                                      ),
                                ),
                                const SizedBox(height: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withOpacity(0.20),
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(
                                      color: Colors.amber.withOpacity(0.6),
                                      width: 1,
                                    ),
                                  ),
                                  child: Text(
                                    '🔥 ${widget.streakDays} day streak',
                                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                                          fontWeight: FontWeight.w600,
                                          color: Colors.brown.shade800,
                                          letterSpacing: 0.3,
                                        ),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  _localeReady
                                      ? DateFormat('d MMMM yyyy', 'hi_IN').format(DateTime.now())
                                      : DateFormat.yMMMMd().format(DateTime.now()),
                                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                                        color: Colors.brown.shade700,
                                      ),
                                ),
                                const Divider(thickness: 1, height: 24),
                                _statRow('आज के जाप', widget.todayJaps.toString()),
                                _statRow('जीवन भर के माला', widget.lifetimeMalas.toString()),
                                _statRow('अभ्यास के दिन', widget.streakDays.toString()),
                                const SizedBox(height: 16),
                                if (_dedication != null && _dedication!.isNotEmpty)
                                  Text(
                                    '💠 समर्पण: ${_dedication!}',
                                    textAlign: TextAlign.center,
                                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                                          color: Colors.deepOrange.shade900,
                                          fontStyle: FontStyle.italic,
                                        ),
                                  ),
                                const SizedBox(height: 16),
                                Text(
                                  'साधना निरंतर 🌼',
                                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                        fontWeight: FontWeight.w500,
                                        color: Colors.brown.shade700,
                                      ),
                                ),
                                const SizedBox(height: 16),
                                Align(
                                  alignment: Alignment.centerRight,
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.temple_hindu,
                                        size: 14,
                                        color: Colors.brown.shade800.withOpacity(0.55),
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        'Radha Jap Counter',
                                        style: Theme.of(context).textTheme.labelMedium?.copyWith(
                                              color: Colors.brown.shade800.withOpacity(0.55),
                                              fontWeight: FontWeight.w600,
                                              letterSpacing: 0.3,
                                            ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 32),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _sharing ? null : _shareCard,
                        icon: const Icon(Icons.ios_share),
                        label: Text(_sharing ? 'Preparing…' : 'Share Image'),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          backgroundColor: Colors.deepOrangeAccent,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    IconButton.filled(
                      onPressed: _sharing ? null : _saveCardPng,
                      icon: const Icon(Icons.download),
                      tooltip: 'Save Image',
                    ),
                    const SizedBox(width: 6),
                    IconButton.filled(
                      onPressed: _sharing ? null : _shareWhatsAppText,
                      icon: const FaIcon(FontAwesomeIcons.whatsapp, color: Colors.white),
                      style: IconButton.styleFrom(
                        backgroundColor: const Color(0xFF25D366),
                      ),
                      tooltip: 'WhatsApp (Text)',
                    ),
                  ],
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
