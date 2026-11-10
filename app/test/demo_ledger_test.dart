import 'package:flutter_test/flutter_test.dart';
import 'package:soko_kuu/data/api_client.dart';
import 'package:soko_kuu/data/demo_ledger.dart';

SignedAct act(int n, Map<String, dynamic> a) => SignedAct(
  pubkey: 'k',
  nonce: n,
  expiresMs: DateTime.now().millisecondsSinceEpoch + 60000,
  action: a,
  actionJson: '',
  sig: 'x',
);

Future<List<Object>> script(int seed) async {
  final l = DemoLedger(seed: seed);
  var n = 0;
  await l.act(act(++n, {'type': 'advance'}));
  final p = (await l.prices()).rows;
  final r = p.first;
  await l.act(
    act(++n, {
      'type': 'buy',
      'merchant': r.merchant,
      'good': r.good,
      'qty': 3,
      'max_unit_price': r.ask,
    }),
  );
  for (var i = 0; i < 9; i++) {
    await l.act(act(++n, {'type': 'advance'}));
  }
  final s = await l.state('k');
  return [
    s.pts,
    s.day,
    s.stock.toString(),
    ((await l.prices()).rows).map((e) => e.ask).toList(),
  ];
}

void main() {
  test('daily mid moves stay within +-20%', () async {
    final l = DemoLedger(seed: 3);
    var prev = {
      for (final r in (await l.prices()).rows)
        '${r.merchant}|${r.good}': r.history.last,
    };
    for (var i = 1; i <= 60; i++) {
      await l.act(act(i, {'type': 'advance'}));
      if (i % 3 != 0) continue;
      for (final r in (await l.prices()).rows) {
        final p = prev['${r.merchant}|${r.good}']!;
        final h = r.history;
        final today = h.last, yday = h[h.length - 2];
        expect(today <= yday * 120 ~/ 100 && today >= yday * 80 ~/ 100, isTrue);
        prev['${r.merchant}|${r.good}'] = p;
      }
    }
  });

  test('trading is refused outside midday', () async {
    final l = DemoLedger();
    final r = ((await l.prices()).rows).first;
    expect(
      () => l.act(
        act(1, {
          'type': 'buy',
          'merchant': r.merchant,
          'good': r.good,
          'qty': 1,
          'max_unit_price': r.ask,
        }),
      ),
      throwsA(isA<Object>()),
    );
  });

  test('demo is deterministic per seed', () async {
    expect(await script(7), await script(7));
  });
  test('nonce must be last+1', () async {
    final l = DemoLedger();
    expect(() => l.act(act(5, {'type': 'advance'})), throwsA(isA<Object>()));
  });
  test('buy spends integer pts and cannot overspend', () async {
    final l = DemoLedger();
    final r = ((await l.prices()).rows).first;
    await l.act(act(1, {'type': 'advance'}));
    final res = await l.act(
      act(2, {
        'type': 'buy',
        'merchant': r.merchant,
        'good': r.good,
        'qty': 2,
        'max_unit_price': r.ask,
      }),
    );
    expect(res.state.pts, 20000 - r.ask * 2);
    expect(
      () => l.act(
        act(3, {
          'type': 'buy',
          'merchant': r.merchant,
          'good': r.good,
          'qty': 20,
          'max_unit_price': r.ask,
        }),
      ),
      throwsA(isA<Object>()),
    );
  });
}
