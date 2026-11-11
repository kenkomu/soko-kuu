import 'package:flutter/material.dart';

import '../theme.dart';

/// Decorative header band from the four measured kitenge colours.
/// Use on headers and empty states only.
class KitengeBand extends StatelessWidget {
  const KitengeBand({super.key, this.height = 10, this.radius = 0});
  final double height, radius;

  @override
  Widget build(BuildContext context) {
    final cols = context.tokens.kitenge;
    return ExcludeSemantics(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: SizedBox(
          height: height,
          width: double.infinity,
          child: CustomPaint(painter: _KitengePainter(cols)),
        ),
      ),
    );
  }
}

class _KitengePainter extends CustomPainter {
  _KitengePainter(this.cols);
  final List<Color> cols;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.height * 1.6;
    var i = 0;
    for (double x = 0; x < size.width; x += w, i++) {
      final paint = Paint()..color = cols[i % cols.length];
      if (i.isEven) {
        canvas.drawRect(Rect.fromLTWH(x, 0, w, size.height), paint);
      } else {
        canvas.drawPath(
          Path()
            ..moveTo(x, size.height)
            ..lineTo(x + w / 2, 0)
            ..lineTo(x + w, size.height)
            ..close(),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_KitengePainter o) => o.cols != cols;
}
