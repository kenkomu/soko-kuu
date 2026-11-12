/// Soko Run: a 5-day offline market run. Pure Dart: no Flutter, no network,
/// no chain. Points here are play points for this mode only and are never
/// sent anywhere.
///
/// [makeMarket] is a bit-exact port of makeMarket() in the approved HTML
/// prototype (mulberry32 RNG, FNV-1a daily seed, same order of RNG calls,
/// JavaScript Math.round). All 32-bit maths is masked by hand so the Dart VM,
/// Android and dart2js (where ints are doubles) give the same numbers.
library;

const int kMaxHold = 30;
const int kStartCash = 1000;
const int kStartEach = 2;
const int kDays = 5;

/// Day 1 of the Daily Soko: 2026-11-12, UTC.
final DateTime kDailyStart = DateTime.utc(2026, 11, 12);

class RunGood {
  const RunGood(this.id, this.base);
  final String id;
  final int base;
}

const runGoods = [
  RunGood('tomato', 50),
  RunGood('maize', 30),
  RunGood('sukuma', 40),
];

/// Multipliers for an all-goods event, in the prototype's order.
const _allMults = [0.8, 0.7, 1.2];

// TODO(sw): news lines stay English for now. Ask a native Kenyan speaker for
// a Swahili pass before translating; keep the same order (the RNG picks by
// index, so the order is part of the daily seed's output).
const runNews = <String, List<String>>{
  'tomato+': [
    'Drought in Kiambu. Few tomato lorries will reach the soko tomorrow.',
    'Wedding season in town. Hotels want tomatoes tomorrow.',
  ],
  'tomato-': [
    'Bumper harvest in Kirinyaga. Tomatoes everywhere tomorrow.',
    'Tomato lorries from Loitokitok arrive together tomorrow.',
  ],
  'maize+': [
    'Maize flour is short in the shops. Buyers will rush tomorrow.',
    'Drought in Kitale. Maize will be scarce tomorrow.',
  ],
  'maize-': [
    'Glut from Trans Nzoia. Maize sellers will cut prices tomorrow.',
    'The NCPB store is selling off maize tomorrow.',
  ],
  'sukuma+': [
    'Road wash-out at Salgaa. Sukuma trucks are stuck.',
    'Frost in Limuru hit the sukuma farms. Little will arrive tomorrow.',
  ],
  'sukuma-': [
    'Long rains in Limuru. Sukuma will flood the market tomorrow.',
    'Every farm in Kikuyu is cutting sukuma at once. Expect plenty tomorrow.',
  ],
  'all0.8': ['Fuel price down. Cheap transport means lower prices tomorrow.'],
  'all0.7': ['Matatu strike tomorrow. Few buyers will reach the soko.'],
  'all1.2': [
    'Fuel price up at the pump. Everything costs more to bring in tomorrow.',
  ],
};

const _m32 = 0xFFFFFFFF;

/// Math.imul on unsigned 32-bit values, returned unsigned. Splits into 16-bit
/// halves so no product exceeds 2^53 (safe on dart2js).
int imul32(int a, int b) {
  a &= _m32;
  b &= _m32;
  final aHi = (a >> 16) & 0xFFFF, aLo = a & 0xFFFF;
  final bHi = (b >> 16) & 0xFFFF, bLo = b & 0xFFFF;
  final mid = ((aHi * bLo + aLo * bHi) & 0xFFFF) * 0x10000;
  return (aLo * bLo + mid) & _m32;
}

/// mulberry32, as in the prototype. State is kept as an unsigned 32-bit int.
class Mulberry32 {
  Mulberry32(int seed) : _a = seed & _m32;
  int _a;

  double next() {
    _a = (_a + 0x6D2B79F5) & _m32;
    var t = imul32(_a ^ (_a >> 15), 1 | _a);
    t = ((t + imul32(t ^ (t >> 7), 61 | t)) & _m32) ^ t;
    return ((t ^ (t >> 14)) & _m32) / 4294967296.0;
  }
}

/// FNV-1a over UTF-16 code units, unsigned 32-bit (the prototype's hashStr).
int fnvHash(String s) {
  var h = 2166136261;
  for (final c in s.codeUnits) {
    h = imul32((h ^ c) & _m32, 16777619);
  }
  return h;
}

/// JavaScript Math.round: nearest integer, halves go towards +infinity.
int jsRound(double x) {
  final f = x.floorToDouble();
  return (x - f >= 0.5 ? f + 1 : f).toInt();
}

/// The market fee on one buy or one sell: 1% of the price, at least 1.
int runFee(int price) {
  final f = jsRound(price * 0.01);
  return f < 1 ? 1 : f;
}

/// Radio Soko's line about tomorrow.
class Rumour {
  const Rumour(this.target, this.mult, this.truth, this.text);

  /// A good id, or 'all'.
  final String target;
  final double mult;
  final bool truth;
  final String text;

  bool get isAll => target == 'all';
  bool get saysRise => mult > 1;
  bool touches(String id) => isAll || target == id;
}

class RunMarket {
  const RunMarket(this.seed, this.tutorial, this.prices, this.rumours);
  final int seed;
  final bool tutorial;

  /// prices[0] is day 1 ... prices[kDays - 1] is the last day.
  final List<Map<String, int>> prices;

  /// rumours[0] is heard on day 1 (about day 2) ... one per day but the last.
  final List<Rumour> rumours;

  Map<String, int> on(int day) => prices[day - 1];
  Rumour rumourOn(int day) => rumours[day - 1];
}

/// Prices for [kDays] days and one rumour per night from [seed]. A wrong
/// rumour has no effect on the price. Tutorial: the day-1 rumour is always
/// "tomato x2" and always true.
RunMarket makeMarket(int seed, {bool tutorial = false}) {
  final rng = Mulberry32(seed);
  double r() => rng.next();
  double u() => 0.92 + 0.16 * r();
  int price(int base, double e) {
    final p = jsRound(base * e * u());
    return p < 1 ? 1 : p;
  }

  final prices = <Map<String, int>>[
    {for (final g in runGoods) g.id: price(g.base, 1)},
  ];
  final rumours = <Rumour>[];
  String? last;
  for (var d = 1; d <= kDays - 1; d++) {
    String target;
    double mult;
    final forced = tutorial && d == 1;
    if (forced) {
      target = 'tomato';
      mult = 2;
    } else if (r() < 0.15) {
      target = 'all';
      mult = _allMults[(r() * 3).floor()];
    } else {
      final opts = [
        for (final g in runGoods)
          if (g.id != last) g.id,
      ];
      target = opts[(r() * opts.length).floor()];
      mult = r() < 0.5 ? 2 : 0.5;
    }
    if (target != 'all') last = target;
    final truth = forced ? true : r() < 0.75;
    final key = target == 'all' ? 'all$mult' : '$target${mult > 1 ? '+' : '-'}';
    final lines = runNews[key]!;
    final text = lines[(r() * lines.length).floor()];
    final eff = truth ? mult : 1.0;
    prices.add({
      for (final g in runGoods)
        g.id: price(g.base, target == 'all' || target == g.id ? eff : 1),
    });
    rumours.add(Rumour(target, mult, truth, text));
  }
  return RunMarket(seed, tutorial, prices, rumours);
}

String _ymd(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

/// The Daily Soko seed: the same for everyone on the same UTC date.
int dailySeed(DateTime now) => fnvHash('soko-daily-${_ymd(now.toUtc())}');

/// Daily Soko number: 1 on 2026-11-12 (UTC), 2 the next day, and so on.
int dailyNumber(DateTime now) =>
    (now.toUtc().difference(kDailyStart).inMilliseconds / 86400000).floor() + 1;

/// Title for a final score. The titles are Swahili in both languages.
String runTitle(int score) => score >= 3400
    ? 'Tajiri wa Soko'
    : score >= 2200
    ? 'Mfanyabiashara'
    : score >= 1400
    ? 'Mchuuzi'
    : 'Mgeni';

enum RunMode { first, practice, daily }

/// All sales of one good on one day, for "best move" and "worst move".
class RunSale {
  RunSale(this.day, this.id, this.price, this.closing);
  final int day;
  final String id;
  final int price;
  final bool closing;
  int qty = 0;
  double profit = 0;
}

/// What changed overnight, for the reveal banner.
class RunReveal {
  const RunReveal(this.rumour, this.old, this.before, this.after);
  final Rumour rumour;
  final Map<String, int> old;

  /// Total worth (cash + sack) at yesterday's and today's prices.
  final int before, after;
}

/// Night squares for the end screen and the share text.
enum RunSquare { up, down, flat }

/// One run. Mirrors the prototype's state and rules exactly.
class RunGame {
  RunGame(this.market, {this.mode = RunMode.practice, this.dailyNo = 0})
    : hold = {for (final g in runGoods) g.id: kStartEach},
      cost = {
        for (final g in runGoods)
          g.id: (kStartEach * market.on(1)[g.id]!).toDouble(),
      },
      hint = mode == RunMode.first ? 1 : 0;

  final RunMarket market;
  final RunMode mode;
  final int dailyNo;

  int day = 1;
  int cash = kStartCash;
  final Map<String, int> hold;

  /// What the player paid for what they hold (average cost basis).
  final Map<String, double> cost;
  final Map<String, RunSale> sales = {};
  final List<RunSquare> squares = [];
  RunReveal? reveal;
  int rightCount = 0, shown = 0;

  /// 0 none, 1 the day-1 tutorial hint, 2 the day-2 hint.
  int hint;
  bool closed = false;

  Map<String, int> get prices => market.on(day);
  bool get lastDay => day >= kDays;
  Rumour? get rumour => lastDay ? null : market.rumourOn(day);

  int sackAt(int d) =>
      runGoods.fold(0, (a, g) => a + hold[g.id]! * market.on(d)[g.id]!);
  int worthAt(int d) => cash + sackAt(d);
  int get sack => sackAt(day);
  int get total => worthAt(day);

  int buyCost(String id) => prices[id]! + runFee(prices[id]!);
  int sellNet(String id) => prices[id]! - runFee(prices[id]!);

  bool canBuy(String id) =>
      !closed && !lastDay && cash >= buyCost(id) && hold[id]! < kMaxHold;
  bool canSell(String id) => !closed && !lastDay && hold[id]! > 0;

  bool buy(String id) {
    if (!canBuy(id)) return false;
    final c = buyCost(id);
    cash -= c;
    hold[id] = hold[id]! + 1;
    cost[id] = cost[id]! + c;
    return true;
  }

  bool sell(String id) => canSell(id) && _sell(id, closing: false);

  bool _sell(String id, {required bool closing}) {
    final h = hold[id]!;
    if (h <= 0) return false;
    final p = prices[id]!;
    final net = closing ? p : p - runFee(p);
    final avg = cost[id]! / h;
    cash += net;
    hold[id] = h - 1;
    cost[id] = cost[id]! - avg;
    final m = sales.putIfAbsent('$day|$id', () => RunSale(day, id, p, closing));
    m.qty++;
    m.profit += net - avg;
    return true;
  }

  /// Gain or loss on what was paid, in whole percent; null if none held.
  int? gainPct(String id) {
    final h = hold[id]!;
    if (h <= 0) return null;
    final avg = cost[id]! / h;
    return jsRound((prices[id]! - avg) / avg * 100);
  }

  /// Change since yesterday in whole percent; null on day 1.
  int? changePct(String id) {
    if (day <= 1) return null;
    final was = market.on(day - 1)[id]!, now = prices[id]!;
    return jsRound((now - was) / was * 100);
  }

  /// Moves to the next day and returns what the radio got right or wrong.
  RunReveal nextDay() {
    assert(!lastDay && !closed);
    final d = day, ru = market.rumourOn(d);
    final before = worthAt(d), after = worthAt(d + 1);
    final ch = before == 0 ? 0.0 : (after - before) / before;
    squares.add(
      ch > 0.01
          ? RunSquare.up
          : ch < -0.01
          ? RunSquare.down
          : RunSquare.flat,
    );
    if (ru.truth) rightCount++;
    shown++;
    final old = Map<String, int>.of(market.on(d));
    day++;
    final rv = RunReveal(ru, old, before, after);
    reveal = rv;
    if (hint == 1) {
      hint = mode == RunMode.first ? 2 : 0;
    } else if (hint == 2) {
      hint = 0;
    }
    return rv;
  }

  /// Last day: sells everything at today's price with no fee. Returns the score.
  int close() {
    if (!closed) {
      for (final g in runGoods) {
        while (hold[g.id]! > 0) {
          _sell(g.id, closing: true);
        }
      }
      closed = true;
    }
    return cash;
  }

  int get score => cash;

  /// What a player who never traded ends with.
  int get lazyScore => runGoods.fold(
    kStartCash,
    (a, g) => a + kStartEach * market.on(kDays)[g.id]!,
  );

  RunSale? get bestMove {
    RunSale? b;
    for (final s in sales.values) {
      if (b == null || s.profit > b.profit) b = s;
    }
    return b != null && b.profit > 0 ? b : null;
  }

  RunSale? get worstMove {
    RunSale? w;
    for (final s in sales.values) {
      if (w == null || s.profit < w.profit) w = s;
    }
    return w != null && w.profit < 0 ? w : null;
  }
}
