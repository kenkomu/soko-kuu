import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:soko_kuu/main.dart';
import 'package:soko_kuu/run/run_widgets.dart';
import 'package:soko_kuu/run/soko_run_engine.dart';
import 'package:soko_kuu/run/soko_run_screen.dart';
import 'package:soko_kuu/state/providers.dart';
import 'package:soko_kuu/ui/kit/money.dart';

/// Mutable clock for the Daily Soko tests.
DateTime clock = DateTime.utc(2026, 11, 12, 9);

Future<SharedPreferences> bootRun(
  WidgetTester t, {
  Map<String, Object> prefs = const {},
  Size size = const Size(360, 740),
  int seed = 12345,
  MediaQueryData? media,
}) async {
  t.view.physicalSize = size;
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  SharedPreferences.setMockInitialValues({
    'age_ok': true,
    'entry': 'run',
    ...prefs,
  });
  final p = await SharedPreferences.getInstance();
  final c = ProviderContainer(
    overrides: [
      prefsProvider.overrideWithValue(p),
      runSeedProvider.overrideWithValue(() => seed),
      runClockProvider.overrideWithValue(() => clock),
    ],
  );
  addTearDown(c.dispose);
  Widget app = const SokoKuuApp();
  if (media != null) app = MediaQuery(data: media, child: app);
  await t.pumpWidget(UncontrolledProviderScope(container: c, child: app));
  await t.pumpAndSettle();
  return p;
}

Finder buyBtn(String id) => find.byKey(Key('buy-$id'));
Finder sellBtn(String id) => find.byKey(Key('sell-$id'));
Finder nextBtn() => find.byKey(const Key('run-next'));

bool buyOn(WidgetTester t, String id) =>
    t.widget<FilledButton>(buyBtn(id)).onPressed != null;
bool sellOn(WidgetTester t, String id) =>
    t.widget<OutlinedButton>(sellBtn(id)).onPressed != null;

String priceShown(WidgetTester t, String id) =>
    t.widget<Text>(find.byKey(Key('price-$id'))).data!;

Future<void> tapKey(WidgetTester t, Finder f, {int times = 1}) async {
  for (var i = 0; i < times; i++) {
    await t.ensureVisible(f);
    await t.pumpAndSettle();
    await t.tap(f);
    await t.pumpAndSettle();
  }
}

void main() {
  setUpAll(() => useSecureStorage = false);
  setUp(() => clock = DateTime.utc(2026, 11, 12, 9));

  testWidgets('full tutorial run: buy, radio right, sell, close, end screen', (
    t,
  ) async {
    await bootRun(t);
    expect(find.text('Soko Run'), findsOneWidget);
    expect(
      find.text('Points are for play only. They can\'t be cashed out.'),
      findsOneWidget,
    );
    await t.tap(find.text('Play your first market'));
    await t.pumpAndSettle();

    expect(find.text('Day 1 of 10'), findsOneWidget);
    expect(find.text('First market'), findsOneWidget);
    expect(find.text('1,000 pts'), findsOneWidget);
    expect(
      find.text(
        'Radio Soko says tomatoes will rise. Tap Buy on Tomato a few times, then tap Next day.',
      ),
      findsOneWidget,
    );
    expect(
      find.text('Radio Soko is right about 3 times in 4.'),
      findsOneWidget,
    );
    expect(priceShown(t, 'tomato'), '54');
    expect(find.text('-55'), findsOneWidget); // Buy shows the exact cost
    expect(find.text('+53'), findsOneWidget); // Sell shows the exact proceeds

    await tapKey(t, buyBtn('tomato'), times: 3);
    expect(find.text('835 pts'), findsOneWidget); // 1,000 - 3 x 55
    expect(find.textContaining('You have 6'), findsOneWidget);

    await t.ensureVisible(nextBtn());
    await t.tap(nextBtn());
    await t.pump();
    expect(priceShown(t, 'tomato'), '54'); // counts up from yesterday's price
    await t.pumpAndSettle();
    expect(find.text('Day 2 of 10'), findsOneWidget);
    expect(
      find.text('Radio was right. Tomato rose from 54 to 100.'),
      findsOneWidget,
    );
    expect(priceShown(t, 'tomato'), '100');
    expect(
      find.text(
        'You read it right! A spike falls back the next day, so sell your tomatoes now.',
      ),
      findsOneWidget,
    );

    await tapKey(t, sellBtn('tomato'), times: 6);
    expect(sellOn(t, 'tomato'), isFalse);
    await tapKey(t, find.byTooltip('Close hint'));
    expect(find.textContaining('You read it right'), findsNothing);

    for (var d = 2; d < 10; d++) {
      await tapKey(t, nextBtn());
    }
    expect(find.text('Day 10 of 10'), findsOneWidget);
    expect(find.text('Close the market'), findsOneWidget);
    expect(buyOn(t, 'maize'), isFalse);
    expect(sellOn(t, 'maize'), isFalse);
    await tapKey(t, nextBtn());

    // Same moves on the engine give the score the screen must show.
    final g = RunGame(makeMarket(12345, tutorial: true), mode: RunMode.first);
    for (var i = 0; i < 3; i++) {
      g.buy('tomato');
    }
    g.nextDay();
    for (var i = 0; i < 6; i++) {
      g.sell('tomato');
    }
    for (var d = 2; d < 10; d++) {
      g.nextDay();
    }
    final score = g.close();
    expect(find.text('The soko is closed.'), findsOneWidget);
    expect(find.text(fmt(score)), findsOneWidget);
    expect(find.text(runTitle(score)), findsOneWidget);
    expect(find.text('New best score!'), findsOneWidget);
    expect(find.text('Right ${g.rightCount} of 9 times.'), findsOneWidget);
    expect(
      find.text(
        'A player who never traded ended with ${fmt(g.lazyScore)} pts.',
      ),
      findsOneWidget,
    );
    expect(
      find.textContaining('Sold 6 tomatoes on day 2 at 100'),
      findsOneWidget,
    );
    final head = 'Soko Run \u00B7 ${fmt(score)} pts \u00B7 ${runTitle(score)}';
    expect(find.text(head), findsOneWidget);
    final share = '$head\n${runSquaresEmoji(g.squares)}\nCan you beat me?';

    String? copied;
    t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (c) async {
        if (c.method == 'Clipboard.setData') {
          copied = (c.arguments as Map)['text'] as String;
        }
        return null;
      },
    );
    addTearDown(
      () => t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await tapKey(t, find.text('Copy'));
    expect(copied, share);
    expect(find.text('Copied'), findsOneWidget);

    await tapKey(t, find.text('Back to start'));
    expect(find.text('Play a new market'), findsOneWidget);
    expect(
      find.textContaining('Your best: ${fmt(score)} pts.'),
      findsOneWidget,
    );
  });

  testWidgets('daily seed is the same all day and changes the next day', (
    t,
  ) async {
    await bootRun(t, prefs: {'run.played': true});
    Future<List<String>> playDaily(String label) async {
      await tapKey(t, find.text(label));
      final shown = [
        for (final g in runGoods) priceShown(t, g.id),
        t.widget<Text>(find.byKey(const Key('run-news'))).data!,
      ];
      await t.binding.handlePopRoute(); // system back: to the start screen
      await t.pumpAndSettle();
      return shown;
    }

    final morning = await playDaily('Daily Soko #1');
    clock = DateTime.utc(2026, 11, 12, 23, 30);
    final night = await playDaily('Daily Soko #1');
    expect(night, morning);
    final m = makeMarket(1799991269); // the prototype's seed for 2026-11-12
    expect(morning, [
      for (final g in runGoods) '${m.on(1)[g.id]}',
      m.rumourOn(1).text,
    ]);

    clock = DateTime.utc(2026, 11, 13, 6);
    await tapKey(t, find.text('Play a new market')); // any rebuild sees day 2
    await t.binding.handlePopRoute();
    await t.pumpAndSettle();
    final next = await playDaily('Daily Soko #2');
    final m2 = makeMarket(dailySeed(clock));
    expect(next, [
      for (final g in runGoods) '${m2.on(1)[g.id]}',
      m2.rumourOn(1).text,
    ]);
    expect(next, isNot(morning));
  });

  testWidgets('buttons: nothing to sell, 20 held, no cash, day 10', (t) async {
    await bootRun(t, prefs: {'run.played': true});
    await tapKey(t, find.text('Play a new market'));
    expect(find.text('Practice'), findsOneWidget);

    await tapKey(t, sellBtn('tomato'), times: 3);
    expect(sellOn(t, 'tomato'), isFalse); // nothing to sell
    expect(buyOn(t, 'tomato'), isTrue);

    await tapKey(t, buyBtn('maize'), times: kMaxHold - kStartEach);
    expect(buyOn(t, 'maize'), isFalse); // 20 held
    expect(sellOn(t, 'maize'), isTrue);
    expect(find.textContaining('You have 20 (full)'), findsOneWidget);

    var bought = 0;
    while (buyOn(t, 'tomato')) {
      await tapKey(t, buyBtn('tomato'));
      bought++;
    }
    expect(bought, lessThan(kMaxHold)); // stopped by cash, not by the limit
    final g = RunGame(makeMarket(12345));
    for (var i = 0; i < 3; i++) {
      g.sell('tomato');
    }
    while (g.buy('maize')) {}
    while (g.buy('tomato')) {}
    expect(g.hold['tomato'], bought);
    expect(g.cash, lessThan(g.buyCost('tomato')));
    expect(find.text(formatPts(g.cash)), findsOneWidget);

    for (var d = 1; d < kDays; d++) {
      await tapKey(t, nextBtn());
    }
    for (final x in runGoods) {
      expect(buyOn(t, x.id), isFalse, reason: 'day 10 buy ${x.id}');
      expect(sellOn(t, x.id), isFalse, reason: 'day 10 sell ${x.id}');
    }
  });

  testWidgets('press and hold Buy repeats until released', (t) async {
    await bootRun(t, prefs: {'run.played': true});
    await tapKey(t, find.text('Play a new market'));
    await t.ensureVisible(buyBtn('sukuma'));
    await t.pumpAndSettle();
    final hold = await t.startGesture(t.getCenter(buyBtn('sukuma')));
    await t.pump(const Duration(milliseconds: 400));
    for (var i = 0; i < 5; i++) {
      await t.pump(const Duration(milliseconds: 90));
    }
    await hold.up();
    await t.pumpAndSettle();
    final n = int.parse(
      RegExp(r'You have (\d+)')
          .firstMatch(
            t
                .widget<Text>(find.byKey(const Key('have-sukuma')))
                .textSpan!
                .toPlainText(),
          )!
          .group(1)!,
    );
    expect(n, greaterThanOrEqualTo(kStartEach + 5));
    await t.pump(const Duration(seconds: 1));
    await t.pumpAndSettle();
    final after = t
        .widget<Text>(find.byKey(const Key('have-sukuma')))
        .textSpan!
        .toPlainText();
    expect(after, startsWith('You have $n')); // stopped on release
  });

  for (final lang in ['en', 'sw']) {
    testWidgets(
      '320x640: no overflow, no sideways scroll, 48dp targets ($lang)',
      (t) async {
        final handle = t.ensureSemantics();
        await bootRun(t, size: const Size(320, 640), prefs: {'lang': lang});
        expect(t.takeException(), isNull);
        await expectLater(t, meetsGuideline(androidTapTargetGuideline));
        await expectLater(t, meetsGuideline(labeledTapTargetGuideline));
        await tapKey(t, find.byType(FilledButton).first);
        expect(t.takeException(), isNull);
        for (final g in runGoods) {
          final r = t.getRect(find.byKey(ValueKey('row-${g.id}')));
          expect(r.left, greaterThanOrEqualTo(0));
          expect(r.right, lessThanOrEqualTo(320));
        }
        await expectLater(t, meetsGuideline(androidTapTargetGuideline));
        await expectLater(t, meetsGuideline(labeledTapTargetGuideline));
        await tapKey(t, nextBtn());
        expect(t.takeException(), isNull);
        for (var d = 2; d <= kDays; d++) {
          await tapKey(t, nextBtn());
        }
        expect(t.takeException(), isNull);
        await expectLater(t, meetsGuideline(androidTapTargetGuideline));
        await expectLater(t, meetsGuideline(labeledTapTargetGuideline));
        handle.dispose();
      },
    );
  }

  testWidgets('320x640 at 200% text: run and end screens do not overflow', (
    t,
  ) async {
    await bootRun(
      t,
      size: const Size(320, 640),
      media: const MediaQueryData(
        size: Size(320, 640),
        textScaler: TextScaler.linear(2.0),
      ),
    );
    await tapKey(t, find.text('Play your first market'));
    expect(t.takeException(), isNull);
    for (var d = 1; d <= kDays; d++) {
      await tapKey(t, nextBtn());
      expect(t.takeException(), isNull, reason: 'day $d');
    }
    expect(find.text('The soko is closed.'), findsOneWidget);
  });

  testWidgets('reduced motion: the new price shows at once, no flash', (
    t,
  ) async {
    await bootRun(
      t,
      media: const MediaQueryData(
        size: Size(360, 740),
        disableAnimations: true,
      ),
    );
    await tapKey(t, find.text('Play your first market'));
    await t.tap(nextBtn());
    await t.pump();
    expect(priceShown(t, 'tomato'), '100'); // no count-up
  });

  testWidgets('entry: gate, choice, Soko Run, live market and back', (t) async {
    SharedPreferences.setMockInitialValues({});
    final p = await SharedPreferences.getInstance();
    await t.pumpWidget(
      ProviderScope(
        overrides: [prefsProvider.overrideWithValue(p)],
        child: const SokoKuuApp(),
      ),
    );
    await t.tap(find.text('I am 18 or older. Start'));
    await t.pumpAndSettle();
    expect(find.text('How do you want to play?'), findsOneWidget);
    await t.tap(find.text('Play Soko Run'));
    await t.pumpAndSettle();
    expect(find.text('Play your first market'), findsOneWidget);
    expect(p.getString('entry'), 'run');

    await tapKey(t, find.text('Live market on NEAR'));
    expect(find.textContaining('Bei za leo'), findsOneWidget);
    expect(p.getString('entry'), 'live');

    await t.tap(find.byTooltip('Settings').first);
    await t.pumpAndSettle();
    await t.tap(find.text('Play Soko Run'));
    await t.pumpAndSettle();
    expect(find.text('Play your first market'), findsOneWidget);
    expect(p.getString('entry'), 'run');
  });
}
