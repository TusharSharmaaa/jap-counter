import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../theme/design_system.dart';

/// Circular progress ring widget using design system
/// 
/// Example:
/// ```dart
/// ProgressRing(
///   progress: 0.7, // 70%
///   size: 120,
///   strokeWidth: 8,
/// )
/// ```
class ProgressRing extends StatelessWidget {
  final double progress; // 0.0 to 1.0
  final double size;
  final double strokeWidth;
  final Color? backgroundColor;
  final Color? progressColor;
  final Color? backgroundFillColor; // Fill color for the ring area
  final Widget? child;
  final bool showGlow;

  const ProgressRing({
    super.key,
    required this.progress,
    this.size = 120,
    this.strokeWidth = 8,
    this.backgroundColor,
    this.progressColor,
    this.backgroundFillColor,
    this.child,
    this.showGlow = false,
  });

  @override
  Widget build(BuildContext context) {
    final clampedProgress = progress.clamp(0.0, 1.0);
    final bgColor = backgroundColor ?? 
        DesignSystem.glassBorder;
    final progColor = progressColor ?? DesignSystem.primary;

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Background fill circle (if provided)
          if (backgroundFillColor != null)
            Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: backgroundFillColor,
              ),
            ),
          // Background circle
          SizedBox(
            width: size,
            height: size,
            child: CircularProgressIndicator(
              value: 1.0,
              strokeWidth: strokeWidth,
              valueColor: AlwaysStoppedAnimation<Color>(bgColor),
              backgroundColor: Colors.transparent,
            ),
          ),
          // Progress circle - keep original width, no blur
          Transform.rotate(
            angle: -math.pi / 2, // Start from top
            child: CustomPaint(
              size: Size(size, size),
              painter: _ProgressRingPainter(
                progress: clampedProgress,
                strokeWidth: strokeWidth, // Keep original width, not wider
                color: progColor,
              ),
            ),
          ),
          // Glow effect - no blur
          if (showGlow && clampedProgress > 0)
            Transform.rotate(
              angle: -math.pi / 2 + (2 * math.pi * clampedProgress),
              child: Container(
                width: size,
                height: size,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: progColor.withValues(alpha: 0.3),
                      blurRadius: 0, // No blur
                      spreadRadius: 1,
                    ),
                  ],
                ),
              ),
            ),
          // Child content
          if (child != null) child!,
        ],
      ),
    );
  }
}

class _ProgressRingPainter extends CustomPainter {
  final double progress;
  final double strokeWidth;
  final Color color;

  _ProgressRingPainter({
    required this.progress,
    required this.strokeWidth,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width - strokeWidth) / 2;
    
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final sweepAngle = 2 * math.pi * progress;
    
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2, // Start from top
      sweepAngle,
      false,
      paint,
    );
  }

  @override
  bool shouldRepaint(_ProgressRingPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.strokeWidth != strokeWidth ||
        oldDelegate.color != color;
  }
}

