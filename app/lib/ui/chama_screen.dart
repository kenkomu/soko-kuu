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

/// Inline English/Swahili pair (keeps l10n files untouched). {x} placeholders as in tr().
String _bi(String en, String swa, [Map<String, Object>? p]) {
  var s = gLang == 'sw' ? swa : en;
  p?.forEach((k, v) => s = s.replaceAll('{$k}', '$v'));
  return s;
}

String _short(String id) => id.length > 6 ? id.substring(0, 6) : id;

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
          _PotCard(chama),
          const SizedBox(height: 12),
          if (chama.offer != null)
            _OfferCard(chama)
          else
            EmptyState(tr('No lot on offer today.')),
        ],
      ],
    ),
  );
}

class _PotCard extends StatelessWidget {
  const _PotCard(this.chama);
  final Chama chama;
  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final t = context.tokens;
    final total = chama.members.length;
    final paid = chama.members.where((m) => m.shares > 0).length;
    final waiting = total - paid;
    final me = chama.members.where((m) => m.you).firstOrNull;
    final need = chama.offer?.totalPts;
    final settled = waiting == 0 && total > 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(chama.name, style: tt.titleLarge),
        const SizedBox(height: 8),
        SummaryStrip([
          SummaryCell(label: _bi('Common pot', 'Mfuko wa pamoja'), value: formatPts(chama.cash)),
          SummaryCell(label: _bi('Your share', 'Sehemu yako'), value: formatPts(me?.shares ?? 0)),
          SummaryCell(label: _bi('Paid in', 'Wamechangia'), value: '$paid / $total'),
          SummaryCell(label: _bi('Waiting', 'Wanasubiriwa'), value: '$waiting'),
        ]),
        const SizedBox(height: 12),
        SokoCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                need == null
                    ? _bi('Pot {c} pts', 'Mfuko {c} pts', {'c': fmt(chama.cash)})
                    : _bi('Pot {c} of {n} pts', 'Mfuko {c} kati ya {n} pts', {'c': fmt(chama.cash), 'n': fmt(need)}),
                style: tt.titleMedium,
              ),
              if (need != null) ...[
                const SizedBox(height: 8),
                TweenAnimationBuilder<double>(
                  tween: Tween(end: need == 0 ? 1.0 : (chama.cash / need).clamp(0.0, 1.0)),
                  duration: reduceMotion(context) ? Duration.zero : const Duration(milliseconds: 500),
                  builder: (_, v, _) => ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(
                      value: v,
                      minHeight: 10,
                      color: t.teal,
                      backgroundColor: t.muted.withValues(alpha: .2),
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  chama.cash >= need
                      ? _bi('The pot covers the lot on offer.', 'Mfuko unatosha kwa bidhaa iliyotolewa.')
                      : _bi('The pot is smaller than the lot on offer.', 'Mfuko ni mdogo kuliko bidhaa iliyotolewa.'),
                  style: tt.bodySmall,
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 12),
        Text(_bi('Who has paid in', 'Nani amechangia'), style: tt.titleMedium),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [for (final m in chama.members) _PaidCell(m)],
        ),
        const SizedBox(height: 8),
        if (settled)
          StatusChip(
            _bi('All settled up', 'Wote wamekamilisha'),
            tone: StatusTone.good,
            icon: Icons.check_circle,
          )
        else
          Text(
            _bi('{n} member(s) have not paid in yet.', 'Wanachama {n} bado hawajachangia.', {'n': waiting}),
            style: tt.bodySmall,
          ),
        const SizedBox(height: 8),
        Text(
          tr(
            'A chama lends only from its common pot ({c}, {m} members). Fewer than about 4 members usually hold too little to cover a big request, so the vote never opens.',
            {'c': pts(chama.cash), 'm': chama.members.length},
          ),
          style: tt.bodySmall,
        ),
      ],
    );
  }
}

class _PaidCell extends StatelessWidget {
  const _PaidCell(this.m);
  final ChamaMember m;
  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final tt = Theme.of(context).textTheme;
    final paid = m.shares > 0;
    final name = m.you ? _bi('You', 'Wewe') : _short(m.name);
    final state = paid ? _bi('paid {p}', 'amechangia {p}', {'p': pts(m.shares)}) : _bi('not paid yet', 'bado hajachangia');
    return Semantics(
      label: '$name: $state',
      excludeSemantics: true,
      child: Container(
        constraints: const BoxConstraints(minWidth: 96, minHeight: 56),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: t.card,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: paid ? t.up : t.muted, width: m.you ? 2 : 1),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              paid ? Icons.check_circle : Icons.hourglass_empty,
              size: 20,
              color: paid ? t.up : t.muted,
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(name, style: tt.labelLarge, overflow: TextOverflow.ellipsis),
                  Text(
                    paid ? pts(m.shares) : _bi('Pending', 'Inasubiri'),
                    style: tt.bodySmall,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
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

  Future<void> _confirm(BuildContext context, WidgetRef ref, ChamaOffer o) async {
    final vote = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _VoteSheet(o),
    );
    if (vote == null || !context.mounted) return;
    await _do(context, ref, {
      'type': 'chama_vote',
      'offer_id': o.id,
      'vote': vote,
    });
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final o = chama.offer!;
    final tt = Theme.of(context).textTheme;
    final player = ref.watch(gameProvider).requireValue.player;
    final day = player.day;
    final me = chama.members.where((m) => m.you).firstOrNull;
    final myShare = me == null || chama.totalShares == 0
        ? 0
        : o.totalPts * me.shares ~/ chama.totalShares;
    final voted = o.myVote != null;
    final mine = o.borrowerIs(player.playerId);
    final borrowerIn = chama.members.any((m) => m.name == o.borrower);
    final voters = (chama.members.length - (borrowerIn || mine ? 1 : 0)).clamp(0, 99);
    final needYes = voters ~/ 2 + 1;
    final waiting = (voters - o.yes - o.no).clamp(0, 99);
    return SokoCard(
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
                  style: tt.titleMedium,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
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
            style: tt.bodySmall,
          ),
          const SizedBox(height: 12),
          Text(tr('Group vote'), style: tt.titleSmall),
          const SizedBox(height: 4),
          Text(
            _bi(
              'The borrower does not vote. A majority of the other members decides: {k} yes of {v} is enough.',
              'Mkopaji hapigi kura. Wengi wa wanachama wengine huamua: kura {k} za ndiyo kati ya {v} zinatosha.',
              {'k': needYes, 'v': voters},
            ),
            style: tt.bodySmall,
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (var i = 0; i < o.yes; i++) _VoteAvatar('yes', mineVote: false),
              for (var i = 0; i < o.no; i++) _VoteAvatar('no', mineVote: false),
              for (var i = 0; i < waiting; i++) _VoteAvatar('waiting', mineVote: false),
            ],
          ),
          const SizedBox(height: 12),
          _ResultBar(
            label: tr('yes'),
            icon: Icons.check,
            count: o.yes,
            of: voters,
            color: context.tokens.up,
          ),
          const SizedBox(height: 6),
          _ResultBar(
            label: tr('no'),
            icon: Icons.close,
            count: o.no,
            of: voters,
            color: context.tokens.down,
          ),
          const SizedBox(height: 4),
          Num(
            tr('{y} yes · {no} no · {n} members', {
              'y': o.yes,
              'no': o.no,
              'n': chama.members.length,
            }),
            style: tt.bodySmall,
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
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => _confirm(context, ref, o),
                child: Text(_bi('Cast my vote', 'Piga kura yangu')),
              ),
            ),
        ],
      ),
    );
  }
}

class _VoteSheet extends StatefulWidget {
  const _VoteSheet(this.o);
  final ChamaOffer o;
  @override
  State<_VoteSheet> createState() => _VoteSheetState();
}

class _VoteSheetState extends State<_VoteSheet> {
  String? choice;
  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final o = widget.o;
    Widget opt(String v, String label, IconData icon) => Expanded(
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 56),
        child: choice == v
            ? FilledButton.icon(
                onPressed: () => setState(() => choice = v),
                icon: Icon(icon),
                label: Text(label),
              )
            : OutlinedButton.icon(
                onPressed: () => setState(() => choice = v),
                icon: Icon(icon),
                label: Text(label),
              ),
      ),
    );
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_bi('Your vote', 'Kura yako'), style: tt.titleLarge),
            const SizedBox(height: 4),
            Row(
              children: [
                GoodIcon(o.good, size: 28),
                const SizedBox(width: 8),
                Expanded(
                  child: Num(
                    tr('Lot on offer: {q} {g}', {
                      'q': o.qty,
                      'g': goodName(o.good),
                    }),
                  ),
                ),
              ],
            ),
            Num(_bi('Pooled price {t}', 'Bei ya pamoja {t}', {'t': pts(o.totalPts)})),
            const SizedBox(height: 12),
            Row(
              children: [
                opt('yes', tr('Approve'), Icons.check),
                const SizedBox(width: 8),
                opt('no', tr('Decline'), Icons.close),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              _bi('You can vote once. It cannot be changed.', 'Unaweza kupiga kura mara moja. Haiwezi kubadilishwa.'),
              style: tt.bodySmall,
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: choice == null ? null : () => Navigator.pop(context, choice),
                child: Text(_bi('Confirm vote', 'Thibitisha kura')),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _VoteAvatar extends StatelessWidget {
  const _VoteAvatar(this.state, {required this.mineVote});
  final String state;
  final bool mineVote;
  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final (icon, label, c) = switch (state) {
      'yes' => (Icons.check, tr('yes'), t.up),
      'no' => (Icons.close, tr('no'), t.down),
      _ => (Icons.hourglass_empty, _bi('waiting', 'anasubiri'), t.muted),
    };
    return Semantics(
      label: _bi('Member vote: {v}', 'Kura ya mwanachama: {v}', {'v': label}),
      excludeSemantics: true,
      child: SizedBox(
        width: 56,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: t.card,
                border: Border.all(color: c, width: 2),
              ),
              child: Icon(icon, size: 20, color: c),
            ),
            Text(
              label,
              style: Theme.of(context).textTheme.bodySmall,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

class _ResultBar extends StatelessWidget {
  const _ResultBar({
    required this.label,
    required this.icon,
    required this.count,
    required this.of,
    required this.color,
  });
  final String label;
  final IconData icon;
  final int count, of;
  final Color color;
  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final frac = of == 0 ? 0.0 : (count / of).clamp(0.0, 1.0);
    return Semantics(
      label: '$label: $count / $of',
      excludeSemantics: true,
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 4),
          SizedBox(
            width: 48,
            child: Text(label, style: tt.labelLarge, overflow: TextOverflow.ellipsis),
          ),
          Expanded(
            child: TweenAnimationBuilder<double>(
              tween: Tween(end: frac),
              duration: reduceMotion(context) ? Duration.zero : const Duration(milliseconds: 500),
              builder: (_, v, _) => ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: v,
                  minHeight: 12,
                  color: color,
                  backgroundColor: context.tokens.muted.withValues(alpha: .2),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text('$count', style: tt.labelLarge),
        ],
      ),
    );
  }
}
