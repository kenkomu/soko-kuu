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

String _bi(String en, String swa, [Map<String, Object>? p]) {
  var s = gLang == 'sw' ? swa : en;
  p?.forEach((k, v) => s = s.replaceAll('{$k}', '$v'));
  return s;
}

const _tierIds = ['mgeni', 'mfanyabiashara', 'mzoefu', 'mzee_wa_soko'];

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
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            icon: const Icon(Icons.add),
            label: Text(tr('Take goods on credit')),
            onPressed: () => showModalBottomSheet<void>(
              context: context,
              isScrollControlled: true,
              showDragHandle: true,
              builder: (_) => const _CreditSheet(),
            ),
          ),
        ),
        const SizedBox(height: 12),
        if (p.loans.isEmpty)
          EmptyState(tr('No open deni. Good standing.'))
        else
          for (final l in p.loans) ...[
            _LoanCard(l, p.day),
            const SizedBox(height: 12),
          ],
        _TierCard(p),
      ],
    );
  }
}

class _TierCard extends StatelessWidget {
  const _TierCard(this.p);
  final PlayerState p;
  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final t = context.tokens;
    final cur = _tierIds.indexOf(p.tier.toLowerCase());
    final starter = cur <= 0 && p.loans.isEmpty;
    final frac = p.creditLimit == 0
        ? 0.0
        : (p.openDebt / p.creditLimit).clamp(0.0, 1.0);
    return SokoCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _bi('Your standing: {t}', 'Hadhi yako: {t}', {
              't': tierName(p.tier),
            }),
            style: tt.titleMedium,
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (var i = 0; i < _tierIds.length; i++)
                StatusChip(
                  tierName(_tierIds[i]),
                  tone: i == cur ? StatusTone.good : StatusTone.neutral,
                  icon: i == cur
                      ? Icons.check_circle
                      : (i < cur ? Icons.check : Icons.lock_outline),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Num(
            _bi(
              'Credit limit {l} · owed {o}',
              'Kikomo cha deni {l} · unadaiwa {o}',
              {'l': pts(p.creditLimit), 'o': pts(p.openDebt)},
            ),
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          TweenAnimationBuilder<double>(
            tween: Tween(end: frac),
            duration: reduceMotion(context)
                ? Duration.zero
                : const Duration(milliseconds: 500),
            builder: (_, v, _) => ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: v,
                minHeight: 10,
                color: t.teal,
                backgroundColor: t.muted.withValues(alpha: .2),
                semanticsLabel: _bi('Credit used', 'Deni lililotumika'),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            tr('Reputation: {t}. Repay on time to raise your limit.', {
              't': tierName(p.tier),
            }),
            style: tt.bodySmall,
          ),
          if (starter) ...[
            const Divider(height: 24),
            Text(
              _bi('Starter credit', 'Deni la kuanzia'),
              style: tt.titleSmall,
            ),
            const SizedBox(height: 4),
            Text(
              _bi(
                'New players start with a small credit limit. Take goods now, pay back within 5 days, and your limit grows with each tier. Take your time.',
                'Wachezaji wapya huanza na kikomo kidogo cha deni. Chukua bidhaa, lipa ndani ya siku 5, na kikomo chako hukua kwa kila ngazi. Hakuna haraka.',
              ),
              style: tt.bodySmall,
            ),
          ],
        ],
      ),
    );
  }
}

class _LoanCard extends ConsumerWidget {
  const _LoanCard(this.l, this.day);
  final Loan l;
  final int day;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tt = Theme.of(context).textTheme;
    final t = context.tokens;
    final left = l.dueDay - day;
    final late = left <= 0;
    final total = l.daysTotal == 0 ? 5 : l.daysTotal;
    final frac = ((total - left) / total).clamp(0.0, 1.0);
    return SokoCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
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
                      style: tt.titleSmall,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      tr(
                        l.lender == 'chama'
                            ? '{r}% interest, from your chama'
                            : '{r}% interest, from the trader',
                        {'r': l.interestPct},
                      ),
                      style: tt.bodySmall,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    'Deni',
                    style: tt.labelMedium?.copyWith(
                      color: t.down,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Money(
                    l.owed,
                    textAlign: TextAlign.end,
                    style: tt.titleLarge?.copyWith(color: t.down),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 8),
          StatusChip(
            late
                ? tr('Overdue: late fees are adding up')
                : tr('Due in {n} day(s) (day {d})', {'n': left, 'd': l.dueDay}),
            tone: late ? StatusTone.warn : StatusTone.info,
            icon: late ? Icons.warning_amber_rounded : Icons.schedule,
          ),
          const SizedBox(height: 10),
          TweenAnimationBuilder<double>(
            tween: Tween(end: frac),
            duration: reduceMotion(context)
                ? Duration.zero
                : const Duration(milliseconds: 500),
            builder: (_, v, _) => ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: v,
                minHeight: 8,
                color: t.teal,
                backgroundColor: t.muted.withValues(alpha: .2),
                semanticsLabel: _bi('Time passed', 'Muda uliopita'),
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            _bi(
              'Day {a} of {b} for this deni',
              'Siku {a} kati ya {b} za deni hili',
              {'a': (total - left).clamp(0, total), 'b': total},
            ),
            style: tt.bodySmall,
          ),
          if (l.guarantor != null) ...[
            const SizedBox(height: 4),
            Text(
              _bi('Guarantor: {g}', 'Mdhamini: {g}', {'g': l.guarantor!}),
              style: tt.bodySmall,
            ),
          ],
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
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
          ),
        ],
      ),
    );
  }
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
