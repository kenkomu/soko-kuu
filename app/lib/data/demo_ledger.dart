import '../domain/models.dart';
import 'api_client.dart';

const goodsList = ['tomato', 'kale', 'maize', 'onion'];
const _base = {'tomato': 3000, 'kale': 1800, 'maize': 2400, 'onion': 2600};
const _perishable = {'tomato', 'kale'};
const _merchants = {
  'njeri': ['tomato', 'kale'],
  'baraka': ['maize', 'onion'],
  'wanjiru': ['tomato', 'maize'],
};
const _marginPct = 6;
const _cessPct = 2;
const _dailyAllowance = 400;
const _loanMarkupPct = 6;
const _startPts = 20000;

/// Offline fake of the whole API: seeded, deterministic, integer pts only.
/// Same inputs (seed + same sequence of actions) always give the same game.
class DemoLedger implements SokoApi {
  DemoLedger({this.seed = 7}) {
    _newDay();
  }
  final int seed;

  int _day = 1;
  Phase _phase = Phase.dawn;
  int _pts = _startPts;
  int _nonce = 0;
  final Map<String, int> _stock = {for (final g in goodsList) g: 0};
  final List<Loan> _loans = [];
  int _repaid = 0, _loanSeq = 0;
  String? _chamaId;
  final Map<String, Map<String, int>> _mStock = {};
  final Set<String> _haggled = {};
  final Map<String, int> _discount = {}; // "m|g" -> pct
  final Map<String, int> _invested = {};
  final Map<int, List<LedgerEntry>> _ledger = {};
  int _faucets = 0, _sinks = 0;
  String _chamaName = 'Chama ya Mama Mboga';
  List<ChamaMember> _members = [];
  int _chamaCash = 0;
  Map<String, dynamic>? _offer;
  int _offerSeq = 0;

  // ---- deterministic randomness -------------------------------------------
  int _h(int a, int b, [int c = 0]) {
    var x =
        (seed * 73856093) ^ (a * 19349663) ^ (b * 83492791) ^ (c * 2654435761);
    x &= 0x7fffffff;
    x = ((x ^ (x >> 15)) * 2246822519) & 0x7fffffff;
    x = ((x ^ (x >> 13)) * 3266489917) & 0x7fffffff;
    return (x ^ (x >> 16)) & 0x7fffffff;
  }

  /// Event of the day, a pure function of (seed, day).
  ({String kind, String text, String? good, int pct})? _eventFor(int day) {
    if (day <= 1) return null;
    switch (_h(day, 99) % 6) {
      case 0:
        return (
          kind: 'ukame',
          text: 'Ukame in Kiambu: tomato supply is short, prices climb.',
          good: 'tomato',
          pct: 18,
        );
      case 1:
        return (
          kind: 'fuel',
          text: 'Fuel price up at the pump; every load costs more to bring in.',
          good: null,
          pct: 7,
        );
      case 2:
        return (
          kind: 'glut',
          text: 'Maize glut from Trans Nzoia; sellers are cutting prices.',
          good: 'maize',
          pct: -14,
        );
      case 3:
        return (
          kind: 'road',
          text: 'Road wash-out near Naivasha delays onion lorries.',
          good: 'onion',
          pct: 12,
        );
      default:
        return null;
    }
  }

  final Map<String, int> _midCache = {};

  /// Mid price, with each day's move capped at +-20% of the day before.
  int _mid(int day, String m, String g) {
    final key = '$day|$m|$g';
    final hit = _midCache[key];
    if (hit != null) return hit;
    var v = _rawMid(day, m, g);
    if (day > 1) {
      final prev = _mid(day - 1, m, g);
      final lo = prev * 80 ~/ 100, hi = prev * 120 ~/ 100;
      v = v.clamp(lo, hi);
    }
    return _midCache[key] = v;
  }

  int _rawMid(int day, String m, String g) {
    final noise =
        (_h(day, m.hashCode & 0xffff, g.hashCode & 0xffff) % 9) - 4; // -4..4
    var pct = 100 + noise;
    final e = _eventFor(day);
    if (e != null && (e.good == null || e.good == g)) pct += e.pct;
    return (_base[g]! * pct) ~/ 100;
  }

  int _ask(String m, String g) {
    final disc = _discount['$m|$g'] ?? 0;
    return (_mid(_day, m, g) * (100 + _marginPct - disc)) ~/ 100;
  }

  int _bid(String m, String g) =>
      (_mid(_day, m, g) * (100 - _marginPct)) ~/ 100;

  List<String> _why(String m, String g) {
    final out = <String>[];
    final e = _eventFor(_day);
    if (e != null && (e.good == null || e.good == g)) {
      out.add(
        '${e.kind == 'fuel'
            ? 'Fuel costs'
            : e.kind == 'ukame'
            ? 'Drought'
            : e.kind == 'glut'
            ? 'Glut'
            : 'Road delays'} moved the mid price ${e.pct > 0 ? '+' : ''}${e.pct}%.',
      );
    }
    final stock = _mStock[m]![g]!;
    out.add(
      stock < 15
          ? 'Only $stock units left at $m, so the ask is firm.'
          : '$m has $stock units, enough to hold the ask steady.',
    );
    out.add(
      'Trader spread is $_marginPct% each way: you buy at ask, sell at bid.',
    );
    if (_perishable.contains(g)) {
      out.add('$g spoils: ${10}% of unsold stock is lost each night.');
    }
    return out;
  }

  // ---- day mechanics --------------------------------------------------------
  void _log(String label, int delta, String cause) {
    _ledger
        .putIfAbsent(_day, () => [])
        .add(LedgerEntry(label: label, delta: delta, cause: cause));
    if (delta > 0 && cause.startsWith('Allowance')) _faucets += delta;
  }

  void _newDay() {
    for (final m in _merchants.keys) {
      _mStock[m] = {
        for (final g in _merchants[m]!)
          g: 20 + _h(_day, m.hashCode & 0xff, g.hashCode & 0xff) % 25,
      };
    }
    _haggled.clear();
    _discount.clear();
    if (_members.isEmpty) {
      _members = [
        ChamaMember(name: 'Amina', shares: 8000, you: false),
        ChamaMember(name: 'Otieno', shares: 8000, you: false),
        ChamaMember(name: 'Mwikali', shares: 8000, you: false),
      ];
      _chamaCash = 24000;
      _offerSeq++;
      _offer = {
        'id': _offerSeq,
        'good': 'maize',
        'qty': 10,
        'total_pts': 22000,
        'deadline_day': _day + 2,
        'votes': <String, String>{},
      };
    }
    if (_day > 1) {
      _pts += _dailyAllowance;
      _log(
        'Market allowance',
        _dailyAllowance,
        'Allowance: a small daily float to keep traders trading.',
      );
    }
  }

  void _endOfDay() {
    // spoilage
    for (final g in _perishable) {
      final lost = _stock[g]! ~/ 10;
      if (lost > 0) {
        _stock[g] = _stock[g]! - lost;
        final v = lost * _mid(_day, 'njeri', g);
        _sinks += v;
        _log(
          'Spoilage: $lost $g',
          0,
          'Spoilage: $lost $g rotted overnight (worth about $v pts).',
        );
      }
    }
    // late loans
    for (var i = 0; i < _loans.length; i++) {
      final l = _loans[i];
      if (_day >= l.dueDay) {
        final pen = l.owed ~/ 10;
        _loans[i] = Loan(
          id: l.id,
          merchant: l.merchant,
          good: l.good,
          qty: l.qty,
          owed: l.owed + pen,
          dueDay: l.dueDay + 1,
          daysTotal: l.daysTotal,
          principal: l.principal,
        );
        _sinks += pen;
        _log(
          'Late fee on ${l.id}',
          0,
          'Deni ${l.id} is overdue: $pen pts added to what you owe.',
        );
      }
    }
    // returns on capital
    _invested.forEach((m, v) {
      final r = v * 2 ~/ 100;
      if (r > 0) {
        _pts += r;
        _log(
          'Return from $m',
          r,
          'Capital in $m earned 2% as the trader sold stock.',
        );
      }
    });
    // chama offer
    final o = _offer;
    if (o != null) {
      final votes = o['votes'] as Map<String, String>;
      if (_day >= (o['deadline_day'] as int) || votes.containsKey('you')) {
        _resolveOffer();
      }
    }
    _day++;
    _phase = Phase.dawn;
    _newDay();
  }

  void _resolveOffer() {
    final o = _offer!;
    final votes = Map<String, String>.from(o['votes'] as Map);
    // NPC members vote deterministically.
    var yes = 0, no = 0;
    for (final m in _members) {
      final key = m.you ? 'you' : m.name;
      final v = m.you
          ? votes['you']
          : (_h(_day, m.name.hashCode & 0xff) % 4 == 0 ? 'no' : 'yes');
      if (v == 'yes') yes++;
      if (v == 'no') no++;
      if (key == 'you' && v == null) continue;
    }
    final total = o['total_pts'] as int;
    if (yes > no && _chamaCash >= total) {
      _chamaCash -= total;
      final ts = _members.fold<int>(0, (a, m) => a + m.shares);
      final me = _members.where((m) => m.you);
      if (me.isNotEmpty) {
        final share = (o['qty'] as int) * me.first.shares ~/ ts;
        _stock[o['good'] as String] = _stock[o['good'] as String]! + share;
        _log(
          'Chama lot: $share ${o['good']}',
          0,
          'Chama bought ${o['qty']} ${o['good']} together; your share of the lot is $share.',
        );
      }
    }
    _offerSeq++;
    _offer = {
      'id': _offerSeq,
      'good': _perishable.contains('kale') && _offerSeq.isEven
          ? 'onion'
          : 'maize',
      'qty': 10,
      'total_pts': 20000 + 500 * (_offerSeq % 3),
      'deadline_day': _day + 3,
      'votes': <String, String>{},
    };
  }

  String get _tier => _repaid >= 8
      ? 'mzoefu'
      : _repaid >= 3
      ? 'mfanyabiashara'
      : 'mgeni';
  int get _limit => _repaid >= 8
      ? 12000
      : _repaid >= 3
      ? 6000
      : 2000;

  PlayerState _snapshot() => PlayerState(
    day: _day,
    phase: _phase,
    pts: _pts,
    stock: Map.of(_stock),
    tier: _tier,
    creditLimit: _limit,
    creditAvailable: (_limit - _loans.fold<int>(0, (a, l) => a + l.owed)).clamp(
      0,
      _limit,
    ),
    playerId: 'demo',
    loans: List.of(_loans),
    chamaId: _chamaId,
    nonce: _nonce,
  );

  // ---- reads ---------------------------------------------------------------
  @override
  Future<Health> health() async => Health(
    version: 'demo-1',
    chainId: 'testnet',
    contractId: 'demo.sokokuu.testnet',
    mode: 'demo',
  );

  @override
  Future<PlayerState> state(String pubkey) async => _snapshot();

  @override
  Future<PriceBoard> prices() async => PriceBoard(
    day: _day,
    indexBp: _indexBp(_day),
    rows: [
      for (final m in _merchants.keys)
        for (final g in _merchants[m]!)
          PriceRow(
            merchant: m,
            good: g,
            ask: _ask(m, g),
            bid: _bid(m, g),
            stock: _mStock[m]![g]!,
            why: _why(m, g),
            history: [
              for (var d = (_day - 6).clamp(1, _day); d <= _day; d++)
                _mid(d, m, g),
            ],
          ),
    ],
  );

  /// Basket index in basis points: today's mid prices against the base prices.
  int _indexBp(int d) =>
      goodsList.fold<int>(0, (a, g) => a + _mid(d, 'njeri', g)) *
      10000 ~/
      _base.values.fold(0, (a, b) => a + b);

  @override
  Future<List<NewsItem>> news() async {
    final out = <NewsItem>[];
    for (var d = _day; d >= (_day - 6).clamp(1, _day); d--) {
      final e = _eventFor(d);
      if (e != null) out.add(NewsItem(text: e.text, day: d, kind: e.kind));
    }
    if (out.isEmpty) {
      out.add(
        NewsItem(
          text: 'Soko is calm today. Prices are near their usual level.',
          day: _day,
          kind: 'calm',
        ),
      );
    }
    return out;
  }

  @override
  Future<List<ChamaSummary>> chamas() async => [
    ChamaSummary(
      id: 'ch1',
      members: _members.length,
      maxMembers: 8,
      joinShare: 3000,
      openOffer: _offer != null,
    ),
  ];

  @override
  Future<Chama?> chama(String id, String myPlayerId) async =>
      _buildChama(joined: _chamaId != null);

  Chama _buildChama({required bool joined}) {
    final o = _offer;
    ChamaOffer? offer;
    if (o != null) {
      final votes = o['votes'] as Map<String, String>;
      offer = ChamaOffer(
        id: o['id'] as int,
        good: o['good'] as String,
        qty: o['qty'] as int,
        totalPts: o['total_pts'] as int,
        yes:
            votes.values.where((v) => v == 'yes').length +
            (_members.where((m) => !m.you).length * 2 ~/ 3),
        no:
            votes.values.where((v) => v == 'no').length +
            (_members.where((m) => !m.you).length ~/ 3),
        deadlineDay: o['deadline_day'] as int,
        myVote: votes['you'],
      );
    }
    return Chama(
      id: 'ch1',
      name: _chamaName,
      members: List.of(_members),
      cash: _chamaCash,
      offer: offer,
    );
  }

  @override
  Future<DayLedger> ledger(String pubkey, int day) async =>
      DayLedger(day: day, entries: List.of(_ledger[day] ?? const []));

  int _stockValue() => _stock.entries.fold(
    0,
    (a, e) => a + e.value * _mid(_day, 'njeri', e.key),
  );

  @override
  Future<SokoReport> report(String pubkey) async => SokoReport(
    faucets: _faucets,
    sinks: _sinks,
    priceIndex: [for (var d = 1; d <= _day; d++) _indexBp(d)],
    solvency: {
      for (final m in _merchants.keys)
        m:
            (80 +
                    _h(_day, m.hashCode & 0xff) % 20 +
                    ((_invested[m] ?? 0) ~/ 1000))
                .clamp(0, 100),
    },
    score: _pts + _stockValue() - _loans.fold(0, (a, l) => a + l.owed),
  );

  @override
  Future<Leaderboard> leaderboard({String? playerId, String? chamaId}) async {
    final s = (await report('')).score;
    return Leaderboard(
      personalBest: s,
      chamas: [
        LeaderRow(
          name: _chamaName,
          score: 91000 + _day * 300,
          you: _chamaId != null,
        ),
        LeaderRow(
          name: 'Chama ya Wakulima',
          score: 88400 + _day * 250,
          you: false,
        ),
        LeaderRow(name: 'Umoja Traders', score: 80100 + _day * 200, you: false),
      ],
    );
  }

  // ---- writes ----------------------------------------------------------------
  ApiException _err(String c, String m) => ApiException(c, m);

  @override
  Future<ActResult> act(SignedAct s) async {
    if (s.sig.isEmpty) throw _err('BAD_SIG', 'Signature missing.');
    if (s.nonce != _nonce + 1) {
      throw _err('BAD_NONCE', 'Out of step. Refresh and try again.');
    }
    if (s.expiresMs < DateTime.now().millisecondsSinceEpoch) {
      throw _err('EXPIRED', 'That request timed out. Try again.');
    }
    final a = s.action;
    const midday = {'buy', 'sell', 'haggle', 'credit_request', 'invest'};
    if (midday.contains(a['type']) && _phase != Phase.midday) {
      throw _err('WRONG_PHASE', 'The market trades at midday only.');
    }
    final events = <String>[];
    switch (a['type']) {
      case 'buy':
        final m = a['merchant'] as String,
            g = a['good'] as String,
            q = a['qty'] as int;
        final ms = _mStock[m]?[g];
        if (ms == null) throw _err('INTERNAL', 'Unknown stall.');
        if (q > ms) throw _err('NOT_ENOUGH_STOCK', '$m only has $ms $g.');
        final ask = _ask(m, g);
        if (ask > (a['max_unit_price'] as int)) {
          throw _err('PRICE_MOVED', 'PRICE_MOVED');
        }
        final cost = ask * q;
        if (cost > _pts) {
          throw _err('NOT_ENOUGH_PTS', 'You need $cost pts, you have $_pts.');
        }
        _pts -= cost;
        _stock[g] = _stock[g]! + q;
        _mStock[m]![g] = ms - q;
        _log('Bought $q $g from $m', -cost, 'Trade: $q x $ask pts at $m.');
        events.add('Bought $q $g for $cost pts');
      case 'sell':
        final m = a['merchant'] as String,
            g = a['good'] as String,
            q = a['qty'] as int;
        if (_stock[g]! < q) {
          throw _err('NOT_ENOUGH_STOCK', 'You only hold ${_stock[g]} $g.');
        }
        final minP = a['min_unit_price'] as int?;
        if (minP != null && _bid(m, g) < minP) {
          throw _err('PRICE_MOVED', 'PRICE_MOVED');
        }
        final gross = _bid(m, g) * q;
        final cess = (gross * _cessPct ~/ 100).clamp(1, gross);
        _pts += gross - cess;
        _sinks += cess;
        _stock[g] = _stock[g]! - q;
        _mStock[m]![g] = _mStock[m]![g]! + q;
        _log(
          'Sold $q $g to $m',
          gross - cess,
          'Trade: $q x ${_bid(m, g)} pts, less $cess pts market cess.',
        );
        events.add('Sold $q $g for ${gross - cess} pts');
      case 'haggle':
        final m = a['merchant'] as String, g = a['good'] as String;
        final key = '$m|$g';
        if (_haggled.contains(key)) {
          throw _err('RATE_LIMITED', 'One haggle per stall per day.');
        }
        _haggled.add(key);
        if (_h(_day, key.hashCode & 0xffff, 5) % 100 < 55) {
          _discount[key] = 4;
          events.add('$m agreed: 4% off the ask on $g today.');
        } else {
          events.add('$m laughed and held the price.');
        }
      case 'chama_join':
        if (a['chama_id'] == null) throw _err('INTERNAL', 'chama_id required');
        if (_chamaId != null) {
          throw _err('WRONG_PHASE', 'You are already in a chama.');
        }
        if (_pts < 3000) {
          throw _err('NOT_ENOUGH_PTS', 'Joining needs a 3000 pts share.');
        }
        _pts -= 3000;
        _chamaCash += 3000;
        _chamaId = 'ch1';
        _members.add(ChamaMember(name: 'You', shares: 3000, you: true));
        _log(
          'Joined $_chamaName',
          -3000,
          'Chama share paid into the common pot.',
        );
        events.add('You joined $_chamaName');
      case 'chama_create':
        if (_chamaId != null) {
          throw _err('WRONG_PHASE', 'You are already in a chama.');
        }
        if (_pts < 1000) {
          throw _err('NOT_ENOUGH_PTS', 'A new chama needs 1000 pts to start.');
        }
        _pts -= 1000;
        _chamaId = 'ch1';
        _chamaName = 'Your chama';
        _members = [ChamaMember(name: 'You', shares: 1000, you: true)];
        _chamaCash = 1000;
        _offer = null;
        _log('Started a chama', -1000, 'First share paid into the new pot.');
        events.add('Chama started');
      case 'chama_vote':
        if (_chamaId == null) throw _err('NOT_MEMBER', 'Join a chama first.');
        final o = _offer;
        if (o == null || o['id'] != a['offer_id']) {
          throw _err('WRONG_PHASE', 'That offer is closed.');
        }
        final votes = o['votes'] as Map<String, String>;
        if (votes.containsKey('you')) {
          throw _err('ALREADY_VOTED', 'You already voted on this lot.');
        }
        votes['you'] = a['vote'] as String;
        events.add('Vote recorded: ${a['vote']}');
      case 'credit_request':
        final m = a['merchant'] as String,
            g = a['good'] as String,
            q = a['qty'] as int;
        final ms = _mStock[m]?[g];
        if (ms == null || q > ms) {
          throw _err('NOT_ENOUGH_STOCK', '$m cannot cover that.');
        }
        final cost = _ask(m, g) * q;
        final owed = cost + cost * _loanMarkupPct ~/ 100;
        final open = _loans.fold<int>(0, (x, l) => x + l.owed);
        if (open + owed > _limit) {
          throw _err(
            'CREDIT_DENIED',
            'That would take your debt to ${open + owed} pts; your limit is $_limit.',
          );
        }
        _mStock[m]![g] = ms - q;
        _stock[g] = _stock[g]! + q;
        _loans.add(
          Loan(
            id: ++_loanSeq,
            merchant: m,
            good: g,
            qty: q,
            owed: owed,
            principal: cost,
            dueDay: _day + 5,
            daysTotal: 5,
          ),
        );
        _sinks += owed - cost;
        _log(
          'Deni: $q $g from $m',
          0,
          'Took goods on credit. You owe $owed pts by day ${_day + 5} (markup ${owed - cost}).',
        );
        events.add('Took $q $g on credit, owe $owed pts');
      case 'credit_repay':
        final i = _loans.indexWhere((l) => l.id == a['loan_id']);
        if (i < 0) throw _err('INTERNAL', 'No such loan.');
        final l = _loans[i];
        if (l.owed > _pts) {
          throw _err('NOT_ENOUGH_PTS', 'You need ${l.owed} pts to clear this.');
        }
        _pts -= l.owed;
        _loans.removeAt(i);
        _repaid++;
        _log('Repaid ${l.id}', -l.owed, 'Deni to ${l.merchant} cleared.');
        events.add('Loan ${l.id} cleared');
      case 'guarantee':
        if (_chamaId == null) {
          throw _err('NOT_MEMBER', 'Only chama members can guarantee.');
        }
        events.add('You stood guarantor for ${a['borrower']}');
      case 'invest':
        final p = a['pts'] as int;
        if (p <= 0 || p > _pts) {
          throw _err('NOT_ENOUGH_PTS', 'You do not have $p pts.');
        }
        _pts -= p;
        _invested[a['merchant'] as String] =
            (_invested[a['merchant']] ?? 0) + p;
        _log(
          'Capital to ${a['merchant']}',
          -p,
          'Mtaji added; earns 2% a day while the trader sells.',
        );
        events.add('Added $p pts of capital');
      case 'delete_account':
        events.add('Account deleted');
      case 'advance':
        if (_phase == Phase.dusk) {
          _endOfDay();
          events.add('Day $_day begins');
        } else {
          _phase = _phase == Phase.dawn ? Phase.midday : Phase.dusk;
          events.add('It is now ${_phase.name}');
        }
      default:
        throw _err('INTERNAL', 'Unknown action.');
    }
    _nonce = s.nonce;
    return ActResult(
      txHash: 'demo-${_nonce.toRadixString(16)}',
      state: _snapshot(),
      events: events,
    );
  }

  @override
  Future<EventBatch> events(int since) async => EventBatch(
    events: const [],
    lastId: since,
    day: _day,
    phase: _phase.name,
  );

  /// Same input, same output: a tiny drift model, enough for the offline fast-forward.
  @override
  Future<List<SimFrame>> sim(
    int seed,
    int days,
    List<Map<String, dynamic>> events,
  ) async {
    var idx = 10000;
    final out = <SimFrame>[];
    for (var d = 1; d <= days; d++) {
      final fired = [
        for (final e in events)
          if (e['day'] == d) e,
      ];
      var move = (_h(d, seed, 3) % 9) - 4; // -4..4 percent of a percent
      for (final e in fired) {
        move +=
            (e['kind'] == 'glut' || e['kind'] == 'festival' ? -1 : 1) *
            (e['magnitude'] as int) ~/
            10;
      }
      idx = (idx * (10000 + move * 10) ~/ 10000).clamp(8000, 12000);
      out.add(
        SimFrame(
          day: d,
          supply: 560000,
          driftBp: 0,
          priceIndexBp: idx,
          solventMerchants: 3,
          openLoans: 0,
          defaults: 0,
          events: [for (final e in fired) '${e['kind']}'],
        ),
      );
    }
    return out;
  }

  @override
  Future<void> guest(String pubkey) async {}
  @override
  Future<void> register(String email, String pubkey) async {}
  @override
  Future<String> confirm(String token, String pubkey) async => 'demo-player';
  @override
  Future<void> deleteAccount(SignedAct act) async {}
}
