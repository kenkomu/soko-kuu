import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:soko_kuu/l10n.dart';
import 'package:soko_kuu/main.dart';
import 'package:soko_kuu/state/providers.dart';
import 'package:soko_kuu/ui/credit_screen.dart';

void main() {
  creditHintTests();
  setUpAll(() => useSecureStorage = false);

  test('every tr() key has a Swahili entry with the same placeholders', () {
    final re = RegExp(r"tr\('((?:\\.|[^'\\])*)'");
    final ph = RegExp(r'\{(\w+)\}');
    for (final f
        in Directory('lib')
            .listSync(recursive: true)
            .whereType<File>()
            .where((f) => f.path.endsWith('.dart'))) {
      for (final m in re.allMatches(f.readAsStringSync())) {
        final key = m.group(1)!.replaceAll(r"\'", "'");
        expect(
          sw.containsKey(key),
          isTrue,
          reason: 'missing sw for: $key (${f.path})',
        );
        expect(
          ph.allMatches(sw[key]!).map((x) => x.group(1)).toSet(),
          ph.allMatches(key).map((x) => x.group(1)).toSet(),
          reason: key,
        );
      }
    }
    for (final code in errorText.keys) {
      expect(errorText[code]!['sw'], isNotEmpty);
    }
  });

  for (final lang in ['en', 'sw']) {
    testWidgets('all tabs: 200% text, tap targets, no overflow ($lang)', (
      t,
    ) async {
      SharedPreferences.setMockInitialValues({
        'age_ok': true,
        'entry': 'live',
        'lang': lang,
        'tut_done': false,
      });
      final prefs = await SharedPreferences.getInstance();
      final handle = t.ensureSemantics();
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
      for (final tab in ['Soko', 'Duka', 'Chama', 'Deni', 'Ripoti']) {
        await t.tap(find.text(tr(tab)).last);
        await t.pumpAndSettle();
        expect(t.takeException(), isNull, reason: 'overflow on $tab ($lang)');
        await expectLater(t, meetsGuideline(androidTapTargetGuideline));
        await expectLater(t, meetsGuideline(labeledTapTargetGuideline));
      }
      // Sheets: trade sheet at midday, then the credit sheet with a loan.
      await t.tap(find.text(tr('Soko')).last);
      await t.pumpAndSettle();
      await t.tap(find.text(tr('Go to midday')));
      await t.pumpAndSettle();
      await t.dragUntilVisible(
        find.text(goodName('tomato')),
        find.byType(ListView).first,
        const Offset(0, -100),
      );
      await t.ensureVisible(find.text(goodName('tomato')).first);
      await t.pumpAndSettle();
      await t.tap(find.text(goodName('tomato')).first);
      await t.pumpAndSettle();
      expect(t.takeException(), isNull, reason: 'trade sheet overflow ($lang)');
      await expectLater(t, meetsGuideline(androidTapTargetGuideline));
      await t.ensureVisible(find.text(tr('Buy')).last);
      await t.pumpAndSettle();
      await t.tap(find.text(tr('Buy')).last);
      await t.pumpAndSettle();
      await t.tap(find.text(tr('Deni')).last);
      await t.pumpAndSettle();
      await t.ensureVisible(find.text(tr('Take goods on credit')));
      await t.pumpAndSettle();
      await t.drag(find.byType(ListView).first, const Offset(0, -200));
      await t.pumpAndSettle();
      await t.tap(find.text(tr('Take goods on credit')), warnIfMissed: false);
      await t.pumpAndSettle();
      expect(
        t.takeException(),
        isNull,
        reason: 'credit sheet overflow ($lang)',
      );
      await t.ensureVisible(find.text(tr('Ask for credit')));
      await t.pumpAndSettle();
      await t.tap(find.text(tr('Ask for credit')));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull, reason: 'loan card overflow ($lang)');
      await expectLater(t, meetsGuideline(androidTapTargetGuideline));
      handle.dispose();
    });
  }
}

void creditHintTests() {
  test('credit shortfall hint explains the chama pot, en and sw', () {
    for (final lang in ['en', 'sw']) {
      gLang = lang;
      final none = creditShortfallHint(
        cost: 6000,
        owed: 6360,
        available: 4000,
        chamaCash: null,
      )!;
      final small = creditShortfallHint(
        cost: 7776,
        owed: 8000,
        available: 4000,
        chamaCash: 6000,
      )!;
      expect(none, contains('4,000'));
      expect(small, allOf(contains('6,000'), contains('7,776')));
      if (lang == 'sw') expect(small, contains('Mfuko wa pamoja'));
      expect(
        creditShortfallHint(
          cost: 3000,
          owed: 3180,
          available: 4000,
          chamaCash: 0,
        ),
        isNull,
      );
      expect(
        creditShortfallHint(
          cost: 5000,
          owed: 5300,
          available: 4000,
          chamaCash: 8000,
        ),
        isNull,
      );
    }
    gLang = 'en';
  });
}
