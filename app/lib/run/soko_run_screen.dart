import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../l10n.dart';
import '../state/providers.dart';
import '../ui/kit/feel.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';
import 'entry.dart';
import 'run_widgets.dart';
import 'soko_run_engine.dart';

/// Clock for the Daily Soko. Tests override it.
final runClockProvider = Provider<DateTime Function()>((ref) => DateTime.now);

/// Seed for a new practice or first market. Tests override it.
final runSeedProvider = Provider<int Function()>((ref) {
  final r = math.Random();
  return () => r.nextInt(0x100000000);
});

enum _View { start, run, end }

/// Soko Run: a self-contained offline mode. It never calls the runner or the
/// chain; its points are separate from the live game's points. Best scores
/// live in prefs as `best.run` and `best.daily.N`.
class SokoRunScreen extends ConsumerStatefulWidget {
  const SokoRunScreen({super.key});

  @override
  ConsumerState<SokoRunScreen> createState() => _SokoRunScreenState();
}

class _SokoRunScreenState extends ConsumerState<SokoRunScreen>
    with SingleTickerProviderStateMixin {
  var _view = _View.start;
  RunGame? _g;
  int _best = 0;
  bool _newBest = false;
  bool _copied = false;
  final _scroll = ScrollController();
  late final AnimationController _fx = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: kRevealMs),
    value: 1,
  );

  SharedPreferences get _prefs => ref.read(prefsProvider);
  bool get _played => _prefs.getBool('run.played') ?? false;
  DateTime _now() => ref.read(runClockProvider)();

  @override
  void dispose() {
    _fx.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _start(RunMode mode) {
    final now = _now();
    final seed = mode == RunMode.daily
        ? dailySeed(now)
        : ref.read(runSeedProvider)();
    final g = RunGame(
      makeMarket(seed, tutorial: mode == RunMode.first),
      mode: mode,
      dailyNo: dailyNumber(now),
    );
    _prefs.setBool('run.played', true);
    _fx.value = 1;
    setState(() {
      _g = g;
      _view = _View.run;
      _copied = false;
    });
    _toTop();
  }

  void _play() => _start(_played ? RunMode.practice : RunMode.first);

  void _toTop() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) _scroll.jumpTo(0);
    });
  }

  bool _trade(String id, {required bool buy}) {
    final g = _g;
    if (g == null || _view != _View.run) return false;
    final ok = buy ? g.buy(id) : g.sell(id);
    if (ok) {
      Feel.light();
      setState(() {});
    }
    return ok;
  }

  void _next() {
    final g = _g!;
    if (g.lastDay) return _close();
    final rv = g.nextDay();
    if (reduceMotion(context)) {
      _fx.value = 1;
    } else {
      _fx.forward(from: 0);
    }
    if ((rv.after - rv.before).abs() > 50 && Feel.haptics) {
      HapticFeedback.mediumImpact();
    }
    if (_scroll.hasClients) _scroll.jumpTo(0); // show the reveal at once
    setState(() {});
  }

  void _close() {
    final g = _g!;
    final score = g.close();
    final key = g.mode == RunMode.daily
        ? 'best.daily.${g.dailyNo}'
        : 'best.run';
    final prev = _prefs.getInt(key);
    _newBest = prev == null || score > prev;
    _best = prev == null ? score : math.max(prev, score);
    if (_newBest) _prefs.setInt(key, score);
    Feel.saleTick();
    setState(() => _view = _View.end);
    _toTop();
  }

  void _home() => setState(() => _view = _View.start);

  @override
  Widget build(BuildContext context) {
    final body = switch (_view) {
      _View.start => _startView(context),
      _View.run => _runView(context),
      _View.end => _endView(context),
    };
    return PopScope(
      canPop: _view == _View.start,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _home();
      },
      child: Scaffold(
        body: SafeArea(
          child: Column(
            children: [
              const KitengeBand(height: 14),
              Expanded(
                child: Align(
                  alignment: Alignment.topCenter,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 480),
                    child: SizedBox(width: double.infinity, child: body),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------- start

  Widget _startView(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final t = context.tokens;
    final best = _prefs.getInt('best.run');
    final small = TextStyle(fontSize: 13, color: t.muted);
    final gear = IconButton(
      tooltip: tr('Settings'),
      icon: const Icon(Icons.settings_outlined),
      onPressed: () => showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        builder: (_) => const _RunSettings(),
      ),
    );
    final page = LayoutBuilder(
      builder: (context, box) => SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: box.maxHeight),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(22, 52, 22, 22),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Soko Run',
                  style: TextStyle(
                    fontFamily: headingFont,
                    fontWeight: FontWeight.w700,
                    fontSize: 54,
                    height: .95,
                    color: cs.tertiary,
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  tr(
                    'Ten market days. Listen to Radio Soko, buy low, sell high.',
                  ),
                  style: const TextStyle(fontSize: 17, height: 1.4),
                ),
                const SizedBox(height: 18),
                FilledButton(
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(48, 56),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                    textStyle: const TextStyle(
                      fontFamily: headingFont,
                      fontWeight: FontWeight.w700,
                      fontSize: 20,
                    ),
                  ),
                  onPressed: _play,
                  child: Text(
                    _played
                        ? tr('Play a new market')
                        : tr('Play your first market'),
                  ),
                ),
                const SizedBox(height: 12),
                OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(48, 52),
                    foregroundColor: cs.tertiary,
                    side: BorderSide(color: cs.tertiary, width: 2),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                    textStyle: const TextStyle(
                      fontFamily: bodyFont,
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                    ),
                  ),
                  onPressed: () => _start(RunMode.daily),
                  child: Text(
                    tr('Daily Soko #{n}', {'n': dailyNumber(_now())}),
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  '${best != null ? '${tr('Your best: {n} pts.', {'n': fmt(best)})} ' : ''}'
                  '${tr('The Daily Soko is the same 10 days for everyone today.')}',
                  style: small,
                ),
                const SizedBox(height: 8),
                Text(
                  tr('Points are for play only. They can\'t be cashed out.'),
                  style: small,
                ),
                const SizedBox(height: 4),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    style: TextButton.styleFrom(
                      padding: EdgeInsets.zero,
                      foregroundColor: cs.tertiary,
                    ),
                    icon: const Icon(Icons.groups_outlined, size: 20),
                    onPressed: () =>
                        ref.read(entryProvider.notifier).set(Entry.live),
                    label: Text(tr('Live market on NEAR')),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    return Stack(
      children: [
        page,
        Positioned(top: 4, right: 8, child: gear),
      ],
    );
  }

  // ------------------------------------------------------------------ run

  Widget _runView(BuildContext context) {
    final g = _g!;
    final still = reduceMotion(context);
    final cs = Theme.of(context).colorScheme;
    final t = context.tokens;
    final hint = switch (g.hint) {
      1 => RunHint(
        tr(
          'Radio Soko says tomatoes will rise. Tap **Buy** on Tomato a few times, then tap **Next day**.',
        ),
      ),
      2 => RunHint(
        tr(
          'You read it right! A spike falls back the next day, so **sell your tomatoes now**.',
        ),
        onClose: () => setState(() => g.hint = 0),
      ),
      _ => null,
    };
    // Pinned so points and the total stay in view while trading; at large
    // text sizes it scrolls with the rest so the goods still fit.
    final pin = MediaQuery.textScalerOf(context).scale(14) / 14 <= 1.3;
    final bar = RunTopBar(g, fx: _fx, still: still);
    return Column(
      children: [
        if (pin)
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
            child: bar,
          ),
        Expanded(
          child: SingleChildScrollView(
            controller: _scroll,
            padding: EdgeInsets.fromLTRB(14, pin ? 0 : 12, 14, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (!pin) bar,
                if (g.reveal != null) ...[
                  const SizedBox(height: 12),
                  RunRevealBanner(g),
                ],
                const SizedBox(height: 12),
                RunRadioCard(g, fx: _fx, still: still),
                if (hint != null) ...[const SizedBox(height: 12), hint],
                for (final x in runGoods) ...[
                  const SizedBox(height: 10),
                  RunGoodRow(
                    g,
                    x.id,
                    key: ValueKey('row-${x.id}'),
                    fx: _fx,
                    still: still,
                    onTrade: _trade,
                  ),
                ],
              ],
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
          decoration: BoxDecoration(
            color: cs.surface,
            border: Border(top: BorderSide(color: cs.outlineVariant)),
          ),
          child: FilledButton(
            key: const Key('run-next'),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(56),
              backgroundColor: t.indigo,
              foregroundColor: t.onIndigo,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
              textStyle: const TextStyle(
                fontFamily: headingFont,
                fontWeight: FontWeight.w700,
                fontSize: 20,
              ),
            ),
            onPressed: _next,
            child: g.lastDay
                ? Text(tr('Close the market'))
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(child: Text(tr('Next day'))),
                      const SizedBox(width: 8),
                      const Icon(Icons.arrow_forward),
                    ],
                  ),
          ),
        ),
      ],
    );
  }

  // ------------------------------------------------------------------ end

  Widget _endView(BuildContext context) {
    final g = _g!;
    final cs = Theme.of(context).colorScheme;
    final t = context.tokens;
    final still = reduceMotion(context);
    final score = g.score;
    final title = runTitle(score);
    final shareHead =
        'Soko Run'
        '${g.mode == RunMode.daily ? ' \u00B7 ${tr('Daily #{n}', {'n': g.dailyNo})}' : ''}'
        ' \u00B7 ${fmt(score)} pts \u00B7 $title';
    // Emoji only in the copied text; the screen draws the squares as icons.
    final share =
        '$shareHead\n${runSquaresEmoji(g.squares)}\n${tr('Can you beat me?')}';
    final scoreStyle = TextStyle(
      fontFamily: headingFont,
      fontWeight: FontWeight.w700,
      fontSize: 56,
      height: 1,
      color: cs.tertiary,
      fontFeatures: tabular,
    );

    Widget fact(String label, Widget body) => Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: t.card,
        border: Border.all(color: cs.outlineVariant),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              letterSpacing: .7,
              color: t.muted,
            ),
          ),
          const SizedBox(height: 2),
          DefaultTextStyle.merge(
            style: const TextStyle(fontSize: 14),
            child: body,
          ),
        ],
      ),
    );

    Widget move(RunSale s) {
      final p = {
        'q': s.qty,
        'g': runGoodNoun(s.id, s.qty),
        'd': s.day,
        'p': fmt(s.price),
      };
      final gain = jsRound(s.profit.abs());
      return Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: s.closing
                  ? tr('Sold {q} {g} at closing at {p}', p)
                  : tr('Sold {q} {g} on day {d} at {p}', p),
            ),
            const TextSpan(text: ': '),
            TextSpan(
              text: '${s.profit >= 0 ? '+' : '-'}${formatPts(gain)}',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                color: s.profit >= 0 ? t.up : t.down,
              ),
            ),
          ],
        ),
      );
    }

    final best = g.bestMove, worst = g.worstMove;
    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            controller: _scroll,
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  tr('The soko is closed.'),
                  style: TextStyle(fontSize: 13, color: t.muted),
                ),
                const SizedBox(height: 10),
                Semantics(
                  label: formatPts(score),
                  excludeSemantics: true,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: still
                        ? Text(fmt(score), style: scoreStyle)
                        : TweenAnimationBuilder<double>(
                            tween: Tween(begin: 0, end: score.toDouble()),
                            duration: const Duration(milliseconds: 900),
                            curve: Curves.easeOutCubic,
                            builder: (_, v, _) =>
                                Text(fmt(v.round()), style: scoreStyle),
                          ),
                  ),
                ),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: t.ochre,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      title,
                      style: const TextStyle(
                        color: charcoal,
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                if (_newBest)
                  Row(
                    children: [
                      Icon(Icons.star, color: t.up, size: 20),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          tr('New best score!'),
                          style: TextStyle(
                            color: t.up,
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                          ),
                        ),
                      ),
                    ],
                  )
                else
                  boldSpans(
                    tr('Your best: {n}', {'n': '**${fmt(_best)}**'}),
                    const TextStyle(fontSize: 15),
                  ),
                const SizedBox(height: 14),
                fact(
                  tr('Radio Soko'),
                  Text(
                    tr('Right {x} of {n} times.', {
                      'x': g.rightCount,
                      'n': g.shown,
                    }),
                  ),
                ),
                if (best != null) ...[
                  const SizedBox(height: 8),
                  fact(tr('Best move'), move(best)),
                ],
                if (worst != null) ...[
                  const SizedBox(height: 8),
                  fact(tr('Worst move'), move(worst)),
                ],
                const SizedBox(height: 8),
                fact(
                  tr('Compared with doing nothing'),
                  Text(
                    tr('A player who never traded ended with {n} pts.', {
                      'n': fmt(g.lazyScore),
                    }),
                  ),
                ),
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.fromLTRB(12, 10, 8, 8),
                  decoration: BoxDecoration(
                    color: t.card,
                    border: Border.all(color: cs.outlineVariant),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(shareHead, style: const TextStyle(fontSize: 14)),
                      const SizedBox(height: 8),
                      RunSquares(g.squares),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              tr('Can you beat me?'),
                              style: const TextStyle(fontSize: 14),
                            ),
                          ),
                          TextButton.icon(
                            style: TextButton.styleFrom(
                              foregroundColor: cs.tertiary,
                            ),
                            icon: Icon(
                              _copied ? Icons.check : Icons.copy,
                              size: 18,
                            ),
                            onPressed: () async {
                              await Clipboard.setData(
                                ClipboardData(text: share),
                              );
                              if (mounted) setState(() => _copied = true);
                            },
                            label: Text(_copied ? tr('Copied') : tr('Copy')),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
          decoration: BoxDecoration(
            color: cs.surface,
            border: Border(top: BorderSide(color: cs.outlineVariant)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              FilledButton(
                style: FilledButton.styleFrom(
                  minimumSize: const Size(48, 56),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                  ),
                  textStyle: const TextStyle(
                    fontFamily: headingFont,
                    fontWeight: FontWeight.w700,
                    fontSize: 20,
                  ),
                ),
                onPressed: _play,
                child: Text(tr('Play again')),
              ),
              const SizedBox(height: 8),
              OutlinedButton(
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(48, 52),
                  foregroundColor: cs.tertiary,
                  side: BorderSide(color: cs.tertiary, width: 2),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                  ),
                ),
                onPressed: _home,
                child: Text(tr('Back to start')),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Sound, haptics and language, reachable from the Soko Run start screen.
class _RunSettings extends ConsumerWidget {
  const _RunSettings();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
              title: Text(tr('Sound')),
              value: ref.watch(soundProvider),
              onChanged: (v) => ref.read(soundProvider.notifier).set(v),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(tr('Haptics')),
              value: ref.watch(hapticsProvider),
              onChanged: (v) => ref.read(hapticsProvider.notifier).set(v),
            ),
            const SizedBox(height: 8),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'en', label: Text('English')),
                ButtonSegment(value: 'sw', label: Text('Kiswahili')),
              ],
              selected: {ref.watch(langProvider)},
              onSelectionChanged: (v) =>
                  ref.read(langProvider.notifier).set(v.first),
            ),
          ],
        ),
      ),
    );
  }
}
