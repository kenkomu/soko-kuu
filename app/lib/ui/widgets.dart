import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/material.dart';

import '../l10n.dart';
import 'kit/kit.dart';
import 'theme.dart';

export 'kit/kit.dart';

/// Basis points as a percent with two decimals: 10025 -> "100.25%".
String bpPercent(int bp) =>
    '${bp ~/ 100}.${(bp % 100).toString().padLeft(2, '0')}%';

String pts(int n) => formatPts(n);

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
