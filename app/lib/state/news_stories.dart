import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../domain/models.dart';
import '../l10n.dart';
import 'trade_book.dart';

/// What each Radio Soko kind does to prices. Source: econ/src/events.rs,
/// `modifiers()` (price_up / price_down per kind), read 2026-11-11:
///   ukame    farm goods up           (tomato, maize, sukuma, onion)
///   fuel     every good up           (charcoal and fish most)
///   road     every good up           (and deliveries late)
///   festival every good up
///   harvest  farm goods down
///   glut     one good down           (named in the bulletin text)
/// A kind that is not here (for example 'calm') gets no tip.
/// `goods: null` means every good the market lists.
const newsEffects = <String, ({bool up, Set<String>? goods})>{
  'ukame': (up: true, goods: _farm),
  'fuel': (up: true, goods: null),
  'road': (up: true, goods: null),
  'festival': (up: true, goods: null),
  'harvest': (up: false, goods: _farm),
  'glut': (up: false, goods: <String>{}), // good comes from the text
};
const _farm = {'tomato', 'maize', 'sukuma', 'kale', 'onion'};

/// Good ids the bulletin text names (word match), in app id form.
Set<String> goodsNamed(String text) {
  final t = text.toLowerCase();
  const names = {
    'tomato': 'tomato',
    'maize': 'maize',
    'sukuma': 'sukuma',
    'kale': 'kale',
    'onion': 'onion',
    'fish': 'fish',
    'charcoal': 'charcoal',
  };
  return {
    for (final e in names.entries)
      if (RegExp('\\b${e.key}s?\\b').hasMatch(t)) e.value,
  };
}

/// The goods a bulletin is about, or null when we cannot say (no tip).
({bool up, Set<String> goods})? effectFor(NewsItem n, Set<String> listed) {
  final e = newsEffects[n.kind];
  if (e == null) return null;
  final named = goodsNamed(n.text).where(listed.contains).toSet();
  Set<String> g;
  if (named.isNotEmpty) {
    g = named;
  } else if (n.kind == 'glut') {
    return null; // a glut hits one good; without its name we do not guess
  } else if (e.goods == null) {
    g = listed;
  } else {
    g = listed.where(e.goods!.contains).toSet();
  }
  if (g.isEmpty) return null;
  return (up: e.up, goods: g);
}

/// Mean ask per good across merchants.
Map<String, int> priceByGood(List<PriceRow> rows) {
  final sum = <String, int>{}, n = <String, int>{};
  for (final r in rows) {
    sum[r.good] = (sum[r.good] ?? 0) + r.ask;
    n[r.good] = (n[r.good] ?? 0) + 1;
  }
  return {for (final g in sum.keys) g: sum[g]! ~/ n[g]!};
}

class Story {
  Story({
    required this.kind,
    required this.day,
    required this.up,
    required this.then,
    required this.demo,
  });
  final String kind;
  final int day;
  final bool up, demo;

  /// Price per good when the bulletin arrived.
  final Map<String, int> then;

  Map<String, dynamic> toJson() => {
    'k': kind,
    'd': day,
    'u': up,
    'm': demo,
    'g': then,
  };
  factory Story.fromJson(Map<String, dynamic> j) => Story(
    kind: j['k'] as String,
    day: j['d'] as int,
    up: j['u'] as bool,
    demo: j['m'] as bool? ?? false,
    then: (j['g'] as Map).map((k, v) => MapEntry('$k', (v as num).toInt())),
  );
}

/// What the screen shows for one story.
class StoryView {
  StoryView({
    required this.story,
    required this.good,
    this.now,
    this.avgPct,
    this.traded,
  });
  final Story story;

  /// The good the line is about.
  final String good;

  /// Null until a later day's prices have loaded.
  final int? now;
  final int? avgPct;
  final ({bool bought, int sales, int net})? traded;

  int? get then => story.then[good];
  int? get pct => (now == null || then == null || then == 0)
      ? null
      : ((now! - then!) * 100 / then!).round();

  /// -1 opposite to the hint, 0 about flat (within 2%), 1 as hinted.
  int? get verdict {
    final p = pct;
    if (p == null) return null;
    if (p.abs() < 2) return 0;
    return (p > 0) == story.up ? 1 : -1;
  }
}

class StoryBook {
  StoryBook(this.p);
  final SharedPreferences p;
  static const keep = 4;

  List<Story> _load() {
    try {
      final l = jsonDecode(p.getString('stories') ?? '[]') as List;
      return [for (final j in l) Story.fromJson(j as Map<String, dynamic>)];
    } catch (_) {
      return [];
    }
  }

  /// Records a snapshot for each new bulletin of today, then returns the
  /// views for the last few stories (newest first). Idempotent.
  List<StoryView> sync({
    required List<NewsItem> news,
    required List<PriceRow> prices,
    required int day,
    required bool demo,
  }) {
    final now = priceByGood(prices);
    if (now.isEmpty) return const [];
    var all = _load();
    var changed = false;
    for (final n in news) {
      if (n.day < day) continue; // older bulletins have no honest "then" price
      final e = effectFor(n, now.keys.toSet());
      if (e == null) continue;
      if (all.any(
        (s) => s.kind == n.kind && s.day == n.day && s.demo == demo,
      )) {
        continue;
      }
      all.add(
        Story(
          kind: n.kind,
          day: n.day,
          up: e.up,
          then: {for (final g in e.goods) g: now[g]!},
          demo: demo,
        ),
      );
      changed = true;
    }
    if (all.length > keep * 2) all = all.sublist(all.length - keep * 2);
    if (changed) {
      p.setString('stories', jsonEncode([for (final s in all) s.toJson()]));
    }
    final book = TradeBook(p);
    final mine = all.where((s) => s.demo == demo).toList().reversed.take(keep);
    return [for (final s in mine) _view(s, now, day, book)];
  }

  StoryView _view(Story s, Map<String, int> now, int day, TradeBook book) {
    final goods = s.then.keys.toList();
    if (day <= s.day) {
      return StoryView(story: s, good: goods.first);
    }
    // Prefer a good the player traded since, else the first listed.
    var good = goods.first;
    ({bool bought, int sales, int net})? traded;
    for (final g in goods) {
      final t = book.tradedSince(g, s.day);
      if (t.bought || t.sales > 0) {
        good = g;
        traded = t;
        break;
      }
    }
    int? avg;
    var sum = 0, n = 0;
    for (final g in goods) {
      final a = s.then[g]!, b = now[g];
      if (b == null || a == 0) continue;
      sum += ((b - a) * 100 / a).round();
      n++;
    }
    if (n > 1) avg = sum ~/ n;
    return StoryView(
      story: s,
      good: good,
      now: now[good],
      avgPct: avg,
      traded: traded,
    );
  }
}

String _signed(int n) =>
    '${n > 0
        ? '+'
        : n < 0
        ? '-'
        : ''}${n.abs()}';
String _num(int n) {
  final s = n.abs().toString();
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
    b.write(s[i]);
  }
  return '${n < 0 ? '-' : ''}$b';
}

const _label = {
  'ukame': ['Drought', 'Ukame'],
  'fuel': ['Fuel prices', 'Bei ya mafuta'],
  'road': ['Road cut', 'Barabara imekatika'],
  'festival': ['Festival', 'Sikukuu'],
  'harvest': ['Harvest', 'Mavuno'],
  'glut': ['Glut', 'Wingi wa mazao'],
};

String _lab(String kind, String lang) =>
    (_label[kind] ?? [kind, kind])[lang == 'sw' ? 1 : 0];

String _goodsList(Iterable<String> ids, String lang) =>
    ids.map((g) => goodName(g, lang)).join(', ');

/// "Drought: Tomato prices may rise soon." A hint, not a promise.
String tipText(Story s, String lang) {
  final ids = s.then.keys;
  final many = ids.length > 3;
  final farm = many && ids.every(_farm.contains);
  final names = _goodsList(ids, lang);
  final l = _lab(s.kind, lang);
  if (lang == 'sw') {
    final subj = farm
        ? 'bei za mazao ya shambani'
        : many
        ? 'bei'
        : 'bei za $names';
    return '$l: $subj ${s.up ? 'zinaweza kupanda' : 'zinaweza kushuka'} hivi karibuni.';
  }
  final subj = farm
      ? 'Farm produce prices'
      : many
      ? 'Prices'
      : '$names prices';
  return '$l: $subj may ${s.up ? 'rise' : 'fall'} soon.';
}

/// "Radio Soko said drought. Tomato was 4,018, now 4,900 (+22%)." plus a plain
/// verdict and, if the player traded that good, what they made or lost.
String outcomeText(StoryView v, String lang) {
  final sw = lang == 'sw';
  final g = goodName(v.good, lang);
  final then = _num(v.then!), now = _num(v.now!), p = v.pct!;
  final l = _lab(v.story.kind, lang);
  final b = StringBuffer(
    sw
        ? 'Radio Soko ilisema: $l. $g ilikuwa $then, sasa ni $now (${_signed(p)}%).'
        : 'Radio Soko said: $l. $g was $then, now $now (${_signed(p)}%).',
  );
  switch (v.verdict) {
    case 0:
      b.write(
        sw ? ' Bei haijabadilika sana bado.' : ' The price has barely moved.',
      );
    case -1:
      b.write(
        sw
            ? ' Bei imeenda upande tofauti na dokezo.'
            : ' It went the other way from the hint.',
      );
  }
  if (v.avgPct != null) {
    b.write(
      sw
          ? ' Kwa bidhaa zote zilizotajwa: wastani ${_signed(v.avgPct!)}%.'
          : ' Across all the goods mentioned: ${_signed(v.avgPct!)}% on average.',
    );
  }
  final t = v.traded;
  if (t != null) {
    if (t.sales > 0) {
      b.write(
        sw
            ? ' Uliuza $g tangu hapo: ${t.net >= 0 ? 'faida' : 'hasara'} ya pointi ${_num(t.net.abs())}.'
            : ' You sold $g since then: ${t.net >= 0 ? 'made' : 'lost'} ${_num(t.net.abs())} pts.',
      );
    } else if (t.bought) {
      b.write(
        sw ? ' Ulinunua $g tangu hapo.' : ' You bought some $g since then.',
      );
    }
  }
  return b.toString();
}
