import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:soko_kuu/main.dart';
import 'package:soko_kuu/run/soko_run_engine.dart';
import 'package:soko_kuu/state/providers.dart';

/// Text drawn without a font family falls back to the engine default
/// (Roboto, an extra download on web). Every visible text must name one.
List<String> familyless(WidgetTester t) => [
  for (final e in find.byType(RichText).evaluate())
    if ((e.widget as RichText).text.style?.fontFamily == null)
      (e.widget as RichText).text.toPlainText(),
  for (final e in find.byType(EditableText).evaluate())
    if ((e.widget as EditableText).style.fontFamily == null) 'EditableText',
];

Future<void> go(WidgetTester t, Finder f) async {
  await t.ensureVisible(f);
  await t.pumpAndSettle();
  await t.tap(f);
  await t.pumpAndSettle();
}

Future<void> pumpApp(WidgetTester t, Map<String, Object> prefs) async {
  t.view.physicalSize = const Size(390, 844);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  SharedPreferences.setMockInitialValues(prefs);
  final p = await SharedPreferences.getInstance();
  await t.pumpWidget(
    ProviderScope(
      overrides: [prefsProvider.overrideWithValue(p)],
      child: const SokoKuuApp(),
    ),
  );
  await t.pumpAndSettle();
}

void main() {
  setUpAll(() => useSecureStorage = false);

  testWidgets('gate, choice and every Soko Run screen name a font family', (
    t,
  ) async {
    await pumpApp(t, {});
    expect(familyless(t), isEmpty, reason: 'gate');
    await go(t, find.text('I am 18 or older. Start'));
    expect(familyless(t), isEmpty, reason: 'entry');
    await go(t, find.text('Play Soko Run'));
    expect(familyless(t), isEmpty, reason: 'run start');
    await go(t, find.byTooltip('Settings'));
    expect(familyless(t), isEmpty, reason: 'run settings');
    await t.tapAt(const Offset(10, 10));
    await t.pumpAndSettle();
    await go(t, find.text('Play your first market'));
    expect(familyless(t), isEmpty, reason: 'run day 1');
    for (var d = 1; d <= kDays; d++) {
      await go(t, find.byKey(const Key('run-next')));
      expect(familyless(t), isEmpty, reason: 'run after day $d');
    }
    expect(find.text('The soko is closed.'), findsOneWidget);
  });

  testWidgets('live market tabs, trade sheet and settings name a family', (
    t,
  ) async {
    await pumpApp(t, {'age_ok': true, 'entry': 'live'});
    expect(familyless(t), isEmpty, reason: 'soko');
    await go(t, find.text('Go to midday'));
    await go(t, find.text('Tomato').first);
    expect(familyless(t), isEmpty, reason: 'trade sheet');
    await t.tapAt(const Offset(10, 10));
    await t.pumpAndSettle();
    for (final tab in ['Duka', 'Chama', 'Deni', 'Ripoti']) {
      await t.tap(find.text(tab).last);
      await t.pumpAndSettle();
      expect(familyless(t), isEmpty, reason: tab);
    }
    await go(t, find.byTooltip('Settings').first);
    expect(familyless(t), isEmpty, reason: 'settings');
  });
}
