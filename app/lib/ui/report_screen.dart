import 'package:flutter/material.dart';

import '../l10n.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/models.dart';
import '../state/providers.dart';
import 'theme.dart';
import 'widgets.dart';

class ReportScreen extends StatelessWidget {
  const ReportScreen({super.key});
  @override
  Widget build(BuildContext context) => DefaultTabController(
    length: 2,
    child: Column(
      children: [
        TabBar(
          tabs: [
            Tab(text: tr('Day ledger')),
            Tab(text: tr('Soko Report')),
          ],
        ),
        Expanded(child: TabBarView(children: [_LedgerTab(), _ReportTab()])),
      ],
    ),
  );
}

class _LedgerTab extends ConsumerWidget {
  const _LedgerTab();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final today = ref.watch(gameProvider).requireValue.player.day;
    final sel = ref.watch(ledgerDayProvider) ?? today;
    return AsyncBody<DayLedger>(
      value: ref.watch(ledgerProvider),
      onRetry: () => ref.invalidate(ledgerProvider),
      builder: (l) => ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
        children: [
          Row(
            children: [
              IconButton(
                tooltip: tr('Previous day'),
                onPressed: sel > 1
                    ? () => ref.read(ledgerDayProvider.notifier).set(sel - 1)
                    : null,
                icon: const Icon(Icons.chevron_left),
              ),
              Expanded(
                child: Center(
                  child: Text(
                    tr('Day {d}', {'d': sel}),
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                    ),
                  ),
                ),
              ),
              IconButton(
                tooltip: tr('Next day'),
                onPressed: sel < today
                    ? () => ref.read(ledgerDayProvider.notifier).set(sel + 1)
                    : null,
                icon: const Icon(Icons.chevron_right),
              ),
            ],
          ),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Expanded(child: Text(tr('Net for the day'))),
                  DeltaChip(l.net, suffix: ' pts'),
                ],
              ),
            ),
          ),
          if (l.entries.isEmpty)
            EmptyState(tr('Nothing recorded for this day yet.')),
          for (final e in l.entries) ...[
            const SizedBox(height: 8),
            Card(
              child: ListTile(
                title: Text(e.label),
                subtitle: Text(e.cause),
                trailing: e.delta == 0 ? const Text('-') : DeltaChip(e.delta),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ReportTab extends ConsumerWidget {
  const _ReportTab();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rep = ref.watch(reportProvider);
    final board = ref.watch(boardProvider);
    return AsyncBody<SokoReport>(
      value: rep,
      onRetry: () => ref.invalidate(reportProvider),
      builder: (r) => ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(tr('Your score')),
                  Num(
                    fmt(r.score),
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 28,
                    ),
                  ),
                  Text(
                    tr('Pts plus stock value, minus what you owe.'),
                    style: TextStyle(fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
          SectionTitle(tr('Basket price index')),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Expanded(
                    child: Sparkline(r.priceIndex, width: 240, height: 60),
                  ),
                  Num(
                    bpPercent(r.priceIndex.isEmpty ? 10000 : r.priceIndex.last),
                  ),
                ],
              ),
            ),
          ),
          const _SimCard(),
          SectionTitle(tr('Pts into and out of the market')),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  _Bar(
                    tr('Added (allowances)'),
                    r.faucets,
                    r.faucets + r.sinks,
                    leaf,
                  ),
                  const SizedBox(height: 8),
                  _Bar(
                    tr('Removed (cess, fees, spoilage)'),
                    r.sinks,
                    r.faucets + r.sinks,
                    terracotta,
                  ),
                ],
              ),
            ),
          ),
          SectionTitle(tr('Trader health')),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  for (final e in r.solvency.entries)
                    _Bar(titleCase(e.key), e.value, 100, ochre, suffix: '%'),
                ],
              ),
            ),
          ),
          SectionTitle(tr('Rankings')),
          board.when(
            data: (b) => Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Num(
                      tr('Your personal best: {n}', {'n': fmt(b.personalBest)}),
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const Divider(),
                    for (var i = 0; i < b.chamas.length; i++)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 3),
                        child: Row(
                          children: [
                            SizedBox(width: 24, child: Num('${i + 1}')),
                            Expanded(
                              child: Text(
                                b.chamas[i].name +
                                    (b.chamas[i].you
                                        ? ' ${tr('(yours)')}'
                                        : ''),
                                style: TextStyle(
                                  fontWeight: b.chamas[i].you
                                      ? FontWeight.w800
                                      : FontWeight.w400,
                                ),
                              ),
                            ),
                            Num(fmt(b.chamas[i].score)),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
            loading: () => const SizedBox.shrink(),
            error: (_, _) => Text(tr('Rankings unavailable.')),
          ),
        ],
      ),
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar(
    this.label,
    this.value,
    this.max,
    this.color, {
    this.suffix = ' pts',
  });
  final String label, suffix;
  final int value, max;
  final Color color;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          Expanded(child: Text(label, style: const TextStyle(fontSize: 12))),
          Num(
            '${fmt(value)}$suffix',
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ],
      ),
      const SizedBox(height: 2),
      LinearProgressIndicator(
        value: max == 0 ? 0 : (value / max).clamp(0, 1).toDouble(),
        minHeight: 8,
        color: color,
        backgroundColor: charcoal.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(6),
      ),
    ],
  );
}

/// "What if?" fast-forward from /v1/sim: preview only, nothing changes in the game.
class _SimCard extends ConsumerStatefulWidget {
  const _SimCard();
  @override
  ConsumerState<_SimCard> createState() => _SimCardState();
}

class _SimCardState extends ConsumerState<_SimCard> {
  int days = 30;
  String? kind;
  (int, String?)? run;
  @override
  Widget build(BuildContext context) {
    final frames = run == null ? null : ref.watch(simProvider(run!));
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              tr('What if? Fast-forward'),
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            Text(
              tr('A preview of the market. It does not change your game.'),
              style: const TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final d in const [7, 30, 60])
                  ChoiceChip(
                    label: Text(tr('{n} days', {'n': d})),
                    selected: days == d,
                    onSelected: (_) => setState(() => days = d),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final k in const [null, 'ukame', 'glut'])
                  ChoiceChip(
                    label: Text(
                      k == null
                          ? tr('No shock')
                          : (k == 'ukame' ? tr('Drought') : tr('Glut')),
                    ),
                    selected: kind == k,
                    onSelected: (_) => setState(() => kind = k),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: () => setState(() => run = (days, kind)),
              child: Text(tr('Run preview')),
            ),
            if (frames != null)
              frames.when(
                loading: () => const Padding(
                  padding: EdgeInsets.all(8),
                  child: LinearProgressIndicator(),
                ),
                error: (_, _) => Text(tr('Could not run the preview.')),
                data: (f) => f.isEmpty
                    ? const SizedBox.shrink()
                    : Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Row(
                          children: [
                            Expanded(
                              child: Sparkline(
                                [for (final x in f) x.priceIndexBp],
                                width: 240,
                                height: 60,
                              ),
                            ),
                            Num(bpPercent(f.last.priceIndexBp)),
                          ],
                        ),
                      ),
              ),
          ],
        ),
      ),
    );
  }
}
