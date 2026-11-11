import 'package:flutter/material.dart';

import '../theme.dart';
import 'money.dart';

/// Direction is never colour alone: arrow + sign + colour + spoken label.
/// Pass translated [upWord]/[downWord]/[flatWord] for Swahili.
class DeltaChip extends StatelessWidget {
  const DeltaChip(
    this.delta, {
    super.key,
    this.suffix = '',
    this.upWord = 'up',
    this.downWord = 'down',
    this.flatWord = 'unchanged',
  });

  final int delta;
  final String suffix;
  final String upWord, downWord, flatWord;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final up = delta > 0, flat = delta == 0;
    final c = flat ? t.muted : (up ? t.up : t.down);
    final label = '${up ? '+' : ''}${fmt(delta)}$suffix';
    final spoken = flat ? flatWord : '${up ? upWord : downWord} $label';
    return Semantics(
      label: spoken,
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: c.withValues(alpha: .14),
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
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: bodyFont,
                  color: c,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
