import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/material.dart';

import '../l10n.dart';
import 'theme.dart';

String fmt(int n) {
  final neg = n < 0;
  final s = n.abs().toString();
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
    b.write(s[i]);
  }
  return '${neg ? '-' : ''}$b';
}

/// Basis points as a percent with two decimals: 10025 -> "100.25%".
String bpPercent(int bp) =>
    '${bp ~/ 100}.${(bp % 100).toString().padLeft(2, '0')}%';

String pts(int n) => '${fmt(n)} pts';

String titleCase(String s) =>
    s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

/// Bundled Material icons per good (no emoji font needed, so nothing renders as a box offline).
const goodIcons = <String, (IconData, Color)>{
  'tomato': (Icons.circle, Color(0xFFC8402D)),
  'kale': (Icons.eco, Color(0xFF2F6B3F)),
  'sukuma': (Icons.eco, Color(0xFF2F6B3F)),
  'maize': (Icons.grass, Color(0xFFD9A21B)),
  'onion': (Icons.spa, Color(0xFF9A5B8C)),
  'beans': (Icons.grain, Color(0xFF7A4A2B)),
  'fish': (Icons.set_meal, Color(0xFF2F6F8F)),
  'charcoal': (Icons.local_fire_department, Color(0xFF4A3F36)),
};

/// Icon for a good, in a soft round badge.
class GoodIcon extends StatelessWidget {
  const GoodIcon(this.good, {super.key, this.size = 40});
  final String good;
  final double size;
  @override
  Widget build(BuildContext context) {
    final e = goodIcons[good] ?? (Icons.shopping_basket_outlined, charcoal);
    return ExcludeSemantics(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: e.$2.withValues(alpha: .15),
        ),
        child: Icon(e.$1, size: size * .6, color: e.$2),
      ),
    );
  }
}

class Num extends StatelessWidget {
  const Num(this.text, {super.key, this.style, this.textAlign});
  final String text;
  final TextStyle? style;
  final TextAlign? textAlign;
  @override
  Widget build(BuildContext context) => Text(
    text,
    textAlign: textAlign,
    style: (style ?? const TextStyle()).copyWith(fontFeatures: tabular),
  );
}

/// Direction is never colour alone: arrow + sign + colour.
class DeltaChip extends StatelessWidget {
  const DeltaChip(this.delta, {super.key, this.suffix = ''});
  final int delta;
  final String suffix;
  @override
  Widget build(BuildContext context) {
    final up = delta > 0, flat = delta == 0;
    final c = flat ? charcoal.withValues(alpha: .6) : (up ? leaf : terracotta);
    final label = '${up ? '+' : ''}${fmt(delta)}$suffix';
    return Semantics(
      label: flat ? 'unchanged' : (up ? 'up $label' : 'down $label'),
      child: ExcludeSemantics(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: c.withValues(alpha: .12),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                flat
                    ? Icons.remove
                    : (up ? Icons.arrow_upward : Icons.arrow_downward),
                size: 14,
                color: c,
              ),
              const SizedBox(width: 2),
              Num(
                label,
                style: TextStyle(
                  color: c,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class Sparkline extends StatelessWidget {
  const Sparkline(this.values, {super.key, this.width = 64, this.height = 28});
  final List<int> values;
  final double width, height;
  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: CustomPaint(
      size: Size(width, height),
      painter: _SparkPainter(values),
    ),
  );
}

class _SparkPainter extends CustomPainter {
  _SparkPainter(this.v);
  final List<int> v;
  @override
  void paint(Canvas canvas, Size size) {
    if (v.length < 2) return;
    final lo = v.reduce((a, b) => a < b ? a : b),
        hi = v.reduce((a, b) => a > b ? a : b);
    final span = (hi - lo) == 0 ? 1 : (hi - lo);
    final p = Path();
    for (var i = 0; i < v.length; i++) {
      final x = size.width * i / (v.length - 1);
      final y = size.height - size.height * (v[i] - lo) / span;
      i == 0 ? p.moveTo(x, y) : p.lineTo(x, y);
    }
    canvas.drawPath(
      p,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = v.last >= v.first ? leaf : terracotta
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(_SparkPainter o) => o.v != v;
}

/// Low-contrast kitenge-style repeating band for headers and empty states.
class KitengeBand extends StatelessWidget {
  const KitengeBand({super.key, this.height = 10});
  final double height;
  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: CustomPaint(
      size: Size.fromHeight(height),
      painter: _KitengePainter(),
    ),
  );
}

class _KitengePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final cols = [terracotta, ochre, leaf, charcoal];
    final w = size.height * 1.6;
    var i = 0;
    for (double x = 0; x < size.width; x += w, i++) {
      final paint = Paint()
        ..color = cols[i % cols.length].withValues(alpha: .35);
      if (i.isEven) {
        canvas.drawRect(Rect.fromLTWH(x, 0, w, size.height), paint);
      } else {
        final path = Path()
          ..moveTo(x, size.height)
          ..lineTo(x + w / 2, 0)
          ..lineTo(x + w, size.height)
          ..close();
        canvas.drawPath(path, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key, this.trailing});
  final String text;
  final Widget? trailing;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
    child: Row(
      children: [
        Expanded(
          child: Text(
            text,
            style: Theme.of(context).textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
        ),
        ?trailing,
      ],
    ),
  );
}

class EmptyState extends StatelessWidget {
  const EmptyState(this.text, {super.key});
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(24),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const KitengeBand(),
        const SizedBox(height: 12),
        Text(text, textAlign: TextAlign.center),
      ],
    ),
  );
}

void toast(BuildContext context, String msg, {bool error = false}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: error ? terracotta : leaf,
        behavior: SnackBarBehavior.floating,
      ),
    );
}

class AsyncBody<T> extends StatelessWidget {
  const AsyncBody({
    super.key,
    required this.value,
    required this.builder,
    this.onRetry,
  });
  final AsyncValue<T> value;
  final Widget Function(T) builder;
  final VoidCallback? onRetry;
  @override
  Widget build(BuildContext context) => value.when(
    data: builder,
    loading: () => const Center(child: CircularProgressIndicator()),
    error: (e, _) => Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(e is Exception ? e.toString() : 'Something went wrong.'),
          if (onRetry != null)
            TextButton(onPressed: onRetry, child: Text(tr('Try again'))),
        ],
      ),
    ),
  );
}
