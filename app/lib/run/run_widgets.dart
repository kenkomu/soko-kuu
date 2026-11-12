import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../l10n.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';
import 'soko_run_engine.dart';

/// Length of the overnight reveal: price count-up, row flash, floating delta,
/// radio wobble. One controller drives all of them.
const kRevealMs = 1200;

String runGoodName(String id) => switch (id) {
  'tomato' => tr('Tomato'),
  'maize' => tr('Maize'),
  _ => tr('Sukuma'),
};

String _goodPlural(String id) => switch (id) {
  'tomato' => tr('tomatoes'),
  'maize' => tr('maize'),
  _ => tr('sukuma'),
};

/// "3 tomatoes" / "1 tomato" style noun for the end-screen moves.
String runGoodNoun(String id, int qty) =>
    qty == 1 ? runGoodName(id).toLowerCase() : _goodPlural(id);

String runModeLabel(RunGame g) => switch (g.mode) {
  RunMode.daily => tr('Daily #{n}', {'n': g.dailyNo}),
  RunMode.first => tr('First market'),
  RunMode.practice => tr('Practice'),
};

/// The reveal sentence: "Radio was right. Tomato rose from 50 to 100."
String revealText(RunGame g) {
  final rv = g.reveal!;
  final r = rv.rumour;
  final head = r.truth
      ? tr('Radio was right.')
      : tr('Radio was wrong this time.');
  final String what;
  if (r.isAll) {
    // A wrong rumour has no effect: prices stay near their normal level.
    what = !r.truth
        ? tr('Prices stayed near normal.')
        : g.prices['tomato']! > rv.old['tomato']!
        ? tr('Prices went up.')
        : tr('Prices went down.');
  } else {
    final now = g.prices[r.target]!, was = rv.old[r.target]!;
    final p = {'g': runGoodName(r.target), 'a': fmt(was), 'b': fmt(now)};
    what = now == was
        ? tr('{g} stayed at {a}.', p)
        : !r.truth
        ? tr('{g} stayed near {b}.', p)
        : now > was
        ? tr('{g} rose from {a} to {b}.', p)
        : tr('{g} fell from {a} to {b}.', p);
  }
  return '$head $what';
}

/// Text with **bold** spans, for the hints.
Text boldSpans(String s, TextStyle style) {
  final parts = s.split('**');
  return Text.rich(
    TextSpan(
      children: [
        for (var i = 0; i < parts.length; i++)
          TextSpan(
            text: parts[i],
            style: i.isOdd
                ? const TextStyle(fontWeight: FontWeight.w800)
                : null,
          ),
      ],
    ),
    style: style,
  );
}

double _phase(Animation<double> fx, int ms) =>
    (fx.value * kRevealMs / ms).clamp(0.0, 1.0);

/// Indigo bar: day, mode chip, points, sack worth and total, 10 dots, and a
/// floating +N or -N on the total after each night.
class RunTopBar extends StatelessWidget {
  const RunTopBar(this.g, {super.key, required this.fx, required this.still});
  final RunGame g;
  final Animation<double> fx;
  final bool still;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final on = t.onIndigo;
    final tt = Theme.of(context).textTheme;
    final rv = g.reveal;
    final delta = rv == null ? 0 : rv.after - rv.before;
    final float = !still && rv != null && delta.abs() >= 1 && g.sack > 0;
    final worthStyle = TextStyle(
      fontSize: 12.5,
      color: on.withValues(alpha: .92),
      fontFeatures: tabular,
    );
    // +N or -N beside the total; rises and fades over the reveal.
    final floatDelta = IgnorePointer(
      child: ExcludeSemantics(
        child: AnimatedBuilder(
          animation: fx,
          builder: (_, _) {
            final k = _phase(fx, 1100);
            if (k >= 1) return const SizedBox.shrink();
            return Opacity(
              opacity: 1 - k,
              child: Transform.translate(
                offset: Offset(0, -28 * k),
                child: Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Text(
                    '${delta > 0 ? '+' : '-'}${fmt(delta.abs())}',
                    style: TextStyle(
                      fontFamily: headingFont,
                      fontWeight: FontWeight.w700,
                      fontSize: 18,
                      height: 1,
                      color: delta > 0
                          ? const Color(0xFFBFF2D2)
                          : const Color(0xFFFFC9C2),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: BoxDecoration(
        color: t.indigo,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: double.infinity,
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 12,
              runSpacing: 4,
              children: [
                Text(
                  tr('Day {d} of {n}', {'d': g.day, 'n': kDays}),
                  style: tt.bodyMedium?.copyWith(
                    color: on.withValues(alpha: .92),
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: t.ochre,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    runModeLabel(g),
                    style: const TextStyle(
                      color: charcoal,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 2),
          // Points left, worth right; the worth drops below at large text.
          SizedBox(
            width: double.infinity,
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.end,
              spacing: 12,
              runSpacing: 2,
              children: [
                Text(
                  formatPts(g.cash),
                  key: const Key('run-cash'),
                  style: TextStyle(
                    fontFamily: headingFont,
                    fontWeight: FontWeight.w700,
                    fontSize: 30,
                    height: 1.1,
                    color: on,
                    fontFeatures: tabular,
                  ),
                ),
                Column(
                  key: const Key('run-worth'),
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      tr('Sack worth {n}', {'n': fmt(g.sack)}),
                      textAlign: TextAlign.end,
                      style: worthStyle,
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (float) floatDelta,
                        Flexible(
                          child: Text(
                            tr('Total {n}', {'n': fmt(g.total)}),
                            textAlign: TextAlign.end,
                            style: worthStyle,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          ExcludeSemantics(
            child: Row(
              children: [
                for (var i = 0; i < kDays; i++) ...[
                  if (i > 0) const SizedBox(width: 5),
                  Expanded(
                    child: Container(
                      height: 5,
                      decoration: BoxDecoration(
                        color: i < g.day
                            ? t.ochre
                            : Colors.white.withValues(alpha: .25),
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// "Radio was right/wrong" banner after each night. Tick or cross plus colour.
class RunRevealBanner extends StatelessWidget {
  const RunRevealBanner(this.g, {super.key});
  final RunGame g;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final right = g.reveal!.rumour.truth;
    final c = right ? t.up : t.down;
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: c.withValues(alpha: .14),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            Icon(right ? Icons.check_circle : Icons.cancel, color: c, size: 24),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                revealText(g),
                style: TextStyle(
                  color: c,
                  fontWeight: FontWeight.w600,
                  fontSize: 15,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Radio Soko card: tomorrow's news, or the closing notice on the last day.
class RunRadioCard extends StatelessWidget {
  const RunRadioCard(
    this.g, {
    super.key,
    required this.fx,
    required this.still,
  });
  final RunGame g;
  final Animation<double> fx;
  final bool still;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final cs = Theme.of(context).colorScheme;
    final r = g.rumour;
    final label = r == null
        ? '${tr('Radio Soko')} · ${tr('Last day')}'
        : '${tr('Radio Soko')} · Habari za kesho';
    final news = r == null
        ? tr(
            'The soko closes tonight. Everything in your sack is sold at today\'s prices.',
          )
        : r.text; // TODO(sw): news lines stay English until a native pass.
    Widget icon = const SizedBox(width: 40, height: 40, child: RadioIcon());
    if (!still && g.reveal != null) {
      icon = AnimatedBuilder(
        animation: fx,
        builder: (_, child) => Transform.rotate(
          angle: -math.sin(fx.value * 4 * math.pi) * 8 * math.pi / 180,
          child: child,
        ),
        child: icon,
      );
    }
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: t.card,
        border: Border.all(color: t.ochre, width: 2),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ExcludeSemantics(child: icon),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label.toUpperCase(),
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: .7,
                    color: cs.primary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  news,
                  key: const Key('run-news'),
                  style: const TextStyle(
                    fontFamily: headingFont,
                    fontWeight: FontWeight.w600,
                    fontSize: 18,
                    height: 1.25,
                  ),
                ),
                if (r != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    tr('Radio Soko is right about 3 times in 4.'),
                    style: TextStyle(fontSize: 12.5, color: t.muted),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The prototype's little radio, drawn so it needs no image or emoji font.
class RadioIcon extends StatelessWidget {
  const RadioIcon({super.key});
  @override
  Widget build(BuildContext context) => CustomPaint(
    painter: _RadioPainter(
      body: kitengeRed,
      dial: context.tokens.ochre,
      grille: Theme.of(context).colorScheme.surface,
      aerial: Theme.of(context).colorScheme.onSurface,
    ),
  );
}

class _RadioPainter extends CustomPainter {
  _RadioPainter({
    required this.body,
    required this.dial,
    required this.grille,
    required this.aerial,
  });
  final Color body, dial, grille, aerial;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 40, size.height / 40);
    final p = Paint();
    canvas.drawLine(
      const Offset(10, 12),
      const Offset(28, 4),
      Paint()
        ..color = aerial
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawRRect(
      RRect.fromLTRBR(4, 12, 36, 34, const Radius.circular(5)),
      p..color = body,
    );
    canvas.drawCircle(const Offset(14, 23), 6, p..color = dial);
    canvas.drawCircle(const Offset(14, 23), 2.2, p..color = body);
    for (final y in [18.0, 24.0]) {
      canvas.drawRRect(
        RRect.fromLTRBR(23, y, 32, y + 3, const Radius.circular(1.5)),
        p..color = grille,
      );
    }
  }

  @override
  bool shouldRepaint(_RadioPainter o) =>
      o.body != body || o.dial != dial || o.grille != grille;
}

/// First-run hint on an ochre card. [onClose] adds a close button.
class RunHint extends StatelessWidget {
  const RunHint(this.text, {super.key, this.onClose});
  final String text;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(12, 10, onClose == null ? 12 : 0, 10),
      decoration: BoxDecoration(
        color: context.tokens.ochre,
        borderRadius: BorderRadius.circular(14),
        boxShadow: const [
          BoxShadow(
            color: Color(0x1F785010),
            blurRadius: 10,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 1, right: 10),
            child: Icon(Icons.lightbulb_outline, color: charcoal, size: 20),
          ),
          Expanded(
            child: boldSpans(
              text,
              const TextStyle(
                color: charcoal,
                fontWeight: FontWeight.w600,
                fontSize: 14,
                height: 1.35,
              ),
            ),
          ),
          if (onClose != null)
            IconButton(
              tooltip: tr('Close hint'),
              color: charcoal,
              icon: const Icon(Icons.close, size: 20),
              onPressed: onClose,
            ),
        ],
      ),
    );
  }
}

/// One good: icon, name, price, change since yesterday, what you hold and its
/// gain or loss, then Buy and Sell with exact amounts. Press and hold repeats.
class RunGoodRow extends StatelessWidget {
  const RunGoodRow(
    this.g,
    this.id, {
    super.key,
    required this.fx,
    required this.still,
    required this.onTrade,
  });
  final RunGame g;
  final String id;
  final Animation<double> fx;
  final bool still;

  /// Returns true if the trade went through.
  final bool Function(String id, {required bool buy}) onTrade;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final cs = Theme.of(context).colorScheme;
    final now = g.prices[id]!;
    final was = g.reveal?.old[id];
    final name = runGoodName(id);
    final flash = !still && was != null && (now - was).abs() / was > 0.2
        ? (now > was ? t.up : t.down).withValues(alpha: .16)
        : null;

    final pc = g.changePct(id);
    final Widget change;
    if (pc == null) {
      change = Text(
        tr('today'),
        style: TextStyle(fontSize: 12.5, color: t.muted),
      );
    } else if (pc > 2 || pc < -2) {
      final up = pc > 2;
      final c = up ? t.up : t.down;
      change = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(up ? Icons.arrow_drop_up : Icons.arrow_drop_down, color: c),
          Text(
            '${up ? '+' : ''}$pc%',
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: c,
              fontFeatures: tabular,
            ),
          ),
        ],
      );
    } else {
      change = Text(
        tr('same'),
        style: TextStyle(
          fontSize: 12.5,
          fontWeight: FontWeight.w700,
          color: t.muted,
        ),
      );
    }

    final h = g.hold[id]!;
    final gain = g.gainPct(id);
    final muted = TextStyle(
      fontSize: 13,
      color: t.muted,
      fontFeatures: tabular,
    );
    final have = Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text:
                '${tr('You have {n}', {'n': h})}'
                '${h >= kMaxHold ? ' ${tr('(full)')}' : ''}',
          ),
          if (gain != null && gain != 0)
            TextSpan(
              text:
                  ' · ${tr('{p}% on what you paid', {'p': gain > 0 ? '+$gain' : '$gain'})}',
              style: TextStyle(
                color: gain > 0 ? t.up : t.down,
                fontWeight: FontWeight.w600,
              ),
            ),
        ],
      ),
      key: Key('have-$id'),
      style: muted,
    );

    final priceStyle = TextStyle(
      fontFamily: headingFont,
      fontWeight: FontWeight.w700,
      fontSize: 24,
      height: 1,
      fontFeatures: tabular,
      color: cs.onSurface,
    );
    final Widget price = still || was == null
        ? Text(fmt(now), key: Key('price-$id'), style: priceStyle)
        : AnimatedBuilder(
            animation: fx,
            builder: (_, _) {
              final k = Curves.easeOutCubic.transform(_phase(fx, 700));
              return Text(
                fmt((was + (now - was) * k).round()),
                key: Key('price-$id'),
                style: priceStyle,
              );
            },
          );

    final canBuy = g.canBuy(id), canSell = g.canSell(id);
    final buyCost = g.buyCost(id), sellNet = g.sellNet(id);
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(14),
    );
    const pad = EdgeInsets.symmetric(horizontal: 8, vertical: 4);
    Widget label(String verb, String amount, String sem) => Semantics(
      label: sem,
      excludeSemantics: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            verb,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
          ),
          Text(
            amount,
            style: const TextStyle(
              fontWeight: FontWeight.w500,
              fontSize: 11.5,
              fontFeatures: tabular,
            ),
          ),
        ],
      ),
    );

    final buyBtn = HoldRepeat(
      onRepeat: () => onTrade(id, buy: true),
      child: FilledButton(
        key: Key('buy-$id'),
        style: FilledButton.styleFrom(
          minimumSize: const Size(48, 48),
          padding: pad,
          shape: shape,
        ),
        onPressed: canBuy ? () => onTrade(id, buy: true) : null,
        child: label(
          tr('Buy'),
          '-${fmt(buyCost)}',
          tr('Buy one {g} for {p} pts', {'g': name, 'p': fmt(buyCost)}),
        ),
      ),
    );
    final sellBtn = HoldRepeat(
      onRepeat: () => onTrade(id, buy: false),
      child: OutlinedButton(
        key: Key('sell-$id'),
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(48, 48),
          padding: pad,
          shape: shape,
          foregroundColor: cs.onSurface,
          side: BorderSide(
            color: canSell ? cs.onSurface : cs.onSurface.withValues(alpha: .3),
            width: 2,
          ),
        ),
        onPressed: canSell ? () => onTrade(id, buy: false) : null,
        child: label(
          tr('Sell'),
          '+${fmt(sellNet)}',
          tr('Sell one {g} for {p} pts', {'g': name, 'p': fmt(sellNet)}),
        ),
      ),
    );

    Widget card(Color bg) => Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: bg,
        border: Border.all(color: cs.outlineVariant),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        children: [
          MergeSemantics(
            child: Row(
              children: [
                GoodIcon(id, size: 48),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: const TextStyle(
                          fontFamily: headingFont,
                          fontWeight: FontWeight.w700,
                          fontSize: 18,
                        ),
                      ),
                      have,
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [price, const SizedBox(height: 2), change],
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(child: buyBtn),
              const SizedBox(width: 8),
              Expanded(child: sellBtn),
            ],
          ),
        ],
      ),
    );

    if (flash == null) return card(t.card);
    return AnimatedBuilder(
      animation: fx,
      builder: (_, _) {
        final k = _phase(fx, 900);
        final a = k < .75 ? 1.0 : (1 - k) / .25;
        return card(Color.lerp(t.card, Color.alphaBlend(flash, t.card), a)!);
      },
    );
  }
}

/// Press and hold to repeat [onRepeat] every 90 ms after a 380 ms hold.
/// A plain tap is left to the child button, so scrolling never trades.
class HoldRepeat extends StatefulWidget {
  const HoldRepeat({super.key, required this.onRepeat, required this.child});

  /// Returns false to stop repeating.
  final bool Function() onRepeat;
  final Widget child;

  @override
  State<HoldRepeat> createState() => _HoldRepeatState();
}

class _HoldRepeatState extends State<HoldRepeat> {
  Timer? _timer;

  void _start() {
    _stop();
    if (!widget.onRepeat()) return;
    _timer = Timer.periodic(const Duration(milliseconds: 90), (_) {
      if (!mounted || !widget.onRepeat()) _stop();
    });
  }

  void _stop() {
    _timer?.cancel();
    _timer = null;
  }

  @override
  void dispose() {
    _stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RawGestureDetector(
    excludeFromSemantics: true,
    gestures: {
      LongPressGestureRecognizer:
          GestureRecognizerFactoryWithHandlers<LongPressGestureRecognizer>(
            () => LongPressGestureRecognizer(
              duration: const Duration(milliseconds: 380),
            ),
            (r) => r
              ..onLongPressStart = ((_) => _start())
              ..onLongPressEnd = ((_) => _stop())
              ..onLongPressCancel = _stop,
          ),
    },
    child: widget.child,
  );
}

/// Night squares: up, down or flat, drawn with icons (no emoji font needed).
class RunSquares extends StatelessWidget {
  const RunSquares(this.squares, {super.key});
  final List<RunSquare> squares;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final cs = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    int n(RunSquare s) => squares.where((x) => x == s).length;
    return Semantics(
      label: tr('Day by day: {u} up, {d} down, {f} flat', {
        'u': n(RunSquare.up),
        'd': n(RunSquare.down),
        'f': n(RunSquare.flat),
      }),
      excludeSemantics: true,
      child: Wrap(
        spacing: 4,
        runSpacing: 4,
        children: [
          for (final s in squares)
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: switch (s) {
                  RunSquare.up => t.up,
                  RunSquare.down => t.down,
                  RunSquare.flat => cs.outlineVariant,
                },
                borderRadius: BorderRadius.circular(6),
              ),
              child: Icon(
                switch (s) {
                  RunSquare.up => Icons.trending_up,
                  RunSquare.down => Icons.trending_down,
                  RunSquare.flat => Icons.remove,
                },
                size: 18,
                color: s == RunSquare.flat
                    ? t.muted
                    : (dark ? charcoal : Colors.white),
              ),
            ),
        ],
      ),
    );
  }
}

/// Emoji row for the share text (copied as text, so emoji are fine there).
String runSquaresEmoji(List<RunSquare> s) => s
    .map(
      (x) => switch (x) {
        RunSquare.up => '\u{1F4C8}',
        RunSquare.down => '\u{1F4C9}',
        RunSquare.flat => '⬜',
      },
    )
    .join();
