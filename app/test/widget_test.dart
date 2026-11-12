import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:soko_kuu/main.dart';
import 'package:soko_kuu/state/providers.dart';

void main() {
  setUpAll(() => useSecureStorage = false);
  testWidgets('18+ gate then demo market renders and a buy works', (t) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await t.pumpWidget(
      ProviderScope(
        overrides: [prefsProvider.overrideWithValue(prefs)],
        child: const SokoKuuApp(),
      ),
    );
    expect(find.textContaining('18 or older'), findsOneWidget);
    await t.tap(find.text('I am 18 or older. Start'));
    await t.pumpAndSettle();
    // Entry choice: Soko Run first, the live market second.
    expect(find.text('Play Soko Run'), findsOneWidget);
    await t.tap(find.text('Live market on NEAR'));
    await t.pumpAndSettle();
    expect(find.textContaining('Bei za leo'), findsOneWidget);
    expect(find.textContaining('20,000 pts'), findsOneWidget);
    expect(find.textContaining('cashed out'), findsOneWidget);
    expect(find.text('Your first day'), findsOneWidget);
    expect(find.text('Make your first profit'), findsNothing);
    await t.tap(find.text('Go to midday'));
    await t.pumpAndSettle();
    await t.ensureVisible(find.text('Tomato').first);
    await t.pumpAndSettle();
    await t.tap(find.text('Tomato').first);
    await t.pumpAndSettle();
    await t.tap(find.text('Buy'));
    await t.pumpAndSettle();
    expect(find.textContaining('20,000 pts'), findsNothing);
  });

  testWidgets('layout survives 200% text scale', (t) async {
    SharedPreferences.setMockInitialValues({'age_ok': true, 'entry': 'live'});
    final prefs = await SharedPreferences.getInstance();
    t.view.physicalSize = const Size(360, 740);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(
      ProviderScope(
        overrides: [prefsProvider.overrideWithValue(prefs)],
        child: MediaQuery(
          data: const MediaQueryData(
            size: Size(360, 740),
            textScaler: TextScaler.linear(2.0),
          ),
          child: const SokoKuuApp(),
        ),
      ),
    );
    await t.pumpAndSettle();
    expect(noOverflow(t), isTrue);
  });

  testWidgets(
    'one info card at a time: tip, then goal, then Radio Soko (320x640)',
    (t) async {
      t.view.physicalSize = const Size(320, 640);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      SharedPreferences.setMockInitialValues({
        'age_ok': true,
        'entry': 'live',
        'stories':
            '[{"k":"ukame","d":1,"u":true,"m":true,"g":{"tomato":3000}}]',
      });
      final prefs = await SharedPreferences.getInstance();
      await t.pumpWidget(
        ProviderScope(
          overrides: [prefsProvider.overrideWithValue(prefs)],
          child: const SokoKuuApp(),
        ),
      );
      await t.pumpAndSettle();
      await t.tap(find.text('Go to midday'));
      await t.pumpAndSettle();
      final tip = find.text('Your first day');
      final goal = find.text('Make your first profit');
      final radio = find.textContaining(
        'Drought: Tomato prices may rise soon.',
      );
      List<int> shown() =>
          [tip, goal, radio].map((f) => f.evaluate().length).toList();
      void tomatoVisible() {
        expect(find.text('Tomato'), findsWidgets);
        expect(t.getCenter(find.text('Tomato').first).dy, lessThan(560));
      }

      expect(shown(), [1, 0, 0]);
      tomatoVisible();
      await t.tap(find.text('Skip'));
      await t.pumpAndSettle();
      expect(shown(), [0, 1, 0]);
      tomatoVisible();
      await t.tap(find.byTooltip('Hide goal'));
      await t.pumpAndSettle();
      expect(shown(), [0, 0, 1]);
      expect(
        find.textContaining('Drought: Tomato prices may rise soon.'),
        findsOneWidget,
      );
      tomatoVisible();
    },
  );
}

bool noOverflow(WidgetTester t) => t.takeException() == null;
