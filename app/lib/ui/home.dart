import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/models.dart';
import '../l10n.dart';
import '../state/providers.dart';
import 'chama_screen.dart';
import 'credit_screen.dart';
import 'market_screen.dart';
import 'report_screen.dart';
import 'stall_screen.dart';
import 'theme.dart';
import 'widgets.dart';

class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});
  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  int _i = 0;
  static const _pages = <Widget>[
    MarketScreen(),
    StallScreen(),
    ChamaScreen(),
    CreditScreen(),
    ReportScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    final game = ref.watch(gameProvider);
    ref.listen(gameProvider, (p, n) {
      final m = n.value?.message;
      if (m != null && m != p?.value?.message) toast(context, m);
    });
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 16,
        title: game.when(
          data: (g) => Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${tr('Day {d}', {'d': g.player.day})} · ${phaseName(g.player.phase)}${_countdown(g.player.nextPhaseMs, ref.watch(healthProvider).value?.mode)}',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Num(
                      pts(g.player.pts),
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
              Chip(
                label: Text(tierName(g.player.tier)),
                visualDensity: VisualDensity.compact,
                backgroundColor: ochre.withValues(alpha: .3),
              ),
            ],
          ),
          loading: () => const Text('Soko Kuu'),
          error: (_, _) => const Text('Soko Kuu'),
        ),
        actions: [
          IconButton(
            tooltip: tr('Settings'),
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => _settings(context),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(40),
          child: _NewsStrip(game.value?.news ?? const []),
        ),
      ),
      // The demo clock button sits in its own strip under the page (not a
      // floating button) so it never covers list content.
      body: Column(
        children: [
          Expanded(
            child: AsyncBody<GameState>(
              value: game,
              onRetry: () => ref.invalidate(gameProvider),
              builder: (_) => _pages[_i],
            ),
          ),
          if (game.hasValue && ref.watch(healthProvider).value?.mode == 'demo')
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: _AdvanceButton(game.requireValue.player.phase),
            ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _i,
        onDestinationSelected: (v) => setState(() => _i = v),
        destinations: [
          NavigationDestination(
            icon: Icon(Icons.storefront_outlined),
            selectedIcon: Icon(Icons.storefront),
            label: tr('Soko'),
          ),
          NavigationDestination(
            icon: Icon(Icons.inventory_2_outlined),
            selectedIcon: Icon(Icons.inventory_2),
            label: tr('Duka'),
          ),
          NavigationDestination(
            icon: Icon(Icons.groups_outlined),
            selectedIcon: Icon(Icons.groups),
            label: tr('Chama'),
          ),
          NavigationDestination(
            icon: Icon(Icons.receipt_long_outlined),
            selectedIcon: Icon(Icons.receipt_long),
            label: tr('Deni'),
          ),
          NavigationDestination(
            icon: Icon(Icons.menu_book_outlined),
            selectedIcon: Icon(Icons.menu_book),
            label: tr('Ripoti'),
          ),
        ],
      ),
    );
  }

  void _settings(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (_) => const _SettingsSheet(),
    );
  }
}

String _countdown(int? v, String? mode) {
  if (v == null || mode == 'demo') return '';
  final ms = v > 1000000000000 ? v - DateTime.now().millisecondsSinceEpoch : v;
  if (ms <= 0) return ' \u00B7 ${tr('next phase soon')}';
  final m = ms ~/ 60000, sec = (ms ~/ 1000) % 60;
  return ' \u00B7 ${tr('next in {t}', {'t': '$m:${sec.toString().padLeft(2, '0')}'})}';
}

class _AdvanceButton extends ConsumerWidget {
  const _AdvanceButton(this.phase);
  final Phase phase;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final label = switch (phase) {
      Phase.dawn => tr('Go to midday'),
      Phase.midday => tr('Go to dusk'),
      Phase.dusk => tr('Close day'),
    };
    return FilledButton.icon(
      style: FilledButton.styleFrom(
        backgroundColor: leaf,
        foregroundColor: Colors.white,
        minimumSize: const Size.fromHeight(48),
      ),
      icon: const Icon(Icons.wb_twilight),
      label: Text(label),
      onPressed: () async {
        final err = await ref.read(gameProvider.notifier).act({
          'type': 'advance',
        });
        if (err != null && context.mounted) toast(context, err, error: true);
      },
    );
  }
}

/// Radio Soko: one-line strip under the app bar; tap for the feed.
class _NewsStrip extends StatelessWidget {
  const _NewsStrip(this.news);
  final List<NewsItem> news;
  @override
  Widget build(BuildContext context) {
    final top = news.isEmpty
        ? tr('Radio Soko: no bulletins yet.')
        : newsText(news.first.kind, news.first.text);
    return Material(
      color: paper,
      child: InkWell(
        onTap: () => showModalBottomSheet<void>(
          context: context,
          showDragHandle: true,
          isScrollControlled: true,
          builder: (_) => DraggableScrollableSheet(
            expand: false,
            initialChildSize: .6,
            builder: (c, sc) => ListView(
              controller: sc,
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  tr('Radio Soko'),
                  style: Theme.of(context).textTheme.titleLarge
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 8),
                for (final n in news)
                  ListTile(
                    leading: Icon(_newsIcon(n.kind), color: terracotta),
                    title: Text(newsText(n.kind, n.text)),
                    subtitle: Text(tr('Day {d}', {'d': n.day})),
                  ),
              ],
            ),
          ),
        ),
        child: SizedBox(
          height: 40,
          child: Row(
            children: [
              const SizedBox(width: 16),
              const Icon(Icons.radio, size: 18, color: terracotta),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  top,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13),
                ),
              ),
              const Icon(Icons.expand_less, size: 18),
              const SizedBox(width: 12),
            ],
          ),
        ),
      ),
    );
  }
}

IconData _newsIcon(String k) => switch (k) {
  'ukame' => Icons.wb_sunny_outlined,
  'fuel' => Icons.local_gas_station_outlined,
  'road' => Icons.add_road,
  'festival' => Icons.celebration_outlined,
  'harvest' => Icons.agriculture_outlined,
  'glut' => Icons.trending_down,
  _ => Icons.campaign_outlined,
};

class _SettingsSheet extends ConsumerWidget {
  const _SettingsSheet();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final demo = ref.watch(demoModeProvider);
    final health = ref.watch(healthProvider);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              tr('Settings'),
              style: Theme.of(context).textTheme.titleLarge
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(tr('Offline demo mode')),
              subtitle: Text(
                tr(
                  'Plays against a built-in market. Nothing is sent anywhere.',
                ),
              ),
              value: demo,
              onChanged: (v) {
                ref.read(demoModeProvider.notifier).set(v);
                ref.invalidate(sessionProvider);
                ref.invalidate(gameProvider);
                Navigator.pop(context);
              },
            ),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'en', label: Text('English')),
                ButtonSegment(value: 'sw', label: Text('Kiswahili')),
              ],
              selected: {ref.watch(langProvider)},
              onSelectionChanged: (v) =>
                  ref.read(langProvider.notifier).set(v.first),
            ),
            health.when(
              data: (h) => Text(
                tr('Market: {m} · {c} · v{v}', {
                  'm': h.mode,
                  'c': h.chainId,
                  'v': h.version,
                }),
                style: const TextStyle(fontSize: 12),
              ),
              loading: () => const SizedBox.shrink(),
              error: (e, _) => Text(
                tr('Market unreachable. Try demo mode.'),
                style: TextStyle(fontSize: 12),
              ),
            ),
            if (!demo)
              TextButton.icon(
                icon: const Icon(Icons.delete_outline),
                label: Text(tr('Delete my account (removes email link)')),
                onPressed: () async {
                  final err = await ref.read(gameProvider.notifier).act({
                    'type': 'delete_account',
                  });
                  if (!context.mounted) return;
                  if (err != null) {
                    toast(context, err, error: true);
                  } else {
                    Navigator.pop(context);
                  }
                },
              ),
            const SizedBox(height: 8),
            Text(
              tr(
                'Your play key is stored on this device. On the web it is a throwaway demo key: clearing site data starts a new player.',
              ),
              style: TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 8),
            Text(
              tr(
                'Pointi (pts) are for play only. They cannot be bought, sent or cashed out.',
              ),
              style: TextStyle(fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}
