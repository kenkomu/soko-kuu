import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:flutter_riverpod/flutter_riverpod.dart';

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

void _openTrade(BuildContext context, PriceRow p, [int qty = 1]) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => TradeSheet(p, initialQty: qty),
    );

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
          const _Tutorial(),
          const _GoalCard(),
          const _RadioTips(),
          Text(
            tr('Points are for play only. They can\'t be cashed out.'),
            style: tt.bodySmall,
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    tr('Bei za leo (today\'s prices)'),
                    style: tt.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Flexible(
                  child: Text(
                    _fresh(),
                    textAlign: TextAlign.end,
                    style: tt.bodySmall?.copyWith(color: context.tokens.muted),
                  ),
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
          for (final p in gs.prices) ...[
            _PriceRowTile(p),
            const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }
}

class _PriceRowTile extends ConsumerStatefulWidget {
  const _PriceRowTile(this.p);
  final PriceRow p;
  @override
  ConsumerState<_PriceRowTile> createState() => _PriceRowTileState();
}

class _PriceRowTileState extends ConsumerState<_PriceRowTile> {
  int qty = 1;

  @override
  Widget build(BuildContext context) {
    final p = widget.p;
    final lang = ref.watch(langProvider);
    final tt = Theme.of(context).textTheme;
    final muted = context.tokens.muted;
    final h = p.history;
    final delta = h.length >= 2 ? h.last - h[h.length - 2] : 0;
    final maxQ = p.stock.clamp(1, 50);
    final q = qty.clamp(1, maxQ);
    final name = goodName(p.good);
    return SokoCard(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PressSquish(
            onTap: () => _openTrade(context, p, q),
            semanticLabel: _bi(
              '{g} from {m}, {p} pts each. Open to buy or sell.',
              '{g} kutoka {m}, pointi {p} kila kimoja. Fungua kununua au kuuza.',
              {'g': name, 'm': titleCase(p.merchant), 'p': fmt(p.ask)},
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                MerchantChip(p.merchant),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          GoodIcon(p.good, size: 28),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              name,
                              style: tt.titleMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                      Text(
                        tr('{m} · {n} left', {
                          'm': titleCase(p.merchant),
                          'n': p.stock,
                        }),
                        style: tt.bodySmall?.copyWith(color: muted),
                      ),
                      Text(
                        tr('pts / unit'),
                        style: tt.bodySmall?.copyWith(color: muted),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerRight,
                        child: RollingNumber(
                          p.ask,
                          style: Money.baseStyle(
                            context,
                          ).copyWith(fontSize: 22, fontWeight: FontWeight.w700),
                        ),
                      ),
                      Text(
                        tr('Sell to them: {p}', {'p': fmt(p.bid)}),
                        textAlign: TextAlign.end,
                        style: tt.bodySmall?.copyWith(color: muted),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (h.length >= 2)
                      Sparkline(
                        h,
                        width: 56,
                        semanticLabel: _bi(
                          'Price history, {n} days',
                          'Historia ya bei, siku {n}',
                          {'n': h.length},
                        ),
                      ),
                    DeltaChip(
                      delta,
                      upWord: _bi('up', 'juu'),
                      downWord: _bi('down', 'chini'),
                      flatWord: _bi('unchanged', 'haijabadilika'),
                    ),
                  ],
                ),
              ),
              _Stepper(
                qty: q,
                max: maxQ,
                name: name,
                onChanged: (v) => setState(() => qty = v),
              ),
            ],
          ),
          if (p.why.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                whyText(p.why.first, lang),
                style: tt.bodySmall?.copyWith(color: muted),
              ),
            ),
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

class TradeSheet extends ConsumerStatefulWidget {
  const TradeSheet(this.p, {super.key, this.initialQty = 1});
  final PriceRow p;
  final int initialQty;
  @override
  ConsumerState<TradeSheet> createState() => _TradeSheetState();
}

class _TradeSheetState extends ConsumerState<TradeSheet> {
  late int qty = widget.initialQty < 1 ? 1 : widget.initialQty;
  bool busy = false;
  bool showWhy = false;
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
    final p = widget.p;
    final tt = Theme.of(context).textTheme;
    final tk = context.tokens;
    final lang = ref.watch(langProvider);
    final g = ref.watch(gameProvider).requireValue.player;
    final held = g.stock[p.good] ?? 0;
    final maxBuy = p.stock.clamp(1, 50);
    if (qty > maxBuy) qty = maxBuy;
    // Allow the price to drift up to 3% before the order is refused.
    final maxUnit = p.ask + (p.ask * 3 ~/ 100);
    final cost = p.ask * qty;
    final worst = maxUnit * qty;
    final afford = cost <= g.pts;
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
                MerchantChip(p.merchant),
                const SizedBox(width: 8),
                GoodIcon(p.good, size: 36),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    tr('{g} at {m}', {'g': name, 'm': titleCase(p.merchant)}),
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
                Num(tr('Buy at {p}', {'p': pts(p.ask)})),
                Num(tr('Sell at {p}', {'p': pts(p.bid)})),
                Num(tr('You hold {n}', {'n': held})),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Flexible(flex: 2, child: Text(tr('Quantity'))),
                Expanded(
                  flex: 3,
                  child: Slider(
                    min: 1,
                    max: maxBuy.toDouble(),
                    divisions: maxBuy > 1 ? maxBuy - 1 : null,
                    value: qty.toDouble(),
                    label: '$qty',
                    semanticFormatterCallback: (v) => '${v.round()}',
                    onChanged: (v) {
                      if (v.round() != qty) Feel.select();
                      setState(() => qty = v.round());
                    },
                  ),
                ),
                SizedBox(
                  width: 36,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Num(
                      '$qty',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
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
                    Num(pts(p.bid * sellQty), textAlign: TextAlign.end),
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
                            'merchant': p.merchant,
                            'good': p.good,
                            'qty': qty,
                            'min_unit_price': p.bid - p.bid * 3 ~/ 100,
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
  const _Tutorial();
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
                onPressed: () =>
                    setState(() => prefs.setBool('tut_done', true)),
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
  const _GoalCard();
  @override
  ConsumerState<_GoalCard> createState() => _GoalCardState();
}

class _GoalCardState extends ConsumerState<_GoalCard> {
  @override
  Widget build(BuildContext context) {
    final prefs = ref.watch(prefsProvider);
    final g = ref.watch(gameProvider).value;
    if (g == null || (prefs.getBool('goal_hidden') ?? false)) {
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
              },
            ),
          ],
        ),
      ),
    );
  }
}
