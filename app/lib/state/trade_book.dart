import 'package:shared_preferences/shared_preferences.dart';

/// What one sale earned, worked out on the device from what the player paid.
class TradeResult {
  TradeResult({
    required this.good,
    required this.qty,
    required this.delta,
    required this.avgCost,
    required this.unitPrice,
    required this.sameDay,
    required this.firstSale,
  });
  final String good;
  final int qty, delta, avgCost, unitPrice;

  /// Sold on the same day it was bought (the trader spread explains the gap).
  final bool sameDay;
  final bool firstSale;
  bool get isLoss => delta < 0;
}

/// Average cost per good and daily profit, kept in prefs. Display only: the
/// contract stays the referee, nothing here is sent anywhere.
class TradeBook {
  TradeBook(this.p);
  final SharedPreferences p;

  void bought(String good, int qty, int spent, int day) {
    if (qty <= 0 || spent < 0) return;
    final cur = _basis(good);
    final q = cur.$1 + qty, c = cur.$2 + spent;
    p.setString('cb_$good', '$q:$c:$day');
    _log(day, good, 'b', 0);
  }

  /// Short log of recent trades ('day|good|b/s|delta'), newest last, for the
  /// Radio Soko stories. Display only.
  void _log(int day, String good, String type, int delta) {
    final l = p.getStringList('tlog') ?? <String>[];
    l.add('$day|$good|$type|$delta');
    p.setStringList('tlog', l.length > 40 ? l.sublist(l.length - 40) : l);
  }

  /// What the player did with [good] on or after [fromDay]: whether they
  /// bought, how many sales, and the points made or lost on those sales.
  ({bool bought, int sales, int net}) tradedSince(String good, int fromDay) {
    var bought = false, sales = 0, net = 0;
    for (final e in p.getStringList('tlog') ?? const <String>[]) {
      final f = e.split('|');
      if (f.length != 4 || f[1] != good) continue;
      if ((int.tryParse(f[0]) ?? -1) < fromDay) continue;
      if (f[2] == 'b') {
        bought = true;
      } else {
        sales++;
        net += int.tryParse(f[3]) ?? 0;
      }
    }
    return (bought: bought, sales: sales, net: net);
  }

  /// Average points paid per unit of what the player still holds, or null
  /// when unknown (never bought through this app, or data cleared).
  int? avgCost(String good) {
    final b = _basis(good);
    return b.$1 > 0 && b.$2 > 0 ? b.$2 ~/ b.$1 : null;
  }

  bool get hadProfit => p.getBool('profit_seen') ?? false;

  (int, int, int) _basis(String good) {
    final s = (p.getString('cb_$good') ?? '').split(':');
    if (s.length != 3) return (0, 0, 0);
    return (
      int.tryParse(s[0]) ?? 0,
      int.tryParse(s[1]) ?? 0,
      int.tryParse(s[2]) ?? 0,
    );
  }

  /// Null when the cost of this stock is unknown (for example, app data was cleared).
  TradeResult? sold(String good, int qty, int proceeds, int day) {
    final b = _basis(good);
    if (qty <= 0 || b.$1 <= 0) return null;
    final avg = b.$2 ~/ b.$1;
    final left = b.$1 > qty ? b.$1 - qty : 0;
    p.setString('cb_$good', '$left:${avg * left}:${b.$3}');
    final delta = proceeds - avg * qty;
    final first = !(p.getBool('first_sale_seen') ?? false);
    p.setBool('first_sale_seen', true);
    _addDay(day, delta);
    _log(day, good, 's', delta);
    if (delta > 0) p.setBool('profit_seen', true);
    return TradeResult(
      good: good,
      qty: qty,
      delta: delta,
      avgCost: avg,
      unitPrice: proceeds ~/ qty,
      sameDay: b.$3 == day,
      firstSale: first,
    );
  }

  void _addDay(int day, int delta) {
    final d = p.getInt('pl_day') ?? day;
    var today = p.getInt('pl_today') ?? 0;
    if (d != day) {
      p.setInt('pl_prev', today);
      p.setBool('pl_has_prev', true);
      today = 0;
    }
    today += delta;
    p.setInt('pl_day', day);
    p.setInt('pl_today', today);
    if (today > (p.getInt('pl_best') ?? 0)) p.setInt('pl_best', today);
  }

  /// Profit today, yesterday (null if none yet) and the best day so far.
  ({int today, int? prev, int best}) days(int day) {
    final d = p.getInt('pl_day');
    final today = d == day ? (p.getInt('pl_today') ?? 0) : 0;
    int? prev;
    if (d == day) {
      prev = (p.getBool('pl_has_prev') ?? false) ? p.getInt('pl_prev') : null;
    } else if (d != null) {
      prev = p.getInt('pl_today');
    }
    return (today: today, prev: prev, best: p.getInt('pl_best') ?? 0);
  }
}
