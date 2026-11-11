import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:soko_kuu/domain/models.dart';
import 'package:soko_kuu/state/news_stories.dart';
import 'package:soko_kuu/state/trade_book.dart';

PriceRow row(String m, String g, int ask) => PriceRow(
  merchant: m,
  good: g,
  ask: ask,
  bid: ask - 100,
  stock: 10,
  why: const [],
  history: [ask],
);
NewsItem news(String kind, String text, int day) =>
    NewsItem(text: text, day: day, kind: kind);

const listed = {'tomato', 'maize', 'sukuma', 'onion', 'fish', 'charcoal'};

void main() {
  test('kind to effect table follows econ events.rs', () {
    final u = effectFor(
      news('ukame', 'Ukame: the rains have failed.', 3),
      listed,
    )!;
    expect(u.up, isTrue);
    expect(u.goods, {'tomato', 'maize', 'sukuma', 'onion'});
    final h = effectFor(news('harvest', 'Harvest is in.', 3), listed)!;
    expect(h.up, isFalse);
    expect(h.goods.contains('fish'), isFalse);
    expect(
      effectFor(news('festival', 'Festival this week', 3), listed)!.goods,
      listed,
    );
    expect(
      effectFor(news('road', 'The main road is cut', 3), listed)!.up,
      isTrue,
    );
    final f = effectFor(
      news('fuel', 'Fuel prices are up. charcoal and fish most.', 3),
      listed,
    )!;
    expect(f.goods, {'fish', 'charcoal'});
    final g = effectFor(
      news('glut', 'A glut of onion floods the market.', 3),
      listed,
    )!;
    expect(g.up, isFalse);
    expect(g.goods, {'onion'});
  });

  test('no tip when the effect is unclear', () {
    expect(
      effectFor(news('glut', 'A glut of something floods', 3), listed),
      isNull,
    );
    expect(effectFor(news('calm', 'Soko is calm today.', 3), listed), isNull);
    expect(effectFor(news('mystery', 'x', 3), listed), isNull);
  });

  test(
    'story: snapshot, outcome from real prices, player trade added',
    () async {
      SharedPreferences.setMockInitialValues({});
      final p = await SharedPreferences.getInstance();
      final sb = StoryBook(p);
      final n = [news('ukame', 'Ukame in Kiambu: tomato supply is short.', 5)];
      var v = sb.sync(
        news: n,
        prices: [
          row('a', 'tomato', 4000),
          row('b', 'tomato', 4036),
          row('a', 'maize', 2000),
        ],
        day: 5,
        demo: true,
      );
      expect(v.length, 1);
      expect(v.first.now, isNull);
      expect(
        tipText(v.first.story, 'en'),
        'Drought: Tomato prices may rise soon.',
      );
      expect(
        tipText(v.first.story, 'sw'),
        contains('bei za Nyanya zinaweza kupanda'),
      );
      expect(v.first.story.then['tomato'], 4018);

      final tb = TradeBook(p);
      tb.bought('tomato', 1, 4018, 5);
      tb.sold('tomato', 1, 4500, 6);
      v = sb.sync(
        news: n,
        prices: [row('a', 'tomato', 4900), row('b', 'tomato', 4900)],
        day: 6,
        demo: true,
      );
      expect(v.length, 1, reason: 'no duplicate story');
      expect(v.first.pct, 22);
      expect(v.first.verdict, 1);
      final t = outcomeText(v.first, 'en');
      expect(t, contains('Tomato was 4,018, now 4,900 (+22%)'));
      expect(t, contains('made 482 pts'));
      expect(outcomeText(v.first, 'sw'), contains('faida ya pointi 482'));

      // a different mode does not see it
      expect(
        sb
            .sync(news: n, prices: [row('a', 'tomato', 1)], day: 6, demo: false)
            .where((x) => x.story.demo),
        isEmpty,
      );
    },
  );

  test(
    'price went the other way: said plainly; old bulletins skipped',
    () async {
      SharedPreferences.setMockInitialValues({});
      final sb = StoryBook(await SharedPreferences.getInstance());
      final n = [
        news('harvest', 'Harvest is in.', 2),
        news('ukame', 'Ukame', 1),
      ];
      sb.sync(
        news: n,
        prices: [row('a', 'tomato', 1000), row('a', 'maize', 1000)],
        day: 2,
        demo: false,
      );
      final v = sb.sync(
        news: n,
        prices: [row('a', 'tomato', 1200), row('a', 'maize', 1100)],
        day: 3,
        demo: false,
      );
      expect(v.length, 1);
      expect(v.first.verdict, -1);
      expect(outcomeText(v.first, 'en'), contains('went the other way'));
    },
  );

  test('goal: first profit flag and trade log', () async {
    SharedPreferences.setMockInitialValues({});
    final b = TradeBook(await SharedPreferences.getInstance());
    expect(b.hadProfit, isFalse);
    b.bought('maize', 1, 100, 1);
    b.sold('maize', 1, 90, 1);
    expect(b.hadProfit, isFalse);
    b.bought('maize', 1, 100, 2);
    b.sold('maize', 1, 150, 2);
    expect(b.hadProfit, isTrue);
    expect(b.tradedSince('maize', 2).net, 50);
  });
}
