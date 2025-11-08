import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

class QuoteImageGenerator {
  static Future<String> generate(String quote) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    const width = 1080.0, height = 1080.0;

    final paint = Paint()..color = Colors.white;
    canvas.drawRect(const Rect.fromLTWH(0, 0, width, height), paint);

    final textPainter = TextPainter(
      text: TextSpan(
        text: quote,
        style: const TextStyle(
          fontFamily: 'NotoSerifDevanagari',
          color: Colors.deepPurple,
          fontSize: 44,
          fontWeight: FontWeight.w500,
          height: 1.5,
        ),
      ),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: width - 120);

    textPainter.paint(canvas, const Offset(60, 420));

    final picture = recorder.endRecording();
    final img = await picture.toImage(width.toInt(), height.toInt());
    final bytes = await img.toByteData(format: ui.ImageByteFormat.png);

    final dir = await getTemporaryDirectory();
    final path = '${dir.path}/quote_${DateTime.now().millisecondsSinceEpoch}.png';
    await File(path).writeAsBytes(bytes!.buffer.asUint8List());
    return path;
  }
}

