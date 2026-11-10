import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../l10n.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/models.dart';
import '../state/providers.dart';
import 'theme.dart';
import 'widgets.dart';

/// Plain reason for a credit refusal that is about the chama pot, or null when the request was within
/// the player's own limit (then the runner's own message stands). [chamaCash] is null without a chama.
String? creditShortfallHint({
  required int cost,
  required int owed,
  required int? available,
  required int? chamaCash,
}) {
  final limit = available ?? 0;
  if (owed <= limit) return null;
  if (chamaCash == null) {
    return tr(
      'That is more than your own credit limit ({l}). A chama can lend the rest, but you are not in one. Join one in the Chama tab.',
      {'l': pts(limit)},
    );
  }
  if (chamaCash >= cost) return null;
  return tr(
    "That is more than your own credit limit ({l}). Your chama's common pot holds {c}, not enough to cover {n}. Ask for less, or invite members: a chama of about 4 members holds enough.",
    {'l': pts(limit), 'c': pts(chamaCash), 'n': pts(cost)},
  );
}

class CreditScreen extends ConsumerWidget {
  const CreditScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final g = ref.watch(gameProvider).requireValue;
    final p = g.player;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
      children: [
        SectionTitle(tr('Deni (credit)')),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Num(
                  tr('Credit limit {l} · owed {o}', {
                    'l': pts(p.creditLimit),
                    'o': pts(p.openDebt),
                  }),
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                LinearProgressIndicator(
                  value: p.creditLimit == 0
                      ? 0
                      : (p.openDebt / p.creditLimit).clamp(0, 1).toDouble(),
                  minHeight: 8,
                  borderRadius: BorderRadius.circular(8),
                  color: ochre,
                  backgroundColor: charcoal.withValues(alpha: .1),
                ),
                const SizedBox(height: 8),
                Text(
                  tr('Reputation: {t}. Repay on time to raise your limit.', {
                    't': tierName(p.tier),
                  }),
                  style: const TextStyle(fontSize: 12),
                ),
                const SizedBox(height: 8),
                FilledButton.icon(
                  icon: const Icon(Icons.add),
                  label: Text(tr('Take goods on credit')),
                  onPressed: () => showModalBottomSheet<void>(
                    context: context,
                    isScrollControlled: true,
                    showDragHandle: true,
                    builder: (_) => const _CreditSheet(),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (p.loans.isEmpty) EmptyState(tr('No open deni. Good standing.')),
        for (final l in p.loans) ...[
          const SizedBox(height: 8),
          _LoanCard(l, p.day),
        ],
      ],
    );
  }
}

class _LoanCard extends ConsumerWidget {
  const _LoanCard(this.l, this.day);
  final Loan l;
  final int day;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final left = l.dueDay - day;
    final late = left <= 0;
    final frac = (left / (l.daysTotal == 0 ? 5 : l.daysTotal)).clamp(0.0, 1.0);
    final c = late ? ochre : leaf;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            SizedBox(
              width: 56,
              height: 56,
              child: CustomPaint(
                painter: _Ring(frac, c),
                child: Center(
                  child: Icon(
                    late ? Icons.warning_amber_rounded : Icons.schedule,
                    color: c,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    tr('{q} {g} from {m}', {
                      'q': l.qty,
                      'g': goodName(l.good),
                      'm': titleCase(l.merchant),
                    }),
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  Num(
                    tr('Owe {p}', {'p': pts(l.owed)}),
                    style: const TextStyle(fontSize: 13),
                  ),
                  Text(
                    tr(
                      l.lender == 'chama'
                          ? '{r}% interest, from your chama'
                          : '{r}% interest, from the trader',
                      {'r': l.interestPct},
                    ),
                    style: const TextStyle(fontSize: 12),
                  ),
                  Text(
                    late
                        ? tr('Overdue: late fees are adding up')
                        : tr('Due in {n} day(s) (day {d})', {
                            'n': left,
                            'd': l.dueDay,
                          }),
                    style: TextStyle(
                      fontSize: 12,
                      color: late ? const Color(0xFF8A5A00) : charcoal,
                    ),
                  ),
                ],
              ),
            ),
            FilledButton(
              onPressed: () async {
                final err = await ref.read(gameProvider.notifier).act({
                  'type': 'credit_repay',
                  'loan_id': l.id,
                });
                if (err != null && context.mounted) {
                  toast(context, err, error: true);
                }
              },
              child: Text(tr('Repay')),
            ),
          ],
        ),
      ),
    );
  }
}

class _Ring extends CustomPainter {
  _Ring(this.frac, this.c);
  final double frac;
  final Color c;
  @override
  void paint(Canvas canvas, Size s) {
    final r = Rect.fromLTWH(4, 4, s.width - 8, s.height - 8);
    canvas.drawArc(
      r,
      0,
      math.pi * 2,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5
        ..color = charcoal.withValues(alpha: .1),
    );
    canvas.drawArc(
      r,
      -math.pi / 2,
      math.pi * 2 * frac,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5
        ..strokeCap = StrokeCap.round
        ..color = c,
    );
  }

  @override
  bool shouldRepaint(_Ring o) => o.frac != frac || o.c != c;
}

class _CreditSheet extends ConsumerStatefulWidget {
  const _CreditSheet();
  @override
  ConsumerState<_CreditSheet> createState() => _CreditSheetState();
}

class _CreditSheetState extends ConsumerState<_CreditSheet> {
  PriceRow? sel;
  int qty = 2;
  @override
  Widget build(BuildContext context) {
    final g = ref.watch(gameProvider).requireValue;
    sel ??= g.prices.first;
    final s = sel!;
    final cost = s.ask * qty;
    final owed = cost + cost * 6 ~/ 100;
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
            Text(
              tr('Goods on credit'),
              style: Theme.of(context).textTheme.titleLarge
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<PriceRow>(
              isExpanded: true,
              initialValue: s,
              items: [
                for (final p in g.prices)
                  DropdownMenuItem(
                    value: p,
                    child: Text(
                      '${goodName(p.good)} · ${titleCase(p.merchant)} (${fmt(p.ask)})',
                      overflow: TextOverflow.ellipsis,
                      maxLines: 2,
                    ),
                  ),
              ],
              onChanged: (v) => setState(() => sel = v),
            ),
            Row(
              children: [
                Text(tr('Quantity')),
                Expanded(
                  child: Slider(
                    min: 1,
                    max: 20,
                    divisions: 19,
                    value: qty.toDouble(),
                    label: '$qty',
                    onChanged: (v) => setState(() => qty = v.round()),
                  ),
                ),
                Num('$qty'),
              ],
            ),
            Num(
              tr(
                'Value {c}. You will owe about {o} (6% interest) within 5 days. Late debts grow.',
                {'c': pts(cost), 'o': pts(owed)},
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () async {
                  final err = await ref.read(gameProvider.notifier).act({
                    'type': 'credit_request',
                    'merchant': s.merchant,
                    'good': s.good,
                    'qty': qty,
                  });
                  if (!context.mounted) return;
                  if (err != null) {
                    final hint = creditShortfallHint(
                      cost: cost,
                      owed: owed,
                      available: ref
                          .read(gameProvider)
                          .value
                          ?.player
                          .creditAvailable,
                      chamaCash: ref.read(chamaProvider).value?.cash,
                    );
                    if (hint == null) {
                      toast(context, err, error: true);
                    } else {
                      await showDialog<void>(
                        context: context,
                        builder: (c) => AlertDialog(
                          content: SingleChildScrollView(child: Text(hint)),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(c),
                              child: Text(tr('OK')),
                            ),
                          ],
                        ),
                      );
                    }
                  } else {
                    Navigator.pop(context);
                  }
                },
                child: Text(tr('Ask for credit')),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
