import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:soko_kuu/l10n.dart';
import 'package:soko_kuu/state/trade_book.dart';
import 'package:soko_kuu/ui/market_screen.dart';
import 'package:soko_kuu/ui/theme.dart';

void main() {
  test('average cost, profit, first sale and daily best', () async {
    SharedPreferences.setMockInitialValues({});
    final b = TradeBook(await SharedPreferences.getInstance());
    b.bought('tomato', 2, 200, 1);
    b.bought('tomato', 2, 240, 1); // avg 110
    final r = b.sold('tomato', 2, 180, 1)!; // paid 220, got 180
    expect(r.delta, -40);
    expect(r.avgCost, 110);
    expect(r.sameDay, isTrue);
    expect(r.firstSale, isTrue);
    final r2 = b.sold('tomato', 2, 300, 2)!;
    expect(r2.delta, 80);
    expect(r2.firstSale, isFalse);
    expect(b.sold('maize', 1, 50, 2), isNull);
    final d = b.days(2);
    expect((d.today, d.prev, d.best), (80, -40, 80));
  });

  testWidgets('result view: loss is a lesson, in en and sw', (t) async {
    for (final lang in ['en', 'sw']) {
      gLang = lang;
      final r = TradeResult(
        good: 'tomato',
        qty: 2,
        delta: -40,
        avgCost: 110,
        unitPrice: 90,
        sameDay: true,
        firstSale: true,
      );
      await t.pumpWidget(
        MaterialApp(
          theme: buildTheme(),
          home: Scaffold(body: SaleResultView(r, onDone: () {})),
        ),
      );
      await t.pumpAndSettle();
      expect(find.textContaining('-40 pts'), findsOneWidget);
      expect(
        find.textContaining(lang == 'en' ? 'first lesson' : 'Somo lako'),
        findsOneWidget,
      );
      expect(find.textContaining('Hasara'), findsOneWidget);
    }
    gLang = 'en';
  });
}
