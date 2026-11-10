import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/models.dart';
import '../state/providers.dart';
import '../l10n.dart';
import 'theme.dart';
import 'widgets.dart';

class MarketScreen extends ConsumerWidget {
  const MarketScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final g = ref.watch(gameProvider).requireValue;
    return RefreshIndicator(
      onRefresh: () => ref.read(gameProvider.notifier).refresh(),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
        children: [
          const _Tutorial(),
          Text(
            tr('Points are for play only. They can\'t be cashed out.'),
            style: TextStyle(fontSize: 12),
          ),
          SectionTitle(tr('Bei za leo (today\'s prices)')),
          for (final p in g.prices) ...[
            _PriceCard(p),
            const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }
}

class _PriceCard extends ConsumerWidget {
  const _PriceCard(this.p);
  final PriceRow p;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final h = p.history;
    final delta = h.length >= 2 ? h.last - h[h.length - 2] : 0;
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => showModalBottomSheet<void>(
          context: context,
          isScrollControlled: true,
          showDragHandle: true,
          builder: (_) => TradeSheet(p),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              GoodIcon(p.good),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      goodName(p.good),
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                      ),
                    ),
                    Text(
                      tr('{m} · {n} left', {
                        'm': titleCase(p.merchant),
                        'n': p.stock,
                      }),
                      style: TextStyle(
                        color: charcoal.withValues(alpha: .7),
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Num(
                      tr('Sell to them: {p}', {'p': fmt(p.bid)}),
                      style: TextStyle(
                        color: charcoal.withValues(alpha: .7),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              if (h.length >= 2 &&
                  MediaQuery.textScalerOf(context).scale(1) < 1.4)
                Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: Sparkline(h),
                ),
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Num(
                      fmt(p.ask),
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 20,
                      ),
                    ),
                    Text(tr('pts / unit'), style: TextStyle(fontSize: 10)),
                    const SizedBox(height: 2),
                    FittedBox(fit: BoxFit.scaleDown, child: DeltaChip(delta)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class TradeSheet extends ConsumerStatefulWidget {
  const TradeSheet(this.p, {super.key});
  final PriceRow p;
  @override
  ConsumerState<TradeSheet> createState() => _TradeSheetState();
}

class _TradeSheetState extends ConsumerState<TradeSheet> {
  int qty = 1;
  bool busy = false;

  Future<void> _go(Map<String, dynamic> a) async {
    setState(() => busy = true);
    final err = await ref.read(gameProvider.notifier).act(a);
    if (!mounted) return;
    setState(() => busy = false);
    if (err != null) {
      toast(context, err, error: true);
    } else {
      HapticFeedback.lightImpact();
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.p;
    final g = ref.watch(gameProvider).requireValue.player;
    final held = g.stock[p.good] ?? 0;
    final maxBuy = p.stock.clamp(1, 50);
    if (qty > maxBuy) qty = maxBuy;
    // Allow the price to drift up to 3% before the order is refused.
    final maxUnit = p.ask + (p.ask * 3 ~/ 100);
    final cost = p.ask * qty;
    final afford = cost <= g.pts;
    final open = g.phase == Phase.midday;
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
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    tr('{g} at {m}', {
                      'g': goodName(p.good),
                      'm': titleCase(p.merchant),
                    }),
                    style: Theme.of(context).textTheme.titleLarge
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(child: Num(tr('Buy at {p}', {'p': pts(p.ask)}))),
                Expanded(child: Num(tr('Sell at {p}', {'p': pts(p.bid)}))),
                Expanded(child: Num(tr('You hold {n}', {'n': held}))),
              ],
            ),
            const SizedBox(height: 12),
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
                    onChanged: (v) {
                      if (v.round() != qty) HapticFeedback.selectionClick();
                      setState(() => qty = v.round());
                    },
                  ),
                ),
                SizedBox(
                  width: 32,
                  child: Num(
                    '$qty',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
            Num(
              tr(
                'Buying {q} costs {c}. Selling {s} brings about {r} before cess.',
                {
                  'q': qty,
                  'c': pts(cost),
                  's': held < qty ? held : qty,
                  'r': pts(p.bid * (held < qty ? held : qty)),
                },
              ),
            ),
            if (!afford)
              Text(
                tr('Not enough pts for this quantity.'),
                style: TextStyle(color: terracotta),
              ),
            if (!open)
              Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text(
                  tr('The market trades at midday. Come back then.'),
                  style: TextStyle(color: terracotta),
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
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    onPressed: busy || !open
                        ? null
                        : () => _go({
                            'type': 'haggle',
                            'merchant': p.merchant,
                            'good': p.good,
                          }),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(tr('Haggle')),
                    ),
                  ),
                ),
              ],
            ),
            SectionTitle(tr('Why this price')),
            if (p.why.isEmpty) Text(tr('No explanation yet.')),
            for (final w in p.why)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text('• ${whyText(w, ref.watch(langProvider))}'),
              ),
          ],
        ),
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
      padding: const EdgeInsets.only(bottom: 8),
      child: Card(
        color: ochre.withValues(alpha: .25),
        child: Padding(
          padding: const EdgeInsets.all(12),
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
