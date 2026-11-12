import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:soko_kuu/main.dart';
import 'package:soko_kuu/state/providers.dart';
import 'package:soko_kuu/ui/kit/wordmark.dart';
import 'package:soko_kuu/ui/theme.dart';

Future<void> boot(WidgetTester t, Map<String, Object> prefs) async {
  t.view.physicalSize = const Size(320, 640);
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

  testWidgets('wordmark reads "Soko Kuu" and hides the tomato image', (
    t,
  ) async {
    final handle = t.ensureSemantics();
    await t.pumpWidget(
      MaterialApp(
        theme: buildTheme(),
        home: const Scaffold(body: Center(child: SokoWordmark())),
      ),
    );
    await t.pumpAndSettle();
    expect(find.bySemanticsLabel('Soko Kuu'), findsOneWidget);
    final img = t.widget<Image>(find.byType(Image));
    expect(img.excludeFromSemantics, isTrue);
    expect((img.image as AssetImage).assetName, 'assets/brand/tomato_mark.png');
    final text = t.widget<RichText>(
      find.descendant(
        of: find.byType(SokoWordmark),
        matching: find.byType(RichText),
      ),
    );
    expect(text.text.style?.color, SokoWordmark.lightInk);
    handle.dispose();
  });

  testWidgets('wordmark is cream on dark', (t) async {
    await t.pumpWidget(
      MaterialApp(
        theme: buildDarkTheme(),
        home: const Scaffold(body: SokoWordmark()),
      ),
    );
    final text = t.widget<RichText>(
      find.descendant(
        of: find.byType(SokoWordmark),
        matching: find.byType(RichText),
      ),
    );
    expect(text.text.style?.color, SokoWordmark.darkInk);
  });

  testWidgets('gate, entry and Soko Run start show it at 320x640', (t) async {
    final handle = t.ensureSemantics();
    await boot(t, {});
    expect(find.bySemanticsLabel('Soko Kuu'), findsOneWidget);
    expect(t.takeException(), isNull);
    await t.ensureVisible(find.text('I am 18 or older. Start'));
    await t.pumpAndSettle();
    await t.tap(find.text('I am 18 or older. Start'));
    await t.pumpAndSettle();
    expect(find.bySemanticsLabel('Soko Kuu'), findsOneWidget);
    expect(t.takeException(), isNull);
    await t.ensureVisible(find.text('Play Soko Run'));
    await t.pumpAndSettle();
    await t.tap(find.text('Play Soko Run'));
    await t.pumpAndSettle();
    expect(find.bySemanticsLabel('Soko Kuu'), findsOneWidget);
    expect(find.text('Soko Run'), findsOneWidget);
    expect(t.takeException(), isNull);
    handle.dispose();
  });
}
