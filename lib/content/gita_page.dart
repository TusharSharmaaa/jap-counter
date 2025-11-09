import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/ad_manager.dart';
import '../utils/quote_image_generator.dart';
import 'gita_service.dart';
import 'quote_theme.dart';

class GitaShloka {
  final String ref;
  final String sanskrit;
  final String? transliteration;
  final String translation;

  GitaShloka({
    required this.ref,
    required this.sanskrit,
    required this.translation,
    this.transliteration,
  });
}

class GitaPage extends StatefulWidget {
  const GitaPage({super.key});

  @override
  State<GitaPage> createState() => _GitaPageState();
}

class _GitaPageState extends State<GitaPage> {
  static const _storeLink =
      'https://play.google.com/store/apps/details?id=com.example.jap_counter';

  final QuoteTheme _shareTheme = QuoteTheme.presets().first;

  final int _chapter = 1;
  int _verse = 1;
  Future<GitaShloka?>? _currentFuture;
  bool _sharing = false;
  String? _lastRecordedRef;

  @override
  void initState() {
    super.initState();
    _loadShloka();
    unawaited(
      AdManager.instance.preloadPlacement('gita.share_rewarded'),
    );
  }

  @override
  void dispose() {
    AdManager.instance.recordEvent('gita.session', 'end');
    super.dispose();
  }

  void _loadShloka() {
    _currentFuture = GitaService.fetchVerse(_chapter, _verse).then((verse) {
      if (verse == null) return null;
      return GitaShloka(
        ref: 'Chapter ${verse.chapter} · Verse ${verse.verse}',
        sanskrit: verse.sanskrit.trim(),
        translation: verse.hindi.trim(),
        transliteration: null,
      );
    });
  }

  void _prefetchNext() {
    GitaService.prefetch(_chapter, _verse + 1);
  }

  void _prevVerse() {
    if (_verse <= 1) return;
    setState(() {
      _verse -= 1;
      _loadShloka();
    });
  }

  void _nextVerse() {
    setState(() {
      _verse += 1;
      _loadShloka();
    });
  }

  Future<void> _copyShloka(GitaShloka shloka) async {
    final buffer = StringBuffer()
      ..writeln(shloka.ref)
      ..writeln()
      ..writeln(shloka.sanskrit);
    if (shloka.transliteration != null &&
        shloka.transliteration!.trim().isNotEmpty) {
      buffer
        ..writeln()
        ..writeln(shloka.transliteration!.trim());
    }
    buffer
      ..writeln()
      ..writeln(shloka.translation)
      ..writeln()
      ..write(_storeLink);

    await Clipboard.setData(ClipboardData(text: buffer.toString()));
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Shloka copied to clipboard')));
  }

  Future<void> _shareOnWhatsApp(GitaShloka shloka) async {
    if (_sharing) return;
    setState(() => _sharing = true);

    try {
      final adShown = await AdManager.instance.showRewardedAd(
        'gita.share_rewarded',
        timeout: const Duration(seconds: 8),
      );
      AdManager.instance.recordEvent(
        'gita.share_rewarded',
        'attempt',
        data: {'ad_shown': adShown},
      );
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[GitaPage] Rewarded attempt failed: $e');
      }
    }

    try {
      final subtitleParts = <String>[];
      if (shloka.transliteration != null &&
          shloka.transliteration!.trim().isNotEmpty) {
        subtitleParts.add(shloka.transliteration!.trim());
      }
      if (shloka.translation.isNotEmpty) {
        subtitleParts.add(shloka.translation);
      }

      final imagePath = await QuoteImageGenerator.generate(
        shloka.sanskrit,
        theme: _shareTheme,
        subtitle: subtitleParts.isEmpty ? null : subtitleParts.join('\n\n'),
        note: shloka.ref,
        shareLink: _storeLink,
      );
      AdManager.instance.recordEvent(
        'gita.share_rewarded',
        'share_card_generated',
      );
      final shareText = [
        shloka.ref,
        if (shloka.translation.isNotEmpty) shloka.translation,
        _storeLink,
      ].join('\n\n');

      final result = await SharePlus.instance.share(
        ShareParams(files: [XFile(imagePath)], text: shareText, title: 'Share'),
      );
      AdManager.instance.recordEvent(
        'gita.share_rewarded',
        'share_intent_launched',
      );

      if (result.status == ShareResultStatus.unavailable) {
        final waUri = Uri.parse(
          'whatsapp://send?text=${Uri.encodeComponent(shareText)}',
        );
        if (await canLaunchUrl(waUri)) {
          await launchUrl(waUri, mode: LaunchMode.externalApplication);
        }
      }
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('[GitaPage] Share failed: $e\n$st');
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Unable to share right now. Please try again.'),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _sharing = false);
      }
      unawaited(
        AdManager.instance.preloadPlacement('gita.share_rewarded'),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Gita'), centerTitle: true),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 24,
                  ),
                  child: FutureBuilder<GitaShloka?>(
                    future: _currentFuture,
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return _LoadingBody(theme: theme);
                      }

                      if (snapshot.hasError ||
                          !snapshot.hasData ||
                          snapshot.data == null) {
                        return _ErrorBody(
                          onRetry: () {
                            setState(() {
                              _loadShloka();
                            });
                          },
                        );
                      }

                      final shloka = snapshot.data!;
                      if (_lastRecordedRef != shloka.ref) {
                        _lastRecordedRef = shloka.ref;
                        AdManager.instance.recordEvent(
                          'gita.session',
                          'shloka_read',
                        );
                      }
                      WidgetsBinding.instance.addPostFrameCallback(
                        (_) => _prefetchNext(),
                      );

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _ShlokaCard(
                            shloka: shloka,
                            onCopy: () => _copyShloka(shloka),
                          ),
                          const SizedBox(height: 24),
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton(
                                  onPressed: _verse > 1 ? _prevVerse : null,
                                  child: const Text('Prev'),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: FilledButton.icon(
                                  onPressed: _sharing
                                      ? null
                                      : () => _shareOnWhatsApp(shloka),
                                  icon: _sharing
                                      ? SizedBox(
                                          width: 16,
                                          height: 16,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: theme.colorScheme.onPrimary,
                                          ),
                                        )
                                      : const Icon(Icons.share),
                                  label: const Text('Share'),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: OutlinedButton(
                                  onPressed: _nextVerse,
                                  child: const Text('Next'),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 24),
                        ],
                      );
                    },
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _ShlokaCard extends StatelessWidget {
  final GitaShloka shloka;
  final VoidCallback onCopy;

  const _ShlokaCard({required this.shloka, required this.onCopy});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textTheme = theme.textTheme;

    return Card(
      color: theme.cardColor,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(color: theme.dividerColor.withValues(alpha: 0.6)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    shloka.ref,
                    style: textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Copy',
                  onPressed: onCopy,
                  icon: const Icon(Icons.copy),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              shloka.sanskrit,
              textAlign: TextAlign.center,
              style: textTheme.headlineSmall?.copyWith(
                height: 1.6,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (shloka.transliteration != null &&
                shloka.transliteration!.trim().isNotEmpty) ...[
              const SizedBox(height: 16),
              Text(
                shloka.transliteration!,
                textAlign: TextAlign.center,
                style: textTheme.titleMedium?.copyWith(height: 1.5),
              ),
            ],
            if (shloka.translation.isNotEmpty) ...[
              const SizedBox(height: 16),
              Divider(color: theme.dividerColor.withValues(alpha: 0.5)),
              const SizedBox(height: 16),
              Text(
                shloka.translation,
                textAlign: TextAlign.center,
                style: textTheme.bodyLarge?.copyWith(height: 1.6),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _LoadingBody extends StatelessWidget {
  final ThemeData theme;

  const _LoadingBody({required this.theme});

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 240),
      child: Center(
        child: CircularProgressIndicator(color: theme.colorScheme.primary),
      ),
    );
  }
}

class _ErrorBody extends StatelessWidget {
  final VoidCallback onRetry;

  const _ErrorBody({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textTheme = theme.textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.error_outline, size: 64, color: theme.colorScheme.error),
        const SizedBox(height: 16),
        Text(
          'Unable to load shloka.',
          textAlign: TextAlign.center,
          style: textTheme.titleMedium,
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: onRetry,
          icon: const Icon(Icons.refresh),
          label: const Text('Retry'),
        ),
      ],
    );
  }
}
