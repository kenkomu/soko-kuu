import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:soko_kuu/run/soko_run_engine.dart';

/// "Follow the news": keep only goods the radio says will rise, buy as many of
/// them as cash and the 20 limit allow, sell the rest. Same as the prototype's
/// check script.
int followNews(int seed) {
  final g = RunGame(makeMarket(seed));
  for (var d = 1; d < kDays; d++) {
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
  for (var d = 1; d < kDays; d++) {
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
    expect(list, hasLength(5));
    expect(vectors['rules'], {
      'days': kDays,
      'maxHold': kMaxHold,
      'startCash': kStartCash,
      'startEach': kStartEach,
      'wrongRumour': 'no effect (eff=1)',
    });
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
    // The prototype's daily seeds for 2026-11-12 and 2026-11-13 (in vectors).
    expect(dailySeed(DateTime.utc(2026, 11, 12, 0, 0)), 1799991269);
    expect(dailySeed(DateTime.utc(2026, 11, 12, 23, 59)), 1799991269);
    expect(dailySeed(DateTime.utc(2026, 11, 13, 7)), 1783213650);
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
    // 5-day rules, from the prototype's makeMarket in node.
    final want = <int, (List<List<int>>, List<String>)>{
      4000000000: (
        [
          [52, 30, 41], [26, 32, 41], [46, 28, 42], [48, 31, 40], //
          [52, 14, 40],
        ],
        ['tomato:0.5:1', 'sukuma:2:0', 'tomato:0.5:0', 'maize:0.5:1'],
      ),
      0: (
        [
          [48, 28, 38], [36, 21, 28], [26, 31, 41], [47, 31, 43], //
          [100, 29, 38],
        ],
        ['all:0.7:1', 'tomato:0.5:1', 'maize:2:0', 'tomato:2:1'],
      ),
      4294967295: (
        [
          [53, 29, 41], [47, 32, 21], [27, 28, 38], [47, 28, 40], //
          [100, 30, 38],
        ],
        ['sukuma:0.5:1', 'tomato:0.5:1', 'sukuma:0.5:0', 'tomato:2:1'],
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

  test('the last day sells everything at its price with no fee', () {
    final g = RunGame(makeMarket(42));
    for (var d = 1; d < kDays; d++) {
      g.nextDay();
    }
    expect(g.day, kDays);
    expect(g.lastDay, isTrue);
    expect(g.canBuy('tomato'), isFalse);
    expect(g.canSell('tomato'), isFalse);
    expect(g.close(), g.lazyScore);
    expect(g.squares, hasLength(kDays - 1));
    expect(g.shown, kDays - 1);
  });

  test('a wrong rumour leaves the price at its normal level', () {
    for (var s = 1; s <= 300; s++) {
      final m = makeMarket(s);
      for (var d = 1; d < kDays; d++) {
        final r = m.rumourOn(d);
        if (r.truth) continue;
        for (final g in runGoods) {
          final p = m.on(d + 1)[g.id]!;
          expect(
            p,
            inInclusiveRange(jsRound(g.base * .92), jsRound(g.base * 1.08)),
            reason: 'seed $s day ${d + 1} ${g.id}',
          );
        }
      }
    }
  });

  test('titles', () {
    expect(runTitle(1399), 'Mgeni');
    expect(runTitle(1400), 'Mchuuzi');
    expect(runTitle(2199), 'Mchuuzi');
    expect(runTitle(2200), 'Mfanyabiashara');
    expect(runTitle(3399), 'Mfanyabiashara');
    expect(runTitle(3400), 'Tajiri wa Soko');
  });

  test(
    'follow the news beats doing nothing at least 1.85x over 2,000 seeds',
    () {
      final news = [for (var s = 1; s <= 2000; s++) followNews(s)];
      final lazy = [for (var s = 1; s <= 2000; s++) doNothing(s)];
      final mNews = median(news), mLazy = median(lazy);
      // ignore: avoid_print
      print(
        'Soko Run medians, 2,000 seeds: follow news $mNews, do nothing $mLazy',
      );
      expect(mNews, greaterThanOrEqualTo(1.85 * mLazy));
      // Same numbers as the prototype's 5-day rules over seeds 1..2000.
      expect((mNews, mLazy), (2407, 1240));
    },
  );
}
