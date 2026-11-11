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
    expect(find.textContaining('Bei za leo'), findsOneWidget);
    expect(find.textContaining('20,000 pts'), findsOneWidget);
    expect(find.textContaining('cashed out'), findsOneWidget);
    expect(find.text('Make your first profit'), findsOneWidget);
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
    SharedPreferences.setMockInitialValues({'age_ok': true});
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
}

bool noOverflow(WidgetTester t) => t.takeException() == null;
