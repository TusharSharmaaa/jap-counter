import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../data/activity_store.dart';

class StreakImageGenerator {
  static Future<String> generate() async {
    final streak = await ActivityStore.currentStreak();

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    const w = 1080.0, h = 1080.0;

    final gradient = const LinearGradient(
      colors: [Color(0xFF6A0572), Color(0xFFF5B700)],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    ).createShader(const Rect.fromLTWH(0, 0, w, h));

    canvas.drawRect(const Rect.fromLTWH(0, 0, w, h), Paint()..shader = gradient);

    final textPainter = TextPainter(
      text: TextSpan(
        text: '🔥 $streak-Day Streak\nसाधना जारी है...',
        style: const TextStyle(
          color: Colors.white,
          fontFamily: 'NotoSerifDevanagari',
          fontSize: 72,
          fontWeight: FontWeight.bold,
          height: 1.4,
        ),
      ),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: w - 200);

    textPainter.paint(canvas, const Offset(100, 400));

    final picture = recorder.endRecording();
    final img = await picture.toImage(w.toInt(), h.toInt());
    final bytes = await img.toByteData(format: ui.ImageByteFormat.png);

    final dir = await getTemporaryDirectory();
    final path = '${dir.path}/streak_${DateTime.now().millisecondsSinceEpoch}.png';
    await File(path).writeAsBytes(bytes!.buffer.asUint8List());
    return path;
  }
}

