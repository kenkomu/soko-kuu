import 'package:flutter/material.dart';

import '../theme.dart';

/// The "Nyanya Juu" wordmark: "S" + the tomato mark in place of the "o" +
/// "ko Kuu", in Fredoka bold. Indigo on light, cream on dark. Screen readers
/// hear "Soko Kuu"; the image itself is excluded from semantics.
class SokoWordmark extends StatelessWidget {
  const SokoWordmark({super.key, this.size = 30, this.header = false});

  /// Font size of the letters; the tomato is about 0.85 of it.
  final double size;

  /// Mark it as a heading for screen readers.
  final bool header;

  static const lightInk = Color(0xFF2E3A8C);
  static const darkInk = Color(0xFFF6EBDA);

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final mark = size * .85;
    return Semantics(
      label: 'Soko Kuu',
      header: header,
      excludeSemantics: true,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: Text.rich(
          TextSpan(
            children: [
              const TextSpan(text: 'S'),
              WidgetSpan(
                alignment: PlaceholderAlignment.baseline,
                baseline: TextBaseline.alphabetic,
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: size * .02),
                  child: Image.asset(
                    'assets/brand/tomato_mark.png',
                    width: mark,
                    height: mark,
                    excludeFromSemantics: true,
                    filterQuality: FilterQuality.medium,
                  ),
                ),
              ),
              const TextSpan(text: 'ko Kuu'),
            ],
          ),
          maxLines: 1,
          softWrap: false,
          style: TextStyle(
            fontFamily: headingFont,
            fontWeight: FontWeight.w700,
            fontSize: size,
            height: 1.1,
            color: dark ? darkInk : lightInk,
          ),
        ),
      ),
    );
  }
}
