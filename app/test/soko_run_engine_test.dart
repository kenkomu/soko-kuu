import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:soko_kuu/run/soko_run_engine.dart';

/// "Follow the news": keep only goods the radio says will rise, buy as many of
/// them as cash and the 20 limit allow, sell the rest. Same as the prototype's
/// check script.
int followNews(int seed) {
  final g = RunGame(makeMarket(seed));
  for (var d = 1; d <= 9; d++) {
    final r = g.rumour!;
    for (final x in runGoods) {
      if (!(r.saysRise && r.touches(x.id))) {
        while (g.sell(x.id)) {}
      }
    }
    if (r.saysRise) {
      for (final x in runGoods) {
        if (r.touches(x.id)) {
          while (g.buy(x.id)) {}
        }
      }
    }
    g.nextDay();
  }
  return g.close();
}

int doNothing(int seed) {
  final g = RunGame(makeMarket(seed));
  for (var d = 1; d <= 9; d++) {
    g.nextDay();
  }
  return g.close();
}

int median(List<int> a) => (List.of(a)..sort())[a.length >> 1];

void main() {
  final vectors = jsonDecode(
    File('test/fixtures/soko_run_vectors.json').readAsStringSync(),
  ) as Map<String, dynamic>;

  test('every price and rumour in the prototype vectors matches exactly', () {
    final list = vectors['vectors'] as List;
    expect(list, hasLength(4));
    for (final v in list.cast<Map<String, dynamic>>()) {
      final m = makeMarket(v['seed'] as int, tutorial: v['tutorial'] as bool);
      final prices = (v['prices'] as List).cast<Map<String, dynamic>>();
      expect(m.prices, hasLength(prices.length));
      for (var i = 0; i < prices.length; i++) {
        for (final g in runGoods) {
          expect(
            m.prices[i][g.id],
            prices[i][g.id],
            reason: 'seed ${v['seed']} day ${i + 1} ${g.id}',
          );
        }
      }
      final rumours = (v['rumours'] as List).cast<Map<String, dynamic>>();
      expect(m.rumours, hasLength(rumours.length));
      for (var i = 0; i < rumours.length; i++) {
        final want = rumours[i], got = m.rumours[i];
        final why = 'seed ${v['seed']} night ${i + 1}';
        expect(got.target, want['target'], reason: why);
        expect(got.mult, (want['mult'] as num).toDouble(), reason: why);
        expect(got.truth, want['truth'], reason: why);
        expect(got.text, want['text'], reason: why);
      }
    }
  });

  test('daily seed is FNV-1a of the UTC date, like the prototype', () {
    expect(
      dailySeed(DateTime.utc(2026, 11, 12, 0, 0)),
      vectors['dailySeed_2026_11_12'],
    );
    expect(
      dailySeed(DateTime.utc(2026, 11, 12, 23, 59)),
      vectors['dailySeed_2026_11_12'],
    );
    // Values from the prototype's hashStr in node.
    expect(fnvHash('soko-daily-2026-11-13'), 1783213650);
    expect(fnvHash('soko-daily-2026-12-31'), 2213007553);
    expect(fnvHash('soko-daily-2027-02-28'), 3834632491);
    expect(dailyNumber(DateTime.utc(2026, 11, 12, 1)), 1);
    expect(dailyNumber(DateTime.utc(2026, 11, 13, 23, 59)), 2);
    expect(dailyNumber(DateTime.utc(2026, 12, 12)), 31);
  });

  test('large and edge seeds match the prototype (unsigned 32-bit maths)', () {
    final rng = Mulberry32(4000000000);
    expect(rng.next(), 0.6919068221468478);
    expect(rng.next(), 0.5511944761965424);
    expect(rng.next(), 0.666226316941902);
    final want = <int, (List<List<int>>, List<String>)>{
      4000000000: (
        [
          [52, 30, 41], [26, 32, 41], [46, 28, 21], [97, 31, 40], //
          [52, 14, 40], [39, 23, 31], [50, 30, 82], [93, 31, 40],
          [43, 23, 30], [47, 58, 41],
        ],
        [
          'tomato:0.5:1', 'sukuma:2:0', 'tomato:0.5:0', 'maize:0.5:1', //
          'all:0.8:1', 'sukuma:2:1', 'tomato:2:1', 'all:0.8:1', 'maize:0.5:0',
        ],
      ),
      0: (
        [
          [48, 28, 38], [36, 21, 28], [26, 31, 41], [47, 16, 43], //
          [100, 29, 38], [49, 63, 40], [50, 29, 79], [50, 60, 37],
          [39, 23, 35], [26, 32, 42],
        ],
        [
          'all:0.7:1', 'tomato:0.5:1', 'maize:2:0', 'tomato:2:1', //
          'maize:2:1', 'sukuma:0.5:0', 'maize:2:1', 'all:0.8:1',
          'tomato:0.5:1',
        ],
      ),
      4294967295: (
        [
          [53, 29, 41], [47, 32, 21], [27, 28, 38], [47, 28, 80], //
          [100, 30, 38], [53, 31, 18], [24, 32, 42], [53, 29, 81],
          [46, 15, 40], [48, 30, 86],
        ],
        [
          'sukuma:0.5:1', 'tomato:0.5:1', 'sukuma:0.5:0', 'tomato:2:1', //
          'sukuma:0.5:1', 'tomato:0.5:1', 'sukuma:2:1', 'maize:2:0',
          'sukuma:2:1',
        ],
      ),
    };
    String mult(double m) => m == m.roundToDouble() ? '${m.round()}' : '$m';
    want.forEach((seed, w) {
      final m = makeMarket(seed);
      expect(
        [
          for (final p in m.prices) [p['tomato'], p['maize'], p['sukuma']],
        ],
        w.$1,
        reason: 'prices seed $seed',
      );
      expect(
        [
          for (final r in m.rumours)
            '${r.target}:${mult(r.mult)}:${r.truth ? 1 : 0}',
        ],
        w.$2,
        reason: 'rumours seed $seed',
      );
    });
  });

  test('rules: fee, no repeat target, tutorial day 1, hold limit', () {
    expect(runFee(30), 1);
    expect(runFee(49), 1);
    expect(runFee(50), 1); // Math.round(0.5) = 1
    expect(runFee(150), 2);
    expect(runFee(249), 2);
    expect(runFee(250), 3);
    for (var s = 1; s <= 300; s++) {
      final m = makeMarket(s);
      String? last;
      for (final r in m.rumours) {
        if (!r.isAll) {
          expect(r.target, isNot(last), reason: 'seed $s');
          last = r.target;
        }
      }
      final t = makeMarket(s, tutorial: true).rumours.first;
      expect((t.target, t.mult, t.truth), ('tomato', 2.0, true));
    }
    final g = RunGame(makeMarket(7));
    while (g.buy('maize')) {}
    expect(g.hold['maize'], kMaxHold);
    expect(g.canBuy('maize'), isFalse);
  });

  test('day 10 sells everything at the day-10 price with no fee', () {
    final g = RunGame(makeMarket(42));
    for (var d = 1; d <= 9; d++) {
      g.nextDay();
    }
    expect(g.lastDay, isTrue);
    expect(g.canBuy('tomato'), isFalse);
    expect(g.canSell('tomato'), isFalse);
    expect(g.close(), g.lazyScore);
    expect(g.squares, hasLength(9));
    expect(g.shown, 9);
  });

  test('follow the news beats doing nothing at least 2x over 2,000 seeds', () {
    final news = [for (var s = 1; s <= 2000; s++) followNews(s)];
    final lazy = [for (var s = 1; s <= 2000; s++) doNothing(s)];
    final mNews = median(news), mLazy = median(lazy);
    // ignore: avoid_print
    print(
      'Soko Run medians, 2,000 seeds: follow news $mNews, do nothing $mLazy',
    );
    expect(mNews, greaterThanOrEqualTo(2 * mLazy));
    // Same numbers as the prototype's check script over seeds 1..2000.
    expect((mNews, mLazy), (3051, 1333));
  });
}
