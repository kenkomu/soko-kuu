import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/models.dart';
import '../state/providers.dart';
import '../state/news_stories.dart';
import '../state/trade_book.dart';
import '../l10n.dart';
import 'kit/feel.dart';
import 'theme.dart';
import 'widgets.dart';

/// English / Swahili inline pair for text that has no tr() key.
String _bi(String en, String sw, [Map<String, Object>? p]) {
  var s = gLang == 'sw' ? sw : en;
  p?.forEach((k, v) => s = s.replaceAll('{$k}', '$v'));
  return s;
}

/// Round chip with the merchant's initial, coloured by a stable pick.
class MerchantChip extends StatelessWidget {
  const MerchantChip(this.merchant, {super.key, this.size = 44});
  final String merchant;
  final double size;
  @override
  Widget build(BuildContext context) {
    final k = context.tokens.kitenge;
    final c = k[merchant.codeUnits.fold<int>(0, (a, b) => a + b) % k.length];
    return ExcludeSemantics(
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: c, shape: BoxShape.circle),
        child: Text(
          merchant.isEmpty ? '?' : merchant[0].toUpperCase(),
          textScaler: TextScaler.noScaling,
          style: TextStyle(
            fontFamily: headingFont,
            color: Colors.white,
            fontWeight: FontWeight.w700,
            fontSize: size * .45,
          ),
        ),
      ),
    );
  }
}

void _openTrade(BuildContext context, List<PriceRow> rows) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => TradeSheet(rows),
    );

/// Cheapest ask across merchants (first wins a tie).
PriceRow cheapestAsk(List<PriceRow> rows) =>
    rows.reduce((a, b) => b.ask < a.ask ? b : a);

/// Highest bid across merchants (first wins a tie).
PriceRow highestBid(List<PriceRow> rows) =>
    rows.reduce((a, b) => b.bid > a.bid ? b : a);

/// Today against yesterday, summed over merchants that have both days.
/// Positive = dearer today.
int trendOf(List<PriceRow> rows) {
  var d = 0;
  for (final r in rows) {
    final h = r.history;
    if (h.length >= 2) d += h.last - h[h.length - 2];
  }
  return d;
}

/// Players' goods in a stable order: market order of first appearance.
Map<String, List<PriceRow>> groupByGood(List<PriceRow> prices) {
  final m = <String, List<PriceRow>>{};
  for (final p in prices) {
    (m[p.good] ??= []).add(p);
  }
  return m;
}

class MarketScreen extends ConsumerStatefulWidget {
  const MarketScreen({super.key});
  @override
  ConsumerState<MarketScreen> createState() => _MarketScreenState();
}

class _MarketScreenState extends ConsumerState<MarketScreen> {
  Object? _seen;
  DateTime _at = DateTime.now();
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 5), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  String _fresh() {
    final s = DateTime.now().difference(_at).inSeconds;
    if (s < 5) return _bi('Updated just now', 'Imesasishwa sasa hivi');
    if (s < 60) {
      return _bi('Updated {n}s ago', 'Imesasishwa sekunde {n} zilizopita', {
        'n': s,
      });
    }
    return _bi('Updated {n} min ago', 'Imesasishwa dakika {n} zilizopita', {
      'n': s ~/ 60,
    });
  }

  @override
  Widget build(BuildContext context) {
    final gs = ref.watch(gameProvider).value;
    if (gs == null) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
        children: [
          for (var i = 0; i < 4; i++)
            const Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: Skeleton(height: 116, radius: 18),
            ),
        ],
      );
    }
    if (!identical(_seen, gs)) {
      _seen = gs;
      _at = DateTime.now();
    }
    final tt = Theme.of(context).textTheme;
    return RefreshIndicator(
      onRefresh: () => ref.read(gameProvider.notifier).refresh(),
      child: ListView(
        scrollCacheExtent: const ScrollCacheExtent.pixels(
          4000,
        ), // a short list: keep every row built
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
        children: [
          const _SackStrip(),
          const _TopCard(),
          Text(
            tr('Points are for play only. They can\'t be cashed out.'),
            style: tt.bodySmall,
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tr('Bei za leo (today\'s prices)'),
                  style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                ),
                Text(
                  _fresh(),
                  style: tt.bodySmall?.copyWith(color: context.tokens.muted),
                ),
              ],
            ),
          ),
          if (gs.prices.isEmpty)
            EmptyState(
              _bi(
                'No prices are posted yet. Pull down to refresh.',
                'Bei bado hazijatangazwa. Vuta chini kusasisha.',
              ),
            ),
          for (final e in groupByGood(gs.prices).entries) ...[
            _GoodRow(e.value),
            const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }
}

/// One clean row per good: icon, name, best buy and sell prices, a small
/// arrow against yesterday. The whole row opens the details sheet.
class _GoodRow extends StatelessWidget {
  const _GoodRow(this.rows);
  final List<PriceRow> rows;
  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final tk = context.tokens;
    final good = rows.first.good;
    final name = goodName(good);
    final buy = cheapestAsk(rows).ask, sell = highestBid(rows).bid;
    final t = trendOf(rows);
    final word = t > 0
        ? tr('up on yesterday')
        : t < 0
        ? tr('down on yesterday')
        : tr('same as yesterday');
    final arrow = t > 0
        ? Icons.arrow_upward
        : t < 0
        ? Icons.arrow_downward
        : Icons.remove;
    final col = t > 0 ? tk.up : (t < 0 ? tk.down : tk.muted);
    return PressSquish(
      onTap: () => _openTrade(context, rows),
      semanticLabel: tr('{g}: buy {b}, sell {s}, {t}. Open for details.', {
        'g': name,
        'b': fmt(buy),
        's': fmt(sell),
        't': word,
      }),
      child: SokoCard(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 56),
          child: Row(
            children: [
              GoodIcon(good, size: 32),
              const SizedBox(width: 12),
              Expanded(
                flex: 5,
                child: Text(
                  name,
                  style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 6,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerRight,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Num(
                        tr('Buy {p}', {'p': fmt(buy)}),
                        style: tt.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Num(
                        tr('Sell {p}', {'p': fmt(sell)}),
                        style: tt.bodyMedium?.copyWith(color: tk.muted),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Icon(arrow, size: 20, color: col),
            ],
          ),
        ),
      ),
    );
  }
}

/// "Your sack": what the player holds and whether it is worth more or less
/// than they paid (average paid, from the trade log, against today's best
/// sell price). One line when empty.
class _SackStrip extends ConsumerWidget {
  const _SackStrip();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final g = ref.watch(gameProvider).value;
    if (g == null) return const SizedBox.shrink();
    final book = TradeBook(ref.watch(prefsProvider));
    final tt = Theme.of(context).textTheme;
    final tk = context.tokens;
    final by = groupByGood(g.prices);
    final held = g.player.stock.entries.where((e) => e.value > 0).toList();
    Widget wrap(Widget c) => Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Semantics(container: true, child: c),
    );
    if (held.isEmpty) {
      return wrap(
        Row(
          children: [
            Icon(Icons.shopping_basket_outlined, size: 20, color: tk.muted),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                tr(
                  'Your sack is empty. Buy something cheap and sell it when the price goes up.',
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: tt.bodySmall,
              ),
            ),
          ],
        ),
      );
    }
    final chips = <Widget>[];
    for (final e in held) {
      final name = goodName(e.key);
      final rows = by[e.key];
      final avg = book.avgCost(e.key);
      int? pct;
      if (avg != null && avg > 0 && rows != null && rows.isNotEmpty) {
        pct = ((highestBid(rows).bid - avg) * 100 / avg).round();
      }
      final up = (pct ?? 0) > 0, down = (pct ?? 0) < 0;
      final col = pct == null
          ? tk.muted
          : (up ? tk.up : (down ? tk.down : tk.muted));
      final sign = '${up ? '+' : ''}$pct%';
      chips.add(
        Semantics(
          label: pct == null
              ? tr('{g}, {n} in your sack', {'g': name, 'n': e.value})
              : tr(
                  up
                      ? '{g}, {n} in your sack, worth {p}% more than you paid'
                      : down
                      ? '{g}, {n} in your sack, worth {p}% less than you paid'
                      : '{g}, {n} in your sack, worth what you paid',
                  {'g': name, 'n': e.value, 'p': pct.abs()},
                ),
          excludeSemantics: true,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                color: col.withValues(alpha: .12),
                borderRadius: BorderRadius.circular(24),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  GoodIcon(e.key, size: 24),
                  const SizedBox(width: 6),
                  Text(
                    '$name x${e.value}',
                    style: tt.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  if (pct != null) ...[
                    const SizedBox(width: 6),
                    Icon(
                      up
                          ? Icons.arrow_upward
                          : down
                          ? Icons.arrow_downward
                          : Icons.remove,
                      size: 16,
                      color: col,
                    ),
                    Text(
                      sign,
                      style: tt.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: col,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      );
    }
    return wrap(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            tr('Your sack'),
            style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          Wrap(spacing: 8, runSpacing: 8, children: chips),
        ],
      ),
    );
  }
}

class _Stepper extends StatelessWidget {
  const _Stepper({
    required this.qty,
    required this.max,
    required this.name,
    required this.onChanged,
  });
  final int qty, max;
  final String name;
  final ValueChanged<int> onChanged;
  @override
  Widget build(BuildContext context) {
    Widget btn(IconData i, String label, int to, bool on) => IconButton(
      constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
      tooltip: label,
      onPressed: on
          ? () {
              Feel.select();
              onChanged(to);
            }
          : null,
      icon: Icon(i),
    );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        btn(
          Icons.remove,
          _bi('Fewer {g}', 'Punguza {g}', {'g': name}),
          qty - 1,
          qty > 1,
        ),
        Semantics(
          label: _bi('Quantity {n}', 'Kiasi {n}', {'n': qty}),
          excludeSemantics: true,
          child: SizedBox(
            width: 32,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Num(
                '$qty',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ),
        btn(
          Icons.add,
          _bi('More {g}', 'Ongeza {g}', {'g': name}),
          qty + 1,
          qty < max,
        ),
      ],
    );
  }
}

/// Details and actions for one good: buys from the cheapest-ask merchant,
/// sells to the highest-bid merchant. [rows] are all merchants for that good.
class TradeSheet extends ConsumerStatefulWidget {
  const TradeSheet(this.rows, {super.key, this.initialQty = 1});
  final List<PriceRow> rows;
  final int initialQty;
  @override
  ConsumerState<TradeSheet> createState() => _TradeSheetState();
}

class _TradeSheetState extends ConsumerState<TradeSheet> {
  late int qty = widget.initialQty < 1 ? 1 : widget.initialQty;
  bool busy = false;
  bool showWhy = true; // the explanation is the point of tapping a row
  TradeResult? result;

  Future<void> _go(Map<String, dynamic> a) async {
    setState(() => busy = true);
    final err = await ref.read(gameProvider.notifier).act(a);
    if (!mounted) return;
    setState(() => busy = false);
    if (err != null) {
      toast(context, err, error: true);
    } else {
      final r = a['type'] == 'sell'
          ? ref.read(gameProvider.notifier).takeResult()
          : null;
      if (r != null) {
        Feel.saleTick();
        setState(() => result = r);
        return;
      }
      Feel.light();
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = cheapestAsk(widget.rows); // buy here
    final sellRow = highestBid(widget.rows); // sell here
    final tt = Theme.of(context).textTheme;
    final tk = context.tokens;
    final lang = ref.watch(langProvider);
    final g = ref.watch(gameProvider).requireValue.player;
    final held = g.stock[p.good] ?? 0;
    final maxBuy = p.stock.clamp(1, 50);
    final maxQty = maxBuy > held ? maxBuy : held.clamp(1, 50);
    if (qty > maxQty) qty = maxQty;
    // Allow the price to drift up to 3% before the order is refused.
    final maxUnit = p.ask + (p.ask * 3 ~/ 100);
    final cost = p.ask * qty;
    final worst = maxUnit * qty;
    final afford = cost <= g.pts && qty <= p.stock;
    final open = g.phase == Phase.midday;
    final sellQty = held < qty ? held : qty;
    final name = goodName(p.good);
    final res = result;
    if (res != null) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: SaleResultView(res, onDone: () => Navigator.pop(context)),
      );
    }

    Widget line(String k, Widget v) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: Text(k, style: tt.bodyMedium)),
          const SizedBox(width: 8),
          Flexible(child: v),
        ],
      ),
    );

    return Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        0,
        16,
        16 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                GoodIcon(p.good, size: 36),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    name,
                    style: tt.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 16,
              runSpacing: 4,
              children: [
                Num(
                  tr('Best to buy from: {m} at {p}', {
                    'm': titleCase(p.merchant),
                    'p': pts(p.ask),
                  }),
                ),
                Num(
                  tr('Best to sell to: {m} at {p}', {
                    'm': titleCase(sellRow.merchant),
                    'p': pts(sellRow.bid),
                  }),
                ),
                Num(tr('You hold {n}', {'n': held})),
              ],
            ),
            if (p.history.length >= 2)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: LayoutBuilder(
                  builder: (c, bc) => Sparkline(
                    p.history,
                    width: bc.maxWidth,
                    height: 40,
                    semanticLabel: _bi(
                      'Price history, {n} days',
                      'Historia ya bei, siku {n}',
                      {'n': p.history.length},
                    ),
                  ),
                ),
              ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(child: Text(tr('Quantity'))),
                _Stepper(
                  qty: qty,
                  max: maxQty,
                  name: name,
                  onChanged: (v) => setState(() => qty = v),
                ),
              ],
            ),
            SokoCard(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  line(
                    _bi('Total for {q}', 'Jumla ya {q}', {'q': qty}),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerRight,
                      child: RollingNumber(
                        cost,
                        format: pts,
                        textAlign: TextAlign.end,
                        style: Money.baseStyle(context).copyWith(fontSize: 20),
                      ),
                    ),
                  ),
                  line(
                    _bi(
                      'Most you could pay if the price moves up to 3%',
                      'Upeo ungelipa bei ikipanda hadi 3%',
                    ),
                    Num(
                      '${pts(worst)} (+${fmt(worst - cost)})',
                      textAlign: TextAlign.end,
                    ),
                  ),
                  line(
                    _bi('Points left after buying', 'Pointi zitakazobaki'),
                    Num(
                      afford ? pts(g.pts - cost) : '—',
                      textAlign: TextAlign.end,
                    ),
                  ),
                  line(
                    _bi(
                      'Selling {s} now brings about',
                      'Kuuza {s} sasa kunaleta takriban',
                      {'s': sellQty},
                    ),
                    Num(pts(sellRow.bid * sellQty), textAlign: TextAlign.end),
                  ),
                ],
              ),
            ),
            if (!afford)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, size: 18, color: tk.down),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        tr('Not enough pts for this quantity.'),
                        style: TextStyle(color: tk.down),
                      ),
                    ),
                  ],
                ),
              ),
            if (!open)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Row(
                  children: [
                    Icon(Icons.schedule, size: 18, color: tk.down),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        tr('The market trades at midday. Come back then.'),
                        style: TextStyle(color: tk.down),
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: FilledButton(
                    onPressed: busy || !open || !afford
                        ? null
                        : () => _go({
                            'type': 'buy',
                            'merchant': p.merchant,
                            'good': p.good,
                            'qty': qty,
                            'max_unit_price': maxUnit,
                          }),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(tr('Buy')),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    onPressed: busy || !open || held < qty
                        ? null
                        : () => _go({
                            'type': 'sell',
                            'merchant': sellRow.merchant,
                            'good': p.good,
                            'qty': qty,
                            'min_unit_price':
                                sellRow.bid - sellRow.bid * 3 ~/ 100,
                          }),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(tr('Sell')),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _Shopkeeper(
              merchant: p.merchant,
              why: p.why.map((w) => whyText(w, lang)).toList(),
              showWhy: showWhy,
              onToggleWhy: () => setState(() => showWhy = !showWhy),
              onHaggle: busy || !open
                  ? null
                  : () => _go({
                      'type': 'haggle',
                      'merchant': p.merchant,
                      'good': p.good,
                    }),
            ),
          ],
        ),
      ),
    );
  }
}

/// Cream card, portrait overlapping the top edge, one line, ask-for-discount.
class _Shopkeeper extends StatelessWidget {
  const _Shopkeeper({
    required this.merchant,
    required this.why,
    required this.showWhy,
    required this.onToggleWhy,
    required this.onHaggle,
  });
  final String merchant;
  final List<String> why;
  final bool showWhy;
  final VoidCallback onToggleWhy;
  final VoidCallback? onHaggle;
  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final m = titleCase(merchant);
    const r = 32.0;
    return Padding(
      padding: const EdgeInsets.only(top: r),
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.topCenter,
        children: [
          SokoCard(
            padding: const EdgeInsets.fromLTRB(16, r + 8, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  m,
                  textAlign: TextAlign.center,
                  style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                Text(
                  _bi(
                    'Karibu. Ask nicely and I may lower the price a little.',
                    'Karibu. Omba kwa heshima, huenda nikashusha bei kidogo.',
                  ),
                  textAlign: TextAlign.center,
                  style: tt.bodyMedium,
                ),
                const SizedBox(height: 8),
                FilledButton.tonal(
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(48, 48),
                  ),
                  onPressed: onHaggle,
                  child: Text(
                    _bi('Ask for a discount (Omba punguzo)', 'Omba punguzo'),
                    textAlign: TextAlign.center,
                  ),
                ),
                TextButton.icon(
                  style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
                  onPressed: onToggleWhy,
                  iconAlignment: IconAlignment.end,
                  icon: AnimatedRotation(
                    turns: showWhy ? .5 : 0,
                    duration: reduceMotion(context)
                        ? Duration.zero
                        : const Duration(milliseconds: 220),
                    child: const Icon(Icons.expand_more),
                  ),
                  label: Text(
                    _bi('Why this price?', 'Kwa nini bei hii?'),
                    textAlign: TextAlign.center,
                  ),
                ),
                AnimatedSize(
                  duration: reduceMotion(context)
                      ? Duration.zero
                      : const Duration(milliseconds: 240),
                  curve: Curves.easeOutCubic,
                  alignment: Alignment.topCenter,
                  child: !showWhy
                      ? const SizedBox(width: double.infinity)
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (why.isEmpty) Text(tr('No explanation yet.')),
                            for (var i = 0; i < why.length; i++)
                              _WhyLine(why[i], i),
                          ],
                        ),
                ),
              ],
            ),
          ),
          Positioned(
            top: -r,
            child: MerchantChip(merchant, size: r * 2),
          ),
        ],
      ),
    );
  }
}

/// Guided first day. Skip is always visible; it ends after the first sale.
class _Tutorial extends ConsumerStatefulWidget {
  const _Tutorial({this.onDismiss});
  final VoidCallback? onDismiss;
  @override
  ConsumerState<_Tutorial> createState() => _TutorialState();
}

class _TutorialState extends ConsumerState<_Tutorial> {
  @override
  Widget build(BuildContext context) {
    final prefs = ref.watch(prefsProvider);
    final lang = ref.watch(langProvider);
    final g = ref.watch(gameProvider).requireValue;
    if (prefs.getBool('tut_done') ?? false) return const SizedBox.shrink();
    final held = g.player.stock.values.any((v) => v > 0);
    final key = held ? 's3' : (g.player.phase == Phase.midday ? 's2' : 's1');
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Card(
        margin: EdgeInsets.zero,
        color: ochre.withValues(alpha: .25),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Row(
            children: [
              const Icon(Icons.school_outlined),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      tutorial['title']![lang]!,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    Text(tutorial[key]![lang]!),
                  ],
                ),
              ),
              TextButton(
                onPressed: () {
                  prefs.setBool('tut_done', true);
                  setState(() {});
                  widget.onDismiss?.call();
                },
                child: Text(tutorial['skip']![lang]!),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One "why" sentence that fades and slides in, a little after the one above.
class _WhyLine extends StatelessWidget {
  const _WhyLine(this.text, this.index);
  final String text;
  final int index;
  @override
  Widget build(BuildContext context) {
    final line = Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text('\u2022 $text'),
    );
    if (reduceMotion(context)) return line;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 260 + 70 * index),
      curve: Curves.easeOut,
      builder: (_, v, child) => Opacity(
        opacity: v,
        child: Transform.translate(
          offset: Offset(0, 8 * (1 - v)),
          child: child,
        ),
      ),
      child: line,
    );
  }
}

/// After a sale: profit or loss in big rolling digits, a faida/hasara line and
/// one sentence of why. A first loss is framed as a lesson, never an error.
class SaleResultView extends StatelessWidget {
  const SaleResultView(this.r, {super.key, required this.onDone});
  final TradeResult r;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final tk = context.tokens;
    final name = goodName(r.good);
    final d = r.delta;
    final loss = d < 0;
    final even = d == 0;
    final col = even ? tt.titleMedium!.color : (loss ? tk.ochre : tk.up);
    final amt = fmt(d.abs());
    final head = even
        ? _bi(
            'Even: no gain, no loss on $name.',
            'Sawa: hakuna faida wala hasara kwa $name.',
          )
        : loss
        ? _bi(
            'Hasara (loss): you lost $amt pts on $name.',
            'Hasara: umepoteza pointi $amt kwa $name.',
          )
        : _bi(
            'Faida (profit): you made $amt pts on $name!',
            'Faida! Umepata pointi $amt kwa $name.',
          );
    final c = fmt(r.avgCost), s = fmt(r.unitPrice);
    final reason = !loss && !even
        ? _bi(
            'You paid about $c each and sold at $s each.',
            'Ulinunua kwa takriban $c kila moja, ukauza kwa $s.',
          )
        : r.sameDay
        ? _bi(
            'The shop buys for less than it sells, so selling right after buying costs you the gap.',
            'Duka linanunua kwa bei ya chini kuliko linavyouza, kwa hiyo kuuza mara tu baada ya kununua kunakugharimu tofauti hiyo.',
          )
        : _bi(
            'The price fell since you bought: you paid about $c each and got $s.',
            'Bei imeshuka tangu ununue: ulilipa takriban $c kila moja, ukapata $s.',
          );
    final fix = !loss
        ? null
        : r.sameDay
        ? _bi(
            'Try this: hold it until the price is above $c, then sell.',
            'Jaribu hivi: shikilia mpaka bei iwe juu ya $c, kisha uze.',
          )
        : _bi(
            'Try this: open "Why this price?" before you buy, and sell once the price is back above $c.',
            'Jaribu hivi: soma "Kwa nini bei hii?" kabla ya kununua, kisha uze bei ikirudi juu ya $c.',
          );
    return Semantics(
      liveRegion: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (loss && r.firstSale)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Icon(Icons.lightbulb_outline, color: tk.ochre),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _bi(
                        'Your first lesson from the soko. This is how trading works, not a mistake.',
                        'Somo lako la kwanza sokoni. Hii ndiyo biashara, si kosa.',
                      ),
                      style: tt.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          Center(
            child: RollingNumber(
              d,
              duration: const Duration(milliseconds: 900),
              format: (n) =>
                  '${n > 0
                      ? '+'
                      : n < 0
                      ? '-'
                      : ''}${fmt(n.abs())} pts',
              style: (tt.displaySmall ?? const TextStyle()).copyWith(
                fontFamily: headingFont,
                fontWeight: FontWeight.w700,
                color: col,
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            head,
            textAlign: TextAlign.center,
            style: tt.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: col,
            ),
          ),
          const SizedBox(height: 8),
          Text(reason, textAlign: TextAlign.center),
          if (fix != null) ...[
            const SizedBox(height: 8),
            Text(
              fix,
              textAlign: TextAlign.center,
              style: tt.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
          ],
          const SizedBox(height: 16),
          FilledButton(onPressed: onDone, child: Text(_bi('Done', 'Sawa'))),
        ],
      ),
    );
  }
}

/// Radio Soko tips for today's bulletins and the real outcome on later days.
/// Hints only, never promises. Shows nothing when there is nothing to say.
class _RadioTips extends ConsumerWidget {
  const _RadioTips();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list = ref.watch(storiesProvider);
    if (list.isEmpty) return const SizedBox.shrink();
    final lang = ref.watch(langProvider);
    final tt = Theme.of(context).textTheme;
    final tk = context.tokens;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: SokoCard(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.radio_outlined, size: 20, color: tk.ochre),
                const SizedBox(width: 8),
                Text(
                  'Radio Soko',
                  style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w800),
                ),
              ],
            ),
            for (final v in list)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  v.now == null ? tipText(v.story, lang) : outcomeText(v, lang),
                  style: tt.bodyMedium,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// One small optional goal: first profit, then beat your best day.
class _GoalCard extends ConsumerStatefulWidget {
  const _GoalCard({this.onDismiss});
  final VoidCallback? onDismiss;
  @override
  ConsumerState<_GoalCard> createState() => _GoalCardState();
}

class _GoalCardState extends ConsumerState<_GoalCard> {
  @override
  Widget build(BuildContext context) {
    final prefs = ref.watch(prefsProvider);
    final g = ref.watch(gameProvider).value;
    if (g == null || !goalActive(prefs, g.player.day)) {
      return const SizedBox.shrink();
    }
    final book = TradeBook(prefs);
    final d = book.days(g.player.day);
    final first = !book.hadProfit;
    final tt = Theme.of(context).textTheme;
    final tk = context.tokens;
    final title = first
        ? _bi('Make your first profit', 'Pata faida yako ya kwanza')
        : _bi('Beat your best day', 'Shinda siku yako bora');
    final sub = first
        ? _bi(
            'Buy at midday, then sell for more than you paid.',
            'Nunua adhuhuri, kisha uze kwa zaidi ya ulivyolipa.',
          )
        : d.best <= 0
        ? _bi(
            'Sell above what you paid to set a best day.',
            'Uza juu ya ulivyolipa uweke siku bora.',
          )
        : _bi(
            'Today ${d.today >= 0 ? '+' : ''}${fmt(d.today)} of your best +${fmt(d.best)} pts.',
            'Leo ${d.today >= 0 ? '+' : ''}${fmt(d.today)} kati ya bora yako +${fmt(d.best)} pts.',
          );
    final frac = first || d.best <= 0
        ? null
        : (d.today / d.best).clamp(0.0, 1.0);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: SokoCard(
        padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
        child: Row(
          children: [
            Icon(Icons.flag_outlined, color: tk.ochre),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w800),
                  ),
                  Text(sub, style: tt.bodySmall),
                  if (frac != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: LinearProgressIndicator(value: frac),
                    ),
                ],
              ),
            ),
            IconButton(
              tooltip: _bi('Hide goal', 'Ficha lengo'),
              icon: const Icon(Icons.close, size: 20),
              onPressed: () {
                prefs.setBool('goal_hidden', true);
                setState(() {});
                widget.onDismiss?.call();
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// True while the first-day tutorial tip is still showing.
bool tutorialActive(SharedPreferences p) => !(p.getBool('tut_done') ?? false);

/// The goal card shows until the player hides it, or until it is done: the
/// best day is matched or beaten today.
bool goalActive(SharedPreferences p, int day) {
  if (p.getBool('goal_hidden') ?? false) return false;
  final b = TradeBook(p);
  final d = b.days(day);
  return !(b.hadProfit && d.best > 0 && d.today >= d.best);
}

/// One info card above the prices, highest priority first: the first-day tip,
/// then the goal, then the Radio Soko story. The rest wait their turn.
class _TopCard extends ConsumerStatefulWidget {
  const _TopCard();
  @override
  ConsumerState<_TopCard> createState() => _TopCardState();
}

class _TopCardState extends ConsumerState<_TopCard> {
  void _again() => setState(() {});
  @override
  Widget build(BuildContext context) {
    final prefs = ref.watch(prefsProvider);
    final g = ref.watch(gameProvider).value;
    if (g == null) return const SizedBox.shrink();
    if (tutorialActive(prefs)) return _Tutorial(onDismiss: _again);
    if (goalActive(prefs, g.player.day)) return _GoalCard(onDismiss: _again);
    return const _RadioTips();
  }
}
