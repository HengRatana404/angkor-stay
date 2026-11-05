import 'package:flutter/material.dart';

import '../core/theme.dart';

/// Pixel-perfect luxury brandmark for Angkor Stay.
/// Displays the official Angkor Wat & Lotus emblem with graceful vector fallback.
class AngkorLogo extends StatelessWidget {
  final double size;
  final bool useAsset;
  final Color color;
  final bool showBackground;
  final Color? backgroundColor;

  const AngkorLogo({
    super.key,
    this.size = 32,
    this.useAsset = true,
    this.color = angkorGoldLight,
    this.showBackground = false,
    this.backgroundColor,
  });

  @override
  Widget build(BuildContext context) {
    final emblem = useAsset
        ? Image.asset(
            'assets/logo.png',
            width: size,
            height: size,
            fit: BoxFit.contain,
            errorBuilder: (_, _, _) => _vectorFallback(context),
          )
        : _vectorFallback(context);

    if (showBackground) {
      return Container(
        width: size * 1.35,
        height: size * 1.35,
        decoration: BoxDecoration(
          color: backgroundColor ?? context.pal.strong,
          borderRadius: BorderRadius.circular(size * 0.32),
          border: Border.all(color: color.withValues(alpha: 0.3), width: 1.2),
          boxShadow: const [
            BoxShadow(
              color: Color(0x1A000000),
              blurRadius: 8,
              offset: Offset(0, 3),
            ),
          ],
        ),
        alignment: Alignment.center,
        child: emblem,
      );
    }

    return SizedBox(width: size, height: size, child: emblem);
  }

  Widget _vectorFallback(BuildContext context) {
    final emblem = CustomPaint(
      size: Size(size, size),
      painter: _AngkorLogoPainter(color: color),
    );

    if (!showBackground) return emblem;

    return Container(
      width: size * 1.35,
      height: size * 1.35,
      decoration: BoxDecoration(
        color: backgroundColor ?? context.pal.strong,
        borderRadius: BorderRadius.circular(size * 0.32),
        border: Border.all(color: color.withValues(alpha: 0.3), width: 1.2),
        boxShadow: const [
          BoxShadow(
            color: Color(0x1A000000),
            blurRadius: 8,
            offset: Offset(0, 3),
          ),
        ],
      ),
      alignment: Alignment.center,
      child: emblem,
    );
  }
}

class _AngkorLogoPainter extends CustomPainter {
  final Color color;
  _AngkorLogoPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final strokePaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = (size.width / 100).clamp(1.2, 4.0)
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final fillPaint = Paint()
      ..color = color.withValues(alpha: 0.30)
      ..style = PaintingStyle.fill;

    final w = size.width;
    final h = size.height;

    // Outer Medallion Ring
    canvas.drawCircle(
      Offset(w * 0.50, h * 0.50),
      w * 0.46,
      strokePaint..strokeWidth = (w / 70).clamp(1.2, 3.0),
    );

    // Finial & Spire peak
    canvas.drawLine(
      Offset(w * 0.50, h * 0.16),
      Offset(w * 0.50, h * 0.24),
      strokePaint..strokeWidth = (w / 100).clamp(1.5, 3.5),
    );
    canvas.drawCircle(
      Offset(w * 0.50, h * 0.14),
      (w * 0.02).clamp(1.0, 3.0),
      Paint()..color = color,
    );

    // Center Tower Lotus Bud Body
    final centerTower = Path()
      ..moveTo(w * 0.50, h * 0.24)
      ..cubicTo(w * 0.46, h * 0.32, w * 0.42, h * 0.40, w * 0.42, h * 0.52)
      ..cubicTo(w * 0.42, h * 0.58, w * 0.44, h * 0.64, w * 0.44, h * 0.68)
      ..lineTo(w * 0.56, h * 0.68)
      ..cubicTo(w * 0.56, h * 0.64, w * 0.58, h * 0.58, w * 0.58, h * 0.52)
      ..cubicTo(w * 0.58, h * 0.40, w * 0.54, h * 0.32, w * 0.50, h * 0.24)
      ..close();
    canvas.drawPath(centerTower, fillPaint);
    canvas.drawPath(centerTower, strokePaint);

    // Left Flanking Tower
    canvas.drawLine(
      Offset(w * 0.28, h * 0.28),
      Offset(w * 0.28, h * 0.34),
      strokePaint,
    );
    canvas.drawCircle(
      Offset(w * 0.28, h * 0.27),
      (w * 0.018).clamp(1.0, 2.5),
      Paint()..color = color,
    );

    final leftTower = Path()
      ..moveTo(w * 0.28, h * 0.34)
      ..cubicTo(w * 0.25, h * 0.40, w * 0.22, h * 0.48, w * 0.22, h * 0.58)
      ..cubicTo(w * 0.22, h * 0.64, w * 0.24, h * 0.68, w * 0.24, h * 0.72)
      ..lineTo(w * 0.34, h * 0.72)
      ..cubicTo(w * 0.34, h * 0.68, w * 0.34, h * 0.64, w * 0.34, h * 0.58)
      ..cubicTo(w * 0.34, h * 0.48, w * 0.31, h * 0.40, w * 0.28, h * 0.34)
      ..close();
    canvas.drawPath(leftTower, fillPaint);
    canvas.drawPath(leftTower, strokePaint);

    // Right Flanking Tower
    canvas.drawLine(
      Offset(w * 0.72, h * 0.28),
      Offset(w * 0.72, h * 0.34),
      strokePaint,
    );
    canvas.drawCircle(
      Offset(w * 0.72, h * 0.27),
      (w * 0.018).clamp(1.0, 2.5),
      Paint()..color = color,
    );

    final rightTower = Path()
      ..moveTo(w * 0.72, h * 0.34)
      ..cubicTo(w * 0.69, h * 0.40, w * 0.66, h * 0.48, w * 0.66, h * 0.58)
      ..cubicTo(w * 0.66, h * 0.64, w * 0.66, h * 0.68, w * 0.66, h * 0.72)
      ..lineTo(w * 0.76, h * 0.72)
      ..cubicTo(w * 0.76, h * 0.68, w * 0.78, h * 0.64, w * 0.78, h * 0.58)
      ..cubicTo(w * 0.78, h * 0.48, w * 0.75, h * 0.40, w * 0.72, h * 0.34)
      ..close();
    canvas.drawPath(rightTower, fillPaint);
    canvas.drawPath(rightTower, strokePaint);

    // Gallery Lines
    canvas.drawLine(
      Offset(w * 0.34, h * 0.70),
      Offset(w * 0.44, h * 0.68),
      strokePaint,
    );
    canvas.drawLine(
      Offset(w * 0.56, h * 0.68),
      Offset(w * 0.66, h * 0.70),
      strokePaint,
    );

    // Plinths
    canvas.drawLine(
      Offset(w * 0.18, h * 0.74),
      Offset(w * 0.82, h * 0.74),
      strokePaint..strokeWidth = (w / 70).clamp(1.5, 4.0),
    );
    canvas.drawLine(
      Offset(w * 0.14, h * 0.78),
      Offset(w * 0.86, h * 0.78),
      strokePaint..strokeWidth = (w / 80).clamp(1.2, 3.5),
    );
    canvas.drawLine(
      Offset(w * 0.10, h * 0.82),
      Offset(w * 0.90, h * 0.82),
      strokePaint..strokeWidth = (w / 90).clamp(1.0, 3.0),
    );

    // Lotus Base
    final lotusCradle = Path()
      ..moveTo(w * 0.12, h * 0.82)
      ..cubicTo(w * 0.08, h * 0.88, w * 0.20, h * 0.92, w * 0.35, h * 0.92)
      ..cubicTo(w * 0.44, h * 0.92, w * 0.48, h * 0.88, w * 0.50, h * 0.86)
      ..cubicTo(w * 0.52, h * 0.88, w * 0.56, h * 0.92, w * 0.65, h * 0.92)
      ..cubicTo(w * 0.80, h * 0.92, w * 0.92, h * 0.88, w * 0.88, h * 0.82);
    canvas.drawPath(
      lotusCradle,
      strokePaint..strokeWidth = (w / 80).clamp(1.2, 3.0),
    );
  }

  @override
  bool shouldRepaint(covariant _AngkorLogoPainter oldDelegate) =>
      oldDelegate.color != color;
}
