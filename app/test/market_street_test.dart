import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:soko_kuu/l10n.dart';
import 'package:soko_kuu/main.dart';
import 'package:soko_kuu/run/market_street.dart';
import 'package:soko_kuu/state/providers.dart';

final walker = find.byKey(const Key('street-walker'));
Finder stall(String good) => find.byKey(Key('stall-$good'));

/// Centre of the trader sprite and of a stall's tap target, in pixels.
double walkerX(WidgetTester t) => t.getRect(walker).center.dx;
double stallX(WidgetTester t, String good) => t.getCenter(stall(good)).dx;

Future<List<String>> pumpStreet(WidgetTester t, {bool still = false}) async {
  t.view.physicalSize = const Size(360, 400);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  final arrived = <String>[];
  await t.pumpWidget(
    MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: still),
        child: child!,
      ),
      home: Scaffold(
        body: Align(
          alignment: Alignment.topCenter,
          child: SizedBox(
            width: 332,
            child: MarketStreet(onArrive: arrived.add),
          ),
        ),
      ),
    ),
  );
  return arrived;
}

void main() {
  setUpAll(() => useSecureStorage = false);

  test('the market street is off unless the build turns it on', () {
    expect(kMarketStreet, isFalse);
    expect(ProviderContainer().read(marketStreetProvider), isFalse);
  });

  testWidgets('tap a stall: the trader walks there in 0.8 s at most', (
    t,
  ) async {
    final arrived = await pumpStreet(t);
    final start = walkerX(t);
    final baraka = stallX(t, 'sukuma');
    expect(start, lessThan(baraka));

    await t.tap(stall('sukuma'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 200));
    final mid = walkerX(t);
    expect(mid, greaterThan(start));
    expect(mid, lessThan(baraka));
    expect(arrived, isEmpty);

    await t.pump(const Duration(milliseconds: 600));
    expect(arrived, ['sukuma']);
    expect(walkerX(t), moreOrLessEquals(baraka, epsilon: 2));

    // The longest walk on the street, Baraka to Njeri, also fits in 0.8 s.
    await t.tap(stall('tomato'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 400));
    expect(arrived, ['sukuma']);
    await t.pump(const Duration(milliseconds: 400));
    expect(arrived, ['sukuma', 'tomato']);
    expect(walkerX(t), moreOrLessEquals(stallX(t, 'tomato'), epsilon: 2));

    // Tapping the stall you stand at opens it again at once.
    await t.tap(stall('tomato'));
    await t.pump();
    expect(arrived, ['sukuma', 'tomato', 'tomato']);
    await t.pumpAndSettle();
  });

  testWidgets('tap again to skip the walk', (t) async {
    final arrived = await pumpStreet(t);
    await t.tap(stall('sukuma'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 100));
    expect(arrived, isEmpty);

    await t.tap(stall('sukuma'));
    await t.pump();
    expect(arrived, ['sukuma']);
    expect(walkerX(t), moreOrLessEquals(stallX(t, 'sukuma'), epsilon: 2));
    await t.pump(const Duration(seconds: 1));
    expect(arrived, ['sukuma'], reason: 'arrives once');

    // A tap on the open street (between stalls) skips too.
    await t.tap(stall('tomato'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 100));
    final box = t.getRect(find.byKey(const Key('street')));
    await t.tapAt(
      Offset(box.left + box.width * .36, box.top + box.height * .5),
    );
    await t.pump();
    expect(arrived, ['sukuma', 'tomato']);
    expect(walkerX(t), moreOrLessEquals(stallX(t, 'tomato'), epsilon: 2));
  });

  testWidgets('reduced motion: the trader appears at the stall, no walk', (
    t,
  ) async {
    final arrived = await pumpStreet(t, still: true);
    await t.tap(stall('maize'));
    await t.pump();
    expect(arrived, ['maize']);
    expect(walkerX(t), moreOrLessEquals(stallX(t, 'maize'), epsilon: 2));

    await t.tap(stall('sukuma'));
    await t.pump();
    expect(arrived, ['maize', 'sukuma']);
    expect(walkerX(t), moreOrLessEquals(stallX(t, 'sukuma'), epsilon: 2));
  });

  testWidgets('keyboard: Tab rings a stall, Enter walks there', (t) async {
    final arrived = await pumpStreet(t, still: true);
    Finder ring(String good) => find.descendant(
      of: stall(good),
      matching: find.byWidgetPredicate(
        (w) =>
            w is DecoratedBox && (w.decoration as BoxDecoration).border != null,
      ),
    );
    expect(ring('tomato'), findsNothing);
    await t.sendKeyEvent(LogicalKeyboardKey.tab);
    await t.pump();
    expect(ring('tomato'), findsOneWidget);
    await t.sendKeyEvent(LogicalKeyboardKey.tab);
    await t.pump();
    expect(ring('tomato'), findsNothing);
    expect(ring('maize'), findsOneWidget);
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    await t.pump();
    expect(arrived, ['maize']);
  });

  testWidgets('stalls are labelled buttons; the scenery is hidden', (t) async {
    final sem = t.ensureSemantics();
    await pumpStreet(t);
    for (final label in [
      'Njeri\'s tomato stall',
      'Wanjiru\'s maize stall',
      'Baraka\'s sukuma stall',
    ]) {
      expect(
        t.getSemantics(find.bySemanticsLabel(label)),
        matchesSemantics(
          label: label,
          isButton: true,
          hasTapAction: true,
          isFocusable: true,
          hasFocusAction: true,
        ),
      );
    }
    // Only the three stalls speak; the plate and trader are decorative.
    expect(find.bySemanticsLabel(RegExp('.')), findsNWidgets(3));
    for (final i in t.widgetList<Image>(find.byType(Image))) {
      expect(i.excludeFromSemantics, isTrue);
    }

    gLang = 'sw';
    addTearDown(() => gLang = 'en');
    await pumpStreet(t);
    expect(
      find.bySemanticsLabel('Kibanda cha nyanya cha Njeri'),
      findsOneWidget,
    );
    sem.dispose();
  });

  testWidgets('Soko Run: no street by default; with it on, a stall walk '
      'brings that good\'s Buy and Sell into view', (t) async {
    t.view.physicalSize = const Size(360, 600);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);

    Future<void> boot({required bool street}) async {
      SharedPreferences.setMockInitialValues({'age_ok': true, 'entry': 'run'});
      final p = await SharedPreferences.getInstance();
      final c = ProviderContainer(
        overrides: [
          prefsProvider.overrideWithValue(p),
          if (street) marketStreetProvider.overrideWithValue(true),
        ],
      );
      addTearDown(c.dispose);
      await t.pumpWidget(
        UncontrolledProviderScope(container: c, child: const SokoKuuApp()),
      );
      await t.pumpAndSettle();
      await t.tap(find.text('Play your first market'));
      await t.pumpAndSettle();
    }

    await boot(street: false);
    expect(find.byKey(const Key('buy-tomato')), findsOneWidget);
    expect(find.byType(MarketStreet), findsNothing);
    expect(find.byType(StallSpotlight), findsNothing);

    await t.pumpWidget(const SizedBox());
    await boot(street: true);
    expect(find.byType(MarketStreet), findsOneWidget);
    final row = find.byKey(const ValueKey('row-sukuma'));
    final next = find.byKey(const Key('run-next'));
    expect(t.getRect(row).bottom, greaterThan(t.getRect(next).top));

    await t.tap(stall('sukuma'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 800));
    await t.pump(const Duration(milliseconds: 300));
    expect(
      find.ancestor(
        of: row,
        matching: find.byKey(const Key('stall-spotlight')),
      ),
      findsOneWidget,
    );
    await t.pumpAndSettle();
    expect(find.byKey(const Key('stall-spotlight')), findsNothing);
    expect(t.getRect(row).bottom, lessThanOrEqualTo(t.getRect(next).top));
    expect(find.byKey(const Key('buy-sukuma')).hitTestable(), findsOneWidget);
  });
}
