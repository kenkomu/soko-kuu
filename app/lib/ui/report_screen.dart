import 'package:flutter/material.dart';

import '../l10n.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/models.dart';
import '../state/providers.dart';
import '../state/trade_book.dart';
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

String _bi(String en, String sw) => gLang == 'sw' ? sw : en;

bool _big(BuildContext c) => MediaQuery.textScalerOf(c).scale(14) / 14 > 1.3;

class _LoadError extends StatelessWidget {
  const _LoadError(this.onRetry);
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) => Center(
    child: SingleChildScrollView(
      child: EmptyState(
        _bi(
          'We could not load this. Check your connection and try again.',
          'Hatukuweza kupakia hii. Angalia mtandao wako ujaribu tena.',
        ),
        actionLabel: tr('Try again'),
        onAction: onRetry,
      ),
    ),
  );
}

class _SkeletonList extends StatelessWidget {
  const _SkeletonList();
  @override
  Widget build(BuildContext context) => ListView(
    physics: const NeverScrollableScrollPhysics(),
    padding: const EdgeInsets.all(16),
    children: [
      for (var i = 0; i < 5; i++)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            children: [
              const Skeleton(width: 40, height: 40, radius: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Skeleton(width: 120),
                    const SizedBox(height: 6),
                    Skeleton(width: 80 + i * 20.0, height: 12),
                  ],
                ),
              ),
              const Skeleton(width: 56),
            ],
          ),
        ),
    ],
  );
}

class _LedgerTab extends ConsumerWidget {
  const _LedgerTab();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final player = ref.watch(gameProvider).requireValue.player;
    final today = player.day;
    final sel = ref.watch(ledgerDayProvider) ?? today;
    final tt = Theme.of(context).textTheme;
    return ref
        .watch(ledgerProvider)
        .when(
          loading: () => const _SkeletonList(),
          error: (_, _) => _LoadError(() => ref.invalidate(ledgerProvider)),
          data: (l) {
            // Running balance is only known for today: it ends at the purse.
            final after = <int>[];
            var run = player.pts;
            for (final e in l.entries.reversed) {
              after.add(run);
              run -= e.delta;
            }
            final bal = after.reversed.toList();
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
              children: [
                Row(
                  children: [
                    IconButton(
                      tooltip: tr('Previous day'),
                      onPressed: sel > 1
                          ? () => ref
                                .read(ledgerDayProvider.notifier)
                                .set(sel - 1)
                          : null,
                      icon: const Icon(Icons.chevron_left),
                    ),
                    Expanded(
                      child: Center(
                        child: Text(
                          tr('Day {d}', {'d': sel}),
                          style: tt.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: tr('Next day'),
                      onPressed: sel < today
                          ? () => ref
                                .read(ledgerDayProvider.notifier)
                                .set(sel + 1)
                          : null,
                      icon: const Icon(Icons.chevron_right),
                    ),
                  ],
                ),
                if (l.entries.isEmpty)
                  EmptyState(tr('Nothing recorded for this day yet.'))
                else ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 8, 4, 4),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            tr('Net for the day'),
                            style: tt.titleSmall,
                          ),
                        ),
                        DeltaChip(
                          l.net,
                          suffix: ' pts',
                          upWord: _bi('up', 'juu'),
                          downWord: _bi('down', 'chini'),
                          flatWord: _bi('unchanged', 'haijabadilika'),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  for (var i = 0; i < l.entries.length; i++)
                    _LedgerRow(
                      l.entries[i],
                      balance: sel == today ? bal[i] : null,
                    ),
                ],
              ],
            );
          },
        );
  }
}

class _LedgerRow extends StatelessWidget {
  const _LedgerRow(this.e, {this.balance});
  final LedgerEntry e;
  final int? balance;
  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final tt = Theme.of(context).textTheme;
    final up = e.delta > 0, flat = e.delta == 0;
    final c = flat ? t.muted : (up ? t.up : t.down);
    final sign = flat ? '' : (up ? '+' : '−');
    final letter = e.label.isEmpty
        ? '?'
        : e.label.characters.first.toUpperCase();
    final amount = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          flat
              ? Icons.remove
              : (up ? Icons.arrow_upward : Icons.arrow_downward),
          size: 16,
          color: c,
        ),
        const SizedBox(width: 2),
        Flexible(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(sign, style: Money.baseStyle(context).copyWith(color: c)),
              Flexible(
                child: Money(
                  e.delta.abs(),
                  style: TextStyle(color: c),
                  textAlign: TextAlign.end,
                ),
              ),
            ],
          ),
        ),
      ],
    );
    final balText = balance == null
        ? null
        : Text(
            _bi(
              'Balance ${formatPts(balance!)}',
              'Salio ${formatPts(balance!)}',
            ),
            style: tt.bodySmall?.copyWith(color: t.muted),
            textAlign: TextAlign.end,
          );
    final words = flat
        ? _bi('no change', 'hakuna mabadiliko')
        : '${up ? _bi('gained', 'imeongezeka') : _bi('lost', 'imepungua')} ${formatPts(e.delta.abs())}';
    final text = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          e.label,
          style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w700),
        ),
        if (e.cause.isNotEmpty) Text(e.cause, style: tt.bodySmall),
      ],
    );
    final chip = Container(
      width: 40,
      height: 40,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: t.indigo.withValues(alpha: .14),
        shape: BoxShape.circle,
      ),
      child: Text(
        letter,
        style: TextStyle(
          fontFamily: headingFont,
          fontWeight: FontWeight.w600,
          color: Theme.of(context).colorScheme.onSurface,
        ),
      ),
    );
    return Semantics(
      container: true,
      label:
          '${e.label}. ${e.cause}. $words.${balance == null ? '' : ' ${_bi('Balance', 'Salio')} ${formatPts(balance!)}.'}',
      excludeSemantics: true,
      child: Container(
        constraints: const BoxConstraints(minHeight: 56),
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(color: Theme.of(context).dividerColor),
          ),
        ),
        child: _big(context)
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      chip,
                      const SizedBox(width: 12),
                      Expanded(child: text),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Align(alignment: Alignment.centerRight, child: amount),
                  ?balText,
                ],
              )
            : Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  chip,
                  const SizedBox(width: 12),
                  Expanded(child: text),
                  const SizedBox(width: 8),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [amount, ?balText],
                  ),
                ],
              ),
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
    final t = context.tokens;
    final tt = Theme.of(context).textTheme;
    return rep.when(
      loading: () => const _SkeletonList(),
      error: (_, _) => _LoadError(() => ref.invalidate(reportProvider)),
      data: (r) => ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
        children: [
          SummaryStrip([
            SummaryCell(label: tr('Your score'), value: fmt(r.score)),
            if (r.best > 0)
              SummaryCell(
                label: _bi('Best so far', 'Bora hadi sasa'),
                value: fmt(r.best),
              ),
          ]),
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 6, 4, 0),
            child: Text(
              tr('Pts plus stock value, minus what you owe.'),
              style: tt.bodySmall,
            ),
          ),
          _BestDayCard(day: ref.watch(gameProvider).requireValue.player.day),
          SectionTitle(tr('Basket price index')),
          SokoCard(
            child: r.priceIndex.isEmpty
                ? Text(
                    _bi(
                      'No prices recorded yet.',
                      'Bado hakuna bei zilizorekodiwa.',
                    ),
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        bpPercent(r.priceIndex.last),
                        style: tt.headlineSmall?.copyWith(
                          fontFamily: headingFont,
                          fontFeatures: tabular,
                        ),
                      ),
                      Text(
                        _bi(
                          'Today, against the start (100%).',
                          'Leo, ikilinganishwa na mwanzo (100%).',
                        ),
                        style: tt.bodySmall,
                      ),
                      const SizedBox(height: 8),
                      LayoutBuilder(
                        builder: (c, bc) => Sparkline(
                          r.priceIndex,
                          width: bc.maxWidth,
                          height: 60,
                          semanticLabel: _bi(
                            'Basket price index chart, now ${bpPercent(r.priceIndex.last)}',
                            'Mchoro wa bei za kapu, sasa ${bpPercent(r.priceIndex.last)}',
                          ),
                        ),
                      ),
                    ],
                  ),
          ),
          const _SimCard(),
          SectionTitle(tr('Pts into and out of the market')),
          SokoCard(
            child: Column(
              children: [
                _Bar(
                  tr('Added (allowances)'),
                  r.faucets,
                  r.faucets + r.sinks,
                  t.up,
                  icon: Icons.add_circle_outline,
                ),
                const SizedBox(height: 10),
                _Bar(
                  tr('Removed (cess, fees, spoilage)'),
                  r.sinks,
                  r.faucets + r.sinks,
                  t.down,
                  icon: Icons.remove_circle_outline,
                ),
              ],
            ),
          ),
          SectionTitle(tr('Trader health')),
          if (r.solvency.isEmpty)
            EmptyState(
              _bi(
                'No trader health figures yet.',
                'Bado hakuna takwimu za afya ya wafanyabiashara.',
              ),
            )
          else
            SokoCard(
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final e in r.solvency.entries)
                    StatusChip(
                      '${titleCase(e.key)} ${e.value}%',
                      tone: e.value >= 70
                          ? StatusTone.good
                          : (e.value >= 40 ? StatusTone.warn : StatusTone.bad),
                    ),
                ],
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
    this.icon,
  });
  final IconData? icon;
  final String label;
  static const suffix = ' pts';
  final int value, max;
  final Color color;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          if (icon != null) ...[
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 6),
          ],
          Expanded(child: Text(label, style: const TextStyle(fontSize: 13))),
          Num(
            '${fmt(value)}$suffix',
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
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

/// Optional, gentle: today's trading profit against yesterday and the best day.
/// Shows only once the player has sold something. No timers, no loss framing.
class _BestDayCard extends ConsumerWidget {
  const _BestDayCard({required this.day});
  final int day;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final d = TradeBook(ref.watch(prefsProvider)).days(day);
    if (d.best <= 0 && d.today == 0 && d.prev == null) {
      return const SizedBox.shrink();
    }
    final tt = Theme.of(context).textTheme;
    final t = context.tokens;
    String sg(int n) => '${n > 0 ? '+' : ''}${fmt(n)} pts';
    final beat = d.best > 0 && d.today >= d.best;
    final goal = d.prev != null && d.prev! > 0 ? d.prev! : d.best;
    final line = beat
        ? _bi('Your best day so far. Hongera!', 'Siku yako bora hadi sasa. Hongera!')
        : goal > 0
        ? _bi('${fmt(goal - d.today > 0 ? goal - d.today : 1)} pts more to beat ${d.prev != null && d.prev! > 0 ? 'yesterday' : 'your best day'}.',
            'Pointi ${fmt(goal - d.today > 0 ? goal - d.today : 1)} zaidi kuishinda ${d.prev != null && d.prev! > 0 ? 'jana' : 'siku yako bora'}.')
        : _bi('Sell something above what you paid to put a good day on the board.',
            'Uza kitu juu ya ulichonunulia uanze siku nzuri.');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionTitle(_bi('Beat yesterday', 'Shinda jana')),
        SokoCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(child: _kv(tt, _bi('Today', 'Leo'), sg(d.today), d.today < 0 ? t.ochre : t.up)),
                  if (d.prev != null)
                    Expanded(child: _kv(tt, _bi('Yesterday', 'Jana'), sg(d.prev!), null)),
                  Expanded(child: _kv(tt, _bi('Best day', 'Siku bora'), sg(d.best), null)),
                ],
              ),
              const SizedBox(height: 8),
              Text(line, style: tt.bodyMedium),
            ],
          ),
        ),
      ],
    );
  }

  Widget _kv(TextTheme tt, String k, String v, Color? c) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(k, style: tt.bodySmall),
      Text(v, style: tt.titleMedium?.copyWith(fontFamily: headingFont, fontWeight: FontWeight.w700, color: c, fontFeatures: tabular)),
    ],
  );
}
