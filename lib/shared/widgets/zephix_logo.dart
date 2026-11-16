import 'package:flutter/material.dart';

import '../../app/theme/zephix_colors.dart';

/// The Zephix mark: a "Z" whose diagonal is a sound wave, with a small
/// lavender spark. Same geometry as the Android adaptive icon and
/// `assets/brand/zephix_mark.svg` (108-unit grid).
class ZephixMark extends StatelessWidget {
  const ZephixMark({super.key, this.size = 40, this.color, this.sparkColor, this.background});

  final double size;
  final Color? color;
  final Color? sparkColor;
  final Color? background;

  @override
  Widget build(BuildContext context) {
    final zc = context.zc;
    return Semantics(
      label: 'Zephix',
      image: true,
      child: CustomPaint(
        size: Size.square(size),
        painter: _MarkPainter(
          color ?? zc.primary,
          sparkColor ?? zc.secondary,
          background,
        ),
      ),
    );
  }
}

class _MarkPainter extends CustomPainter {
  _MarkPainter(this.color, this.spark, this.background);
  final Color color;
  final Color spark;
  final Color? background;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 108;
    canvas.scale(s);
    if (background != null) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(const Rect.fromLTWH(0, 0, 108, 108), const Radius.circular(28)),
        Paint()..color = background!,
      );
    }
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 7
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final path = Path()
      ..moveTo(36, 38)
      ..lineTo(72, 38)
      ..moveTo(72, 40)
      ..cubicTo(60, 44, 63, 55, 54, 54)
      ..cubicTo(45, 53, 48, 64, 36, 68)
      ..moveTo(36, 70)
      ..lineTo(72, 70);
    canvas.drawPath(path, stroke);
    canvas.drawCircle(const Offset(78, 30), 4, Paint()..color = spark);
  }

  @override
  bool shouldRepaint(_MarkPainter old) =>
      old.color != color || old.spark != spark || old.background != background;
}

/// Mark + wordmark lockup.
class ZephixWordmark extends StatelessWidget {
  const ZephixWordmark({super.key, this.size = 28});
  final double size;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ZephixMark(size: size * 1.35),
        const SizedBox(width: 6),
        Text(
          'zephix',
          style: TextStyle(
            fontSize: size,
            fontWeight: FontWeight.w800,
            letterSpacing: -size * 0.04,
            color: context.zc.textPrimary,
            height: 1,
          ),
        ),
      ],
    );
  }
}
