import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/models.dart';
import '../l10n.dart';
import '../run/entry.dart';
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
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            const KitengeBand(height: 10),
            if (!game.hasValue)
              Align(
                alignment: Alignment.centerRight,
                child: IconButton(
                  tooltip: tr('Settings'),
                  icon: const Icon(Icons.settings_outlined),
                  onPressed: () => _settings(context),
                ),
              ),
            Expanded(
              child: AsyncBody<GameState>(
                value: game,
                onRetry: () => ref.invalidate(gameProvider),
                builder: (g) => Column(
                  children: [
                    _BalanceHeader(g, onSettings: () => _settings(context)),
                    Expanded(child: _pages[_i]),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      floatingActionButton:
          game.hasValue && ref.watch(healthProvider).value?.mode == 'demo'
          ? _AdvanceButton(game.requireValue.player.phase)
          : null,
      bottomNavigationBar: NavigationBar(
        height: 72,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
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
    return FloatingActionButton.extended(
      backgroundColor: leaf,
      foregroundColor: Colors.white,
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

String _bi(String en, String sw) => gLang == 'sw' ? sw : en;

/// Indigo balance card (purse, credit available, freshness), Radio Soko strip
/// and the play-only line. Collapses to the purse at large text sizes.
class _BalanceHeader extends ConsumerStatefulWidget {
  const _BalanceHeader(this.g, {required this.onSettings});
  final GameState g;
  final VoidCallback onSettings;
  @override
  ConsumerState<_BalanceHeader> createState() => _BalanceHeaderState();
}

class _BalanceHeaderState extends ConsumerState<_BalanceHeader> {
  DateTime _seen = DateTime.now();
  bool? _open;

  @override
  void didUpdateWidget(covariant _BalanceHeader old) {
    super.didUpdateWidget(old);
    if (!identical(old.g, widget.g)) _seen = DateTime.now();
  }

  String _fresh() {
    final m = DateTime.now().difference(_seen).inMinutes;
    return m < 1
        ? _bi('Updated just now', 'Imesasishwa sasa hivi')
        : _bi('Updated $m min ago', 'Imesasishwa dakika $m zilizopita');
  }

  @override
  Widget build(BuildContext context) {
    final g = widget.g, p = g.player;
    final t = context.tokens;
    final tt = Theme.of(context).textTheme;
    final big = MediaQuery.textScalerOf(context).scale(14) / 14 > 1.3;
    final open = _open ?? !big;
    final mode = ref.watch(healthProvider).value?.mode;
    final on = t.onIndigo;
    final credit = p.creditAvailable;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Column(
        children: [
          Material(
            color: t.indigo,
            borderRadius: BorderRadius.circular(18),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 8, 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${tr('Day {d}', {'d': p.day})} · ${phaseName(p.phase)}${_countdown(p.nextPhaseMs, mode)}',
                          style: tt.bodySmall?.copyWith(
                            color: on,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      if (open || !big)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: t.ochre,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            tierName(p.tier),
                            style: const TextStyle(
                              color: charcoal,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      IconButton(
                        tooltip: tr('Settings'),
                        color: on,
                        icon: const Icon(Icons.settings_outlined),
                        onPressed: widget.onSettings,
                      ),
                    ],
                  ),
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: RollingNumber(
                        p.pts,
                        format: (n) => formatPts(n, unit: 'pts'),
                        style: (tt.headlineMedium ?? const TextStyle())
                            .copyWith(
                              color: on,
                              fontFamily: headingFont,
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                    ),
                  ),
                  if (open) ...[
                    Padding(
                      padding: const EdgeInsets.only(right: 8, bottom: 4),
                      child: Text(
                        '${credit != null ? _bi('Credit available: ${formatPts(credit)}', 'Mkopo unaopatikana: ${formatPts(credit)}') : _bi('Credit limit: ${formatPts(p.creditLimit)}', 'Kikomo cha mkopo: ${formatPts(p.creditLimit)}')} \u00B7 ${_fresh()}',
                        style: tt.bodySmall?.copyWith(color: on),
                      ),
                    ),
                  ],
                  if (big)
                    TextButton(
                      style: TextButton.styleFrom(
                        foregroundColor: on,
                        minimumSize: const Size(48, 48),
                      ),
                      onPressed: () => setState(() => _open = !open),
                      child: Text(
                        open
                            ? _bi('Show less', 'Onyesha kidogo')
                            : _bi('Show more', 'Onyesha zaidi'),
                      ),
                    ),
                ],
              ),
            ),
          ),
          if (open) _NewsStrip(g.news),
        ],
      ),
    );
  }
}

/// Radio Soko: one line with an ochre tag; tap to read the full text.
/// Static on purpose: no auto-scroll.
class _NewsStrip extends StatefulWidget {
  const _NewsStrip(this.news);
  final List<NewsItem> news;
  @override
  State<_NewsStrip> createState() => _NewsStripState();
}

class _NewsStripState extends State<_NewsStrip> {
  bool _open = false;
  @override
  Widget build(BuildContext context) {
    final news = widget.news;
    final tt = Theme.of(context).textTheme;
    final top = news.isEmpty
        ? tr('Radio Soko: no bulletins yet.')
        : newsText(news.first.kind, news.first.text);
    return Semantics(
      button: true,
      expanded: _open,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => setState(() => _open = !_open),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      margin: const EdgeInsets.only(top: 1),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: context.tokens.ochre,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        tr('Radio Soko'),
                        style: const TextStyle(
                          color: charcoal,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        top,
                        maxLines: _open ? null : 1,
                        overflow: _open ? null : TextOverflow.ellipsis,
                        style: tt.bodyMedium,
                      ),
                    ),
                    Icon(_open ? Icons.expand_less : Icons.expand_more),
                  ],
                ),
                if (_open && news.length > 1)
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 160),
                    child: ListView(
                      shrinkWrap: true,
                      padding: const EdgeInsets.only(top: 6),
                      children: [
                        for (final n in news.skip(1))
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 3),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(
                                  _newsIcon(n.kind),
                                  size: 18,
                                  color: context.tokens.muted,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    '${newsText(n.kind, n.text)} (${tr('Day {d}', {'d': n.day})})',
                                    style: tt.bodySmall,
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
              ],
            ),
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
      child: SingleChildScrollView(
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
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.directions_run),
              title: Text(tr('Play Soko Run')),
              subtitle: Text(
                tr('Ten quick market days, offline. Nothing is sent anywhere.'),
              ),
              onTap: () {
                Navigator.pop(context);
                ref.read(entryProvider.notifier).set(Entry.run);
              },
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
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(_bi('Sound', 'Sauti')),
              subtitle: Text(
                _bi(
                  'Off by default. A soft click after a sale.',
                  'Imezimwa kwa kawaida. Mlio mdogo baada ya kuuza.',
                ),
              ),
              value: ref.watch(soundProvider),
              onChanged: (v) => ref.read(soundProvider.notifier).set(v),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(_bi('Haptics', 'Mtetemo')),
              subtitle: Text(
                _bi(
                  'A small buzz when you trade.',
                  'Mtetemo mdogo unapofanya biashara.',
                ),
              ),
              value: ref.watch(hapticsProvider),
              onChanged: (v) => ref.read(hapticsProvider.notifier).set(v),
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
