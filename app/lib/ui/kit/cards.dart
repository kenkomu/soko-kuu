import 'package:flutter/material.dart';

import '../theme.dart';
import 'kitenge_band.dart';

/// Raised cream card with a thin border and no shadow.
/// With [onTap] it becomes a button (min 48dp, ripple).
class SokoCard extends StatelessWidget {
  const SokoCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.onTap,
    this.color,
    this.semanticLabel,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final Color? color;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    final r = BorderRadius.circular(18);
    final body = Padding(padding: padding, child: child);
    return Semantics(
      container: semanticLabel != null,
      label: semanticLabel,
      button: onTap != null,
      child: Material(
        color: color ?? context.tokens.card,
        shape: RoundedRectangleBorder(
          borderRadius: r,
          side: BorderSide(color: s.outlineVariant),
        ),
        clipBehavior: Clip.antiAlias,
        child: onTap == null
            ? body
            : InkWell(
                onTap: onTap,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 48),
                  child: body,
                ),
              ),
      ),
    );
  }
}

class SummaryCell {
  const SummaryCell({
    required this.label,
    required this.value,
    this.semanticLabel,
  });

  /// Short caption, already translated.
  final String label;

  /// Already formatted, e.g. '3,800 pts'.
  final String value;
  final String? semanticLabel;
}

/// Indigo strip of 2 to 4 figures. Goes 2x2 at large text sizes.
class SummaryStrip extends StatelessWidget {
  const SummaryStrip(this.cells, {super.key});
  final List<SummaryCell> cells;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
    final perRow = (cells.length > 2 && scale > 1.15) ? 2 : cells.length;
    final rows = <List<SummaryCell>>[
      for (var i = 0; i < cells.length; i += perRow)
        cells.sublist(i, (i + perRow).clamp(0, cells.length)),
    ];
    Widget cell(SummaryCell c) => Semantics(
      label: c.semanticLabel ?? '${c.label}: ${c.value}',
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              c.label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: bodyFont,
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: t.onIndigo.withValues(alpha: .88),
              ),
            ),
            const SizedBox(height: 4),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                c.value,
                maxLines: 1,
                style: TextStyle(
                  fontFamily: headingFont,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: t.onIndigo,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ],
        ),
      ),
    );
    return Container(
      decoration: BoxDecoration(
        color: t.indigo,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var r = 0; r < rows.length; r++)
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < rows[r].length; i++) ...[
                    if (i > 0)
                      VerticalDivider(
                        width: 1,
                        thickness: 1,
                        indent: 10,
                        endIndent: 10,
                        color: t.onIndigo.withValues(alpha: .25),
                      ),
                    Expanded(child: cell(rows[r][i])),
                  ],
                  // keep widths equal on a short last row
                  for (var i = rows[r].length; i < perRow; i++)
                    const Expanded(child: SizedBox.shrink()),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

enum StatusTone { good, bad, warn, info, neutral }

/// Pill with icon + text (never colour alone).
class StatusChip extends StatelessWidget {
  const StatusChip(
    this.label, {
    super.key,
    this.tone = StatusTone.neutral,
    this.icon,
  });

  final String label;
  final StatusTone tone;

  /// Defaults to a glyph that matches the tone.
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final s = Theme.of(context).colorScheme;
    final (Color fg, Color bg, IconData ic) = switch (tone) {
      StatusTone.good => (
        t.up,
        t.up.withValues(alpha: .15),
        Icons.check_circle,
      ),
      StatusTone.bad => (t.down, t.down.withValues(alpha: .15), Icons.error),
      // Ochre is a fill only; text stays ink.
      StatusTone.warn => (
        Colors.black.withValues(alpha: .87),
        t.ochre.withValues(alpha: .55),
        Icons.schedule,
      ),
      StatusTone.info => (t.teal, t.teal.withValues(alpha: .14), Icons.info),
      StatusTone.neutral => (
        s.onSurfaceVariant,
        s.onSurface.withValues(alpha: .08),
        Icons.circle_outlined,
      ),
    };
    final warnInk = tone == StatusTone.warn
        ? (Theme.of(context).brightness == Brightness.dark
              ? Colors.white
              : const Color(0xFF2B2322))
        : fg;
    return Semantics(
      label: label,
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon ?? ic, size: 14, color: warnInk),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                label,
                style: TextStyle(
                  fontFamily: bodyFont,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: warnInk,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Kitenge band + plain sentence (+ optional title and one action).
/// Text is passed in already translated.
class EmptyState extends StatelessWidget {
  const EmptyState(
    this.text, {
    super.key,
    this.title,
    this.actionLabel,
    this.onAction,
  });

  final String text;
  final String? title;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const KitengeBand(radius: 5),
          const SizedBox(height: 16),
          if (title != null) ...[
            Text(title!, textAlign: TextAlign.center, style: tt.titleMedium),
            const SizedBox(height: 6),
          ],
          Text(text, textAlign: TextAlign.center),
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: 12),
            FilledButton(onPressed: onAction, child: Text(actionLabel!)),
          ],
        ],
      ),
    );
  }
}
