import 'package:flutter/material.dart';

import '../l10n.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/models.dart';
import '../state/providers.dart';
import 'login.dart';
import 'theme.dart';
import 'widgets.dart';

class ChamaScreen extends ConsumerWidget {
  const ChamaScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final joined = ref.watch(gameProvider).requireValue.player.chamaId != null;
    return joined ? const _MyChama() : const _ChamaList();
  }
}

/// Discovery: chamas with room, from `GET /v1/chamas`. Each has its own Join button.
class _ChamaList extends ConsumerWidget {
  const _ChamaList();
  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      AsyncBody<List<ChamaSummary>>(
        value: ref.watch(chamaListProvider),
        onRetry: () => ref.invalidate(chamaListProvider),
        builder: (list) => ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
          children: [
            SectionTitle(tr('Chama (buy together)')),
            if (list.isEmpty) EmptyState(tr('No chama here yet.')),
            for (final c in list) ...[
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Chama ${c.id.toUpperCase()}',
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                        ),
                      ),
                      Text(
                        tr('{n} of {max} members', {
                          'n': c.members,
                          'max': c.maxMembers,
                        }),
                        style: const TextStyle(fontSize: 12),
                      ),
                      if (c.openOffer)
                        Text(
                          tr('A lot is open for voting.'),
                          style: const TextStyle(fontSize: 12),
                        ),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: () => _do(context, ref, {
                            'type': 'chama_join',
                            'chama_id': c.id,
                          }),
                          child: Text(
                            tr('Join (share {p})', {'p': pts(c.joinShare)}),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
            ],
            OutlinedButton(
              onPressed: () => _do(context, ref, {'type': 'chama_create'}),
              child: Text(tr('Start my own')),
            ),
          ],
        ),
      );
}

class _MyChama extends ConsumerWidget {
  const _MyChama();
  @override
  Widget build(BuildContext context, WidgetRef ref) => AsyncBody<Chama?>(
    value: ref.watch(chamaProvider),
    onRetry: () => ref.invalidate(chamaProvider),
    builder: (chama) => ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
      children: [
        SectionTitle(tr('Chama (buy together)')),
        if (chama == null) EmptyState(tr('No chama here yet.')),
        if (chama != null) ...[
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    chama.name,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 18,
                    ),
                  ),
                  Num(tr('Common pot {p}', {'p': pts(chama.cash)})),
                  Text(
                    tr(
                      'A chama lends only from its common pot ({c}, {m} members). Fewer than about 4 members usually hold too little to cover a big request, so the vote never opens.',
                      {'c': pts(chama.cash), 'm': chama.members.length},
                    ),
                    style: const TextStyle(fontSize: 12),
                  ),
                  const SizedBox(height: 8),
                  for (final m in chama.members)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Row(
                        children: [
                          Icon(
                            m.you ? Icons.person : Icons.person_outline,
                            size: 18,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              m.you ? tr('{n} (you)', {'n': m.name}) : m.name,
                            ),
                          ),
                          Flexible(
                            child: Num(
                              '${pts(m.shares)} · ${chama.totalShares == 0 ? 0 : m.shares * 100 ~/ chama.totalShares}%',
                              textAlign: TextAlign.end,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          if (chama.offer != null)
            _OfferCard(chama)
          else
            EmptyState(tr('No lot on offer today.')),
        ],
      ],
    ),
  );
}

Future<void> _do(
  BuildContext context,
  WidgetRef ref,
  Map<String, dynamic> a,
) async {
  if ((a['type'] == 'chama_join' || a['type'] == 'chama_create') &&
      !await ensureEmail(context, ref)) {
    return;
  }
  if (!context.mounted) return;
  final err = await ref.read(gameProvider.notifier).act(a);
  if (err != null && context.mounted) toast(context, err, error: true);
}

class _OfferCard extends ConsumerWidget {
  const _OfferCard(this.chama);
  final Chama chama;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final o = chama.offer!;
    final day = ref.watch(gameProvider).requireValue.player.day;
    final me = chama.members.where((m) => m.you).firstOrNull;
    final myShare = me == null || chama.totalShares == 0
        ? 0
        : o.totalPts * me.shares ~/ chama.totalShares;
    final voted = o.myVote != null;
    final mine = o.borrowerIs(
      ref.watch(gameProvider).requireValue.player.playerId,
    );
    final n = chama.members.length;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                GoodIcon(o.good, size: 32),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    tr('Lot on offer: {q} {g}', {
                      'q': o.qty,
                      'g': goodName(o.good),
                    }),
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                    ),
                  ),
                ),
              ],
            ),
            Num(
              tr('Pooled price {t}. Your share of the cost: {s}.', {
                't': pts(o.totalPts),
                's': pts(myShare),
              }),
            ),
            Text(
              tr('Vote closes day {d} ({n} days left).', {
                'd': o.deadlineDay,
                'n': o.deadlineDay - day,
              }),
              style: const TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 12),
            Text(tr('Group vote'), style: TextStyle(fontSize: 12)),
            const SizedBox(height: 4),
            _VoteBar(yes: o.yes, no: o.no, total: n),
            const SizedBox(height: 4),
            Num(
              tr('{y} yes · {no} no · {n} members', {
                'y': o.yes,
                'no': o.no,
                'n': n,
              }),
              style: const TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 12),
            if (mine)
              Text(
                tr('This request is yours. The other members vote on it.'),
                style: const TextStyle(fontWeight: FontWeight.w600),
              )
            else if (voted)
              Text(
                tr('You voted {v}. The result is read when the day closes.', {
                  'v': tr(o.myVote == 'yes' ? 'yes' : 'no'),
                }),
                style: const TextStyle(fontWeight: FontWeight.w600),
              )
            else
              Row(
                children: [
                  Expanded(
                    child: FilledButton(
                      onPressed: () => _do(context, ref, {
                        'type': 'chama_vote',
                        'offer_id': o.id,
                        'vote': 'yes',
                      }),
                      child: Text(tr('Approve')),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => _do(context, ref, {
                        'type': 'chama_vote',
                        'offer_id': o.id,
                        'vote': 'no',
                      }),
                      child: Text(tr('Decline')),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _VoteBar extends StatelessWidget {
  const _VoteBar({required this.yes, required this.no, required this.total});
  final int yes, no, total;
  @override
  Widget build(BuildContext context) {
    final t = total == 0 ? 1 : total;
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: SizedBox(
        height: 12,
        child: Row(
          children: [
            if (yes > 0)
              Expanded(
                flex: yes,
                child: Container(color: leaf),
              ),
            if (no > 0)
              Expanded(
                flex: no,
                child: Container(color: terracotta),
              ),
            if (t - yes - no > 0)
              Expanded(
                flex: t - yes - no,
                child: Container(color: charcoal.withValues(alpha: .1)),
              ),
          ],
        ),
      ),
    );
  }
}
