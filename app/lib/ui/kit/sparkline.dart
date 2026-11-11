import 'package:flutter/material.dart';

import '../theme.dart';

/// Tiny trend line. Green/up if it ends higher than it starts, else down.
/// Decorative unless [semanticLabel] is given.
class Sparkline extends StatelessWidget {
  const Sparkline(
    this.values, {
    super.key,
    this.width = 64,
    this.height = 28,
    this.color,
    this.semanticLabel,
  });

  final List<num> values;
  final double width, height;
  final Color? color;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final up = values.length < 2 || values.last >= values.first;
    final paint = CustomPaint(
      size: Size(width, height),
      painter: _SparkPainter(values, color ?? (up ? t.up : t.down)),
    );
    return semanticLabel == null
        ? ExcludeSemantics(child: paint)
        : Semantics(label: semanticLabel, image: true, child: paint);
  }
}

class _SparkPainter extends CustomPainter {
  _SparkPainter(this.v, this.color);
  final List<num> v;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (v.length < 2) return;
    final lo = v.reduce((a, b) => a < b ? a : b);
    final hi = v.reduce((a, b) => a > b ? a : b);
    final span = (hi - lo) == 0 ? 1 : (hi - lo);
    const pad = 2.0;
    final h = size.height - pad * 2;
    final p = Path();
    for (var i = 0; i < v.length; i++) {
      final x = size.width * i / (v.length - 1);
      final y = pad + h - h * (v[i] - lo) / span;
      i == 0 ? p.moveTo(x, y) : p.lineTo(x, y);
    }
    canvas.drawPath(
      p,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = color,
    );
  }

  @override
  bool shouldRepaint(_SparkPainter o) => o.v != v || o.color != color;
}
