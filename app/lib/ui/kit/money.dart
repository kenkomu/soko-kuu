import 'package:flutter/material.dart';

import '../theme.dart';

/// 20000 -> "20,000"; negatives keep a leading "-".
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

/// 3800 -> "3,800 pts". [unit] is a parameter so it can be translated.
String formatPts(int n, {String unit = 'pts'}) => '${fmt(n)} $unit';

/// Shillings with two decimals: 20000 -> "Ksh 20,000.00". Rounds to cents
/// using integer maths on the string form, so no float drift is shown.
String ksh(num amount, {String prefix = 'Ksh'}) {
  final cents = (amount * 100).round();
  final neg = cents < 0;
  final abs = cents.abs();
  final whole = fmt(abs ~/ 100);
  final frac = (abs % 100).toString().padLeft(2, '0');
  return '${neg ? '-' : ''}$prefix $whole.$frac';
}

/// An integer points amount in Fredoka with tabular figures.
/// Pair with `textAlign: TextAlign.end` in columns of amounts.
class Money extends StatelessWidget {
  const Money(
    this.pts, {
    super.key,
    this.style,
    this.textAlign,
    this.unit = 'pts',
    this.showUnit = true,
  });

  final int pts;
  final TextStyle? style;
  final TextAlign? textAlign;

  /// Unit word shown after the number.
  final String unit;
  final bool showUnit;

  static TextStyle baseStyle(BuildContext context) =>
      (Theme.of(context).textTheme.titleMedium ?? const TextStyle()).copyWith(
        fontFamily: headingFont,
        fontWeight: FontWeight.w600,
      );

  @override
  Widget build(BuildContext context) => Text(
    showUnit ? formatPts(pts, unit: unit) : fmt(pts),
    textAlign: textAlign,
    style: baseStyle(context)
        .merge(style)
        .copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
  );
}
