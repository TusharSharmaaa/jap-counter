import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import '../core/ad_manager.dart';
import '../l10n/app_localizations.dart';
import 'dedication_store.dart';

String _toHindiDigits(int number) {
  const mapping = {
    '0': '०',
    '1': '१',
    '2': '२',
    '3': '३',
    '4': '४',
    '5': '५',
    '6': '६',
    '7': '७',
    '8': '८',
    '9': '९',
  };
  return number.toString().split('').map((d) => mapping[d] ?? d).join();
}

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
    final lang = AppLocalizationScope.of(context).language;
    final locale = lang == 'hi' ? 'hi_IN' : 'en_US';
    await initializeDateFormatting(locale);
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

  Future<File?> _captureCardImage({String prefix = 'streak_share'}) async {
    try {
      final ctx = _cardKey.currentContext;
      if (ctx == null) return null;
      final boundary = ctx.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) return null;

      final image = await boundary.toImage(pixelRatio: 3.5);
      final byteData = await image.toByteData(format: ImageByteFormat.png);
      if (byteData == null) return null;

      final dir = await getTemporaryDirectory();
      final file = File(
        '${dir.path}/${prefix}_${DateTime.now().millisecondsSinceEpoch}.png',
      );
      await file.writeAsBytes(byteData.buffer.asUint8List());
      return file;
    } catch (e) {
      if (kDebugMode) debugPrint('[SharePreview] Capture failed: $e');
      return null;
    }
  }

  Future<void> _shareCard() async {
    final shareText =
        '${context.tr('share.shareText')}\n${context.tr('share.shareTextLink')}';
    try {
      setState(() => _sharing = true);
      final file = await _captureCardImage();
      if (file == null) return;
      AdManager.instance.recordEvent(
        'stats.share_rewarded',
        'share_card_generated',
      );

      await SharePlus.instance.share(
        ShareParams(files: [XFile(file.path)], text: shareText),
      );
      AdManager.instance.recordEvent(
        'stats.share_rewarded',
        'share_intent_launched',
      );
    } catch (e) {
      if (kDebugMode) debugPrint('[SharePreview] Share failed: $e');
    } finally {
      unawaited(
        AdManager.instance.preloadPlacement('stats.share_rewarded'),
      );
      if (mounted) setState(() => _sharing = false);
    }
  }

  Future<void> _saveCardPng() async {
    try {
      setState(() => _sharing = true);
      final file = await _captureCardImage(prefix: 'rjc_streak');
      if (file == null) return;

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.tr('share.saved', args: {'path': file.path})),
        ),
      );
    } catch (e) {
      if (kDebugMode) debugPrint('[SharePreview] Save failed: $e');
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  Future<void> _shareWhatsAppCard() async {
    final shareText =
        '${context.tr('share.shareText')}\n${context.tr('share.shareTextLink')}';
    try {
      setState(() => _sharing = true);
      final file = await _captureCardImage(prefix: 'whatsapp_streak');
      if (file == null) {
        await SharePlus.instance.share(ShareParams(text: shareText));
        return;
      }
      AdManager.instance.recordEvent(
        'stats.share_rewarded',
        'share_card_generated',
      );

      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path)],
          text: shareText,
          title: context.tr('share.whatsappTooltip'),
        ),
      );
      AdManager.instance.recordEvent(
        'stats.share_rewarded',
        'share_intent_launched',
      );
    } catch (e) {
      if (kDebugMode) debugPrint('[SharePreview] WhatsApp share failed: $e');
    } finally {
      unawaited(
        AdManager.instance.preloadPlacement('stats.share_rewarded'),
      );
      if (mounted) setState(() => _sharing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final lang = AppLocalizationScope.of(context).language;
    final locale = lang == 'hi' ? 'hi_IN' : 'en_US';
    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr('share.appBar')),
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
                    constraints: const BoxConstraints(maxWidth: 720),
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
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [
                                  Color(0xFFF6F1EB),
                                  Color(0xFFE4D6C4),
                                  Color(0xFFF6E7D8),
                                ],
                              ),
                              border: Border.all(
                                color: Colors.brown.shade200,
                                width: 1.2,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.brown.withValues(
                                    alpha: 0.12 + 0.10 * _glowCtl.value,
                                  ),
                                  blurRadius: 18 + 8 * _glowCtl.value,
                                  spreadRadius: 2 + 2 * _glowCtl.value,
                                  offset: const Offset(0, 10),
                                ),
                              ],
                            ),
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.center,
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    context.tr('share.title'),
                                    style: Theme.of(context)
                                        .textTheme
                                        .headlineSmall
                                        ?.copyWith(
                                          fontWeight: FontWeight.bold,
                                          color: Colors.brown.shade800,
                                        ),
                                  ),
                                  const SizedBox(height: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 6,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.white.withValues(
                                        alpha: 0.20,
                                      ),
                                      borderRadius: BorderRadius.circular(20),
                                      border: Border.all(
                                        color: Colors.amber.withValues(
                                          alpha: 0.6,
                                        ),
                                        width: 1,
                                      ),
                                    ),
                                    child: Text(
                                      context.tr(
                                        'share.streakLabel',
                                        args: {
                                          'days': _formatNumber(
                                            widget.streakDays,
                                            lang,
                                          ),
                                        },
                                      ),
                                      style: Theme.of(context)
                                          .textTheme
                                          .labelLarge
                                          ?.copyWith(
                                            fontWeight: FontWeight.w600,
                                            color: Colors.brown.shade800,
                                            letterSpacing: 0.3,
                                          ),
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    _localeReady
                                        ? DateFormat(
                                            'd MMMM yyyy',
                                            locale,
                                          ).format(DateTime.now())
                                        : DateFormat.yMMMMd(
                                            locale,
                                          ).format(DateTime.now()),
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelLarge
                                        ?.copyWith(
                                          color: Colors.brown.shade700,
                                        ),
                                  ),
                                  const Divider(thickness: 1, height: 24),
                                  _statLine(
                                    context.tr(
                                      'share.todayJaps',
                                      args: {
                                        'value': _formatNumber(
                                          widget.todayJaps,
                                          lang,
                                        ),
                                      },
                                    ),
                                  ),
                                  _statLine(
                                    context.tr(
                                      'share.lifetimeMalas',
                                      args: {
                                        'value': _formatNumber(
                                          widget.lifetimeMalas,
                                          lang,
                                        ),
                                      },
                                    ),
                                  ),
                                  _statLine(
                                    context.tr(
                                      'share.streakDays',
                                      args: {
                                        'value': _formatNumber(
                                          widget.streakDays,
                                          lang,
                                        ),
                                      },
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                  if (_dedication != null &&
                                      _dedication!.isNotEmpty)
                                    Text(
                                      context.tr(
                                        'share.dedication',
                                        args: {'note': _dedication!},
                                      ),
                                      textAlign: TextAlign.center,
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodyLarge
                                          ?.copyWith(
                                            color: Colors.deepOrange.shade900,
                                            fontStyle: FontStyle.italic,
                                          ),
                                    ),
                                  const SizedBox(height: 16),
                                  Text(
                                    context.tr('share.motto'),
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium
                                        ?.copyWith(
                                          fontWeight: FontWeight.w500,
                                          color: Colors.brown.shade700,
                                        ),
                                  ),
                                  const SizedBox(height: 16),
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        Icons.temple_hindu,
                                        size: 14,
                                        color: Colors.brown.shade800
                                            .withValues(alpha: 0.55),
                                      ),
                                      const SizedBox(width: 6),
                                      Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            context.tr('share.footer'),
                                            textAlign: TextAlign.left,
                                            style: Theme.of(context)
                                                .textTheme
                                                .labelMedium
                                                ?.copyWith(
                                                  color: Colors.brown.shade800
                                                      .withValues(alpha: 0.55),
                                                  fontWeight: FontWeight.w600,
                                                  letterSpacing: 0.3,
                                                ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            context.tr('share.footerSub'),
                                            textAlign: TextAlign.left,
                                            style: Theme.of(context)
                                                .textTheme
                                                .labelSmall
                                                ?.copyWith(
                                                  color: Colors.brown.shade800
                                                      .withValues(alpha: 0.4),
                                                  fontWeight: FontWeight.w500,
                                                ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ],
                              ),
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
                        label: Text(
                          _sharing
                              ? context.tr('stats.sharePreparing')
                              : context.tr('common.share'),
                        ),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          backgroundColor: const Color(0xFFD97757), // Eye-friendly softer orange
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
                      tooltip: context.tr('share.saveTooltip'),
                    ),
                    const SizedBox(width: 6),
                    IconButton.filled(
                      onPressed: _sharing ? null : _shareWhatsAppCard,
                      icon: const FaIcon(
                        FontAwesomeIcons.whatsapp,
                        color: Colors.white,
                      ),
                      style: IconButton.styleFrom(
                        backgroundColor: const Color(0xFF25D366),
                      ),
                      tooltip: context.tr('share.whatsappTooltip'),
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

  Widget _statLine(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            text,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.2,
              color: Colors.black, // Black color for visibility
            ),
          ),
        ],
      ),
    );
  }

  String _formatNumber(int value, String language) {
    return language == 'hi' ? _toHindiDigits(value) : value.toString();
  }
}
