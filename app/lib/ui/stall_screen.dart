import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n.dart';
import '../state/providers.dart';
import 'market_screen.dart';
import 'theme.dart';
import 'widgets.dart';

const _perishable = {'tomato', 'kale'};

class StallScreen extends ConsumerWidget {
  const StallScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final g = ref.watch(gameProvider).requireValue;
    final tt = Theme.of(context).textTheme;
    final muted = context.tokens.muted;
    final held = g.player.stock.entries.where((e) => e.value > 0).toList();
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
      children: [
        const KitengeBand(radius: 5),
        SectionTitle(tr('Duka lako (your stall)')),
        SummaryStrip([
          SummaryCell(
            label: tr('Pointi'),
            value: pts(g.player.pts),
            semanticLabel: '${tr('Pointi')}: ${pts(g.player.pts)}',
          ),
          SummaryCell(label: tr('Reputation'), value: tierName(g.player.tier)),
        ]),
        const SizedBox(height: 8),
        if (held.isEmpty)
          EmptyState(
            tr('Your shelves are empty. Buy something at Soko to begin.'),
          ),
        for (final e in held) ...[
          const SizedBox(height: 8),
          Builder(
            builder: (context) {
              final rows = g.prices.where((p) => p.good == e.key).toList();
              final best = rows.isEmpty
                  ? null
                  : (rows..sort((a, b) => b.bid.compareTo(a.bid))).first;
              return SokoCard(
                padding: const EdgeInsets.all(12),
                semanticLabel: '${goodName(e.key)}, ${e.value}',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        GoodIcon(e.key),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            goodName(e.key),
                            style: tt.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '× ${e.value}',
                          style: Money.baseStyle(
                            context,
                          ).copyWith(fontSize: 22, fontWeight: FontWeight.w700),
                        ),
                      ],
                    ),
                    if (_perishable.contains(e.key))
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          tr('Spoils: about 10% lost each night'),
                          style: tt.bodySmall?.copyWith(color: muted),
                        ),
                      ),
                    if (best != null) ...[
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Num(
                          tr('Best bid {p} at {m}', {
                            'p': pts(best.bid),
                            'm': titleCase(best.merchant),
                          }),
                          style: tt.bodySmall?.copyWith(color: muted),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerRight,
                        child: FilledButton(
                          style: FilledButton.styleFrom(
                            minimumSize: const Size(48, 48),
                          ),
                          onPressed: () => showModalBottomSheet<void>(
                            context: context,
                            isScrollControlled: true,
                            showDragHandle: true,
                            builder: (_) => TradeSheet(
                              g.prices.where((p) => p.good == e.key).toList(),
                            ),
                          ),
                          child: Text(tr('Sell')),
                        ),
                      ),
                    ],
                  ],
                ),
              );
            },
          ),
        ],
      ],
    );
  }
}
