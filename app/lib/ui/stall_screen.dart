import 'package:flutter/material.dart';

import '../l10n.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

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
    final held = g.player.stock.entries.where((e) => e.value > 0).toList();
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
      children: [
        const KitengeBand(),
        SectionTitle(tr('Duka lako (your stall)')),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(tr('Pointi')),
                      Num(
                        pts(g.player.pts),
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 18,
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(tr('Reputation')),
                      Text(
                        tierName(g.player.tier),
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 18,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
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
              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      GoodIcon(e.key),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${goodName(e.key)} x ${e.value}',
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 16,
                              ),
                            ),
                            if (_perishable.contains(e.key))
                              Row(
                                children: [
                                  const Icon(
                                    Icons.hourglass_bottom,
                                    size: 14,
                                    color: ochre,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    tr('Spoils: about 10% lost each night'),
                                    style: TextStyle(fontSize: 12),
                                  ),
                                ],
                              ),
                            if (best != null)
                              Num(
                                tr('Best bid {p} at {m}', {
                                  'p': pts(best.bid),
                                  'm': titleCase(best.merchant),
                                }),
                                style: const TextStyle(fontSize: 12),
                              ),
                          ],
                        ),
                      ),
                      if (best != null)
                        FilledButton(
                          onPressed: () => showModalBottomSheet<void>(
                            context: context,
                            isScrollControlled: true,
                            showDragHandle: true,
                            builder: (_) => TradeSheet(best),
                          ),
                          child: Text(tr('Sell')),
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
        ],
      ],
    );
  }
}
