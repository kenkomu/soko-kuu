import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:soko_kuu/main.dart';
import 'package:soko_kuu/state/providers.dart';
import 'package:soko_kuu/state/trade_book.dart';

Future<ProviderContainer> boot(
  WidgetTester t,
  Map<String, Object> seed, {
  Size size = const Size(360, 800),
}) async {
  t.view.physicalSize = size;
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  SharedPreferences.setMockInitialValues({
    'age_ok': true,
    'tut_done': true,
    'goal_hidden': true,
    ...seed,
  });
  final prefs = await SharedPreferences.getInstance();
  final c = ProviderContainer(
    overrides: [prefsProvider.overrideWithValue(prefs)],
  );
  addTearDown(c.dispose);
  await t.pumpWidget(
    UncontrolledProviderScope(container: c, child: const SokoKuuApp()),
  );
  await t.pumpAndSettle();
  return c;
}

final buyRow = find.textContaining(RegExp(r'^Buy [\d,]+$'));

Future<void> midday(WidgetTester t) async {
  await t.tap(find.text('Go to midday'));
  await t.pumpAndSettle();
}

void main() {
  setUpAll(() => useSecureStorage = false);

  testWidgets('one row per good, not per merchant', (t) async {
    final c = await boot(t, {});
    final prices = c.read(gameProvider).requireValue.prices;
    final goods = prices.map((p) => p.good).toSet();
    expect(
      prices.length,
      greaterThan(goods.length),
    ); // several merchants per good
    expect(buyRow, findsNWidgets(goods.length));
    expect(
      find.textContaining(RegExp(r'^Sell [\d,]+$')),
      findsNWidgets(goods.length),
    );
    // lowest ask / highest bid across merchants, real values
    for (final g in goods) {
      final rows = prices.where((p) => p.good == g);
      final lo = rows.map((p) => p.ask).reduce((a, b) => a < b ? a : b);
      expect(
        find.text(
          'Buy ${lo.toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+$)'), (_) => ',')}',
        ),
        findsWidgets,
      );
    }
  });

  testWidgets('tap a row: why lines, merchants, stepper, buy and sell', (
    t,
  ) async {
    await boot(t, {});
    await midday(t);
    await t.tap(find.text('Tomato').first);
    await t.pumpAndSettle();
    expect(find.text('Quantity'), findsOneWidget);
    expect(find.byTooltip('More Tomato'), findsOneWidget);
    expect(find.byTooltip('Fewer Tomato'), findsOneWidget);
    expect(find.textContaining('Best to buy from:'), findsOneWidget);
    expect(find.textContaining('Best to sell to:'), findsOneWidget);
    expect(find.text('Why this price?'), findsOneWidget);
    expect(find.textContaining('•'), findsWidgets); // why lines open by default
    expect(find.text('Buy'), findsOneWidget);
    expect(find.text('Sell'), findsOneWidget);
    await t.tap(find.byTooltip('More Tomato'));
    await t.pumpAndSettle();
    expect(find.text('2'), findsWidgets);
  });

  testWidgets('before midday the buttons are disabled with the reason', (
    t,
  ) async {
    await boot(t, {});
    await t.tap(find.text('Tomato').first);
    await t.pumpAndSettle();
    expect(find.textContaining('trades at midday'), findsOneWidget);
    expect(
      t
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Buy'))
          .onPressed,
      isNull,
    );
  });

  testWidgets('sack: empty line, then a gain and a loss', (t) async {
    await boot(t, {});
    expect(find.textContaining('Your sack is empty'), findsOneWidget);
    expect(find.text('Your sack'), findsNothing);
  });

  for (final gain in [true, false]) {
    testWidgets('sack shows a ${gain ? 'gain' : 'loss'} with sign and arrow', (
      t,
    ) async {
      // Earlier buy at 100 (cheap) or 100000 (dear) per unit, then one real buy.
      await boot(t, {'cb_tomato': gain ? '1:100:1' : '1:100000:1'});
      await midday(t);
      await t.tap(find.text('Tomato').first);
      await t.pumpAndSettle();
      await t.tap(find.text('Buy'));
      await t.pumpAndSettle();
      expect(find.text('Your sack'), findsOneWidget);
      expect(find.text('Tomato x1'), findsOneWidget);
      final pct = find.textContaining(RegExp(gain ? r'^\+\d+%$' : r'^-\d+%$'));
      expect(pct, findsOneWidget);
      expect(
        find.byIcon(gain ? Icons.arrow_upward : Icons.arrow_downward),
        findsWidgets,
      );
    });
  }

  test('unknown cost: no average, so the sack shows quantity only', () async {
    SharedPreferences.setMockInitialValues({});
    final b = TradeBook(await SharedPreferences.getInstance());
    expect(b.avgCost('tomato'), isNull);
    b.bought('tomato', 2, 6000, 1);
    expect(b.avgCost('tomato'), 3000);
  });

  testWidgets('320x640: the first price row is visible without scrolling', (
    t,
  ) async {
    await boot(t, {'tut_done': false}, size: const Size(320, 640));
    await midday(t);
    expect(buyRow, findsWidgets);
    expect(t.getRect(buyRow.first).bottom, lessThan(560));
  });
}
