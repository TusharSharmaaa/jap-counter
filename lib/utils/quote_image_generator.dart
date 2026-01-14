import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../content/quote_theme.dart';

class QuoteImageGenerator {
  static final QuoteTheme _fallbackTheme = QuoteTheme.presets().first;

  static Future<String> generate(
    String quote, {
    QuoteTheme? theme,
    String? note,
    bool includeLink = true,
    String? shareLink,
    String? subtitle,
  }) async {
    final selectedTheme = theme ?? _fallbackTheme;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    const width = 1080.0, height = 1350.0;

    final rect = const Rect.fromLTWH(0, 0, width, height);
    final gradientPaint = Paint()
      ..shader = selectedTheme.background.createShader(rect);
    canvas.drawRect(rect, gradientPaint);

    final inset = 72.0;
    final innerRect = Rect.fromLTWH(
      inset,
      inset,
      width - inset * 2,
      height - inset * 2,
    );
    final innerRRect = RRect.fromRectAndRadius(
      innerRect,
      const Radius.circular(48),
    );
    final innerPaint = Paint()
      ..color = Colors.white.withOpacity(0.12)
      ..style = PaintingStyle.fill;
    canvas.drawRRect(innerRRect, innerPaint);

    final accentPaint = Paint()
      ..color = selectedTheme.badgeColor.withOpacity(0.35);
    canvas.drawCircle(
      Offset(innerRect.left + 140, innerRect.top + 160),
      120,
      accentPaint,
    );
    canvas.drawCircle(
      Offset(innerRect.right - 100, innerRect.bottom - 180),
      90,
      accentPaint..color = selectedTheme.accentColor.withOpacity(0.25),
    );

    final titleStyle = TextStyle(
      fontSize: 42,
      color: selectedTheme.textColor,
      fontWeight: FontWeight.w700,
    );
    final bodyStyle = TextStyle(
      fontSize: 46,
      color: selectedTheme.textColor.withOpacity(0.92),
      fontWeight: FontWeight.w500,
      height: 1.4,
    );
    final noteStyle = TextStyle(
      fontSize: 36,
      color: selectedTheme.textColor.withOpacity(0.75),
      fontStyle: FontStyle.italic,
    );
    final footerStyle = TextStyle(
      fontSize: 34,
      color: selectedTheme.textColor.withOpacity(0.7),
      fontWeight: FontWeight.w600,
    );

    double cursorY = innerRect.top + 120;

    cursorY = _paintText(
      canvas,
      text: '“',
      style: titleStyle.copyWith(fontSize: 80),
      maxWidth: innerRect.width,
      startX: innerRect.left + 40,
      startY: cursorY,
    );

    cursorY += 10;

    cursorY = _paintText(
      canvas,
      text: quote,
      style: bodyStyle,
      maxWidth: innerRect.width - 80,
      startX: innerRect.left + 40,
      startY: cursorY,
    );

    cursorY += 20;

    cursorY = _paintText(
      canvas,
      text: '”',
      style: titleStyle.copyWith(fontSize: 60),
      maxWidth: innerRect.width,
      startX: innerRect.left + innerRect.width - 100,
      startY: cursorY,
    );

    if (subtitle != null && subtitle.trim().isNotEmpty) {
      cursorY += 40;
      cursorY = _paintText(
        canvas,
        text: subtitle.trim(),
        style: bodyStyle.copyWith(
          fontSize: 32,
          fontWeight: FontWeight.w500,
          color: selectedTheme.textColor.withOpacity(0.85),
        ),
        maxWidth: innerRect.width - 60,
        startX: innerRect.left + 30,
        startY: cursorY,
      );
    }

    if (note != null && note.trim().isNotEmpty) {
      cursorY += 60;
      cursorY = _paintText(
        canvas,
        text: note.trim(),
        style: noteStyle,
        maxWidth: innerRect.width - 40,
        startX: innerRect.left + 20,
        startY: cursorY,
      );
    }

    final footerY = innerRect.bottom - 140;
    _paintText(
      canvas,
      text: 'Naam Jap Counter : Sadhna',
      style: footerStyle,
      maxWidth: innerRect.width,
      startX: innerRect.left + 20,
      startY: footerY,
    );
    if (includeLink) {
      final linkText =
          shareLink ??
          'Download today · https://play.google.com/store/apps/details?id=com.example.jap_counter';
      _paintText(
        canvas,
        text: linkText,
        style: footerStyle.copyWith(
          fontSize: 30,
          fontWeight: FontWeight.w500,
          color: selectedTheme.textColor.withOpacity(0.6),
        ),
        maxWidth: innerRect.width,
        startX: innerRect.left + 20,
        startY: footerY + 46,
      );
    }

    final picture = recorder.endRecording();
    final img = await picture.toImage(width.toInt(), height.toInt());
    final bytes = await img.toByteData(format: ui.ImageByteFormat.png);

    final dir = await getTemporaryDirectory();
    final path =
        '${dir.path}/quote_${DateTime.now().millisecondsSinceEpoch}.png';
    await File(path).writeAsBytes(bytes!.buffer.asUint8List());
    return path;
  }

  static double _paintText(
    Canvas canvas, {
    required String text,
    required TextStyle style,
    required double maxWidth,
    required double startX,
    required double startY,
  }) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textAlign: TextAlign.start,
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: maxWidth);
    painter.paint(canvas, Offset(startX, startY));
    return startY + painter.height;
  }
}
