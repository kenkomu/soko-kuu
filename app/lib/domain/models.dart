/// Plain models. All money is integer pts.
enum Phase { dawn, midday, dusk }

Phase phaseFrom(String s) =>
    Phase.values.firstWhere((p) => p.name == s, orElse: () => Phase.dawn);

int _i(Object? v, [int d = 0]) => v is num ? v.toInt() : d;

class Loan {
  Loan({
    required this.id,
    required this.merchant,
    required this.good,
    required this.qty,
    required this.owed,
    required this.dueDay,
    this.daysTotal = 5,
    this.principal = 0,
    this.interestPct = 6,
    this.lender = 'merchant',
    this.lenderId,
    this.guarantor,
  });
  final int id;
  final String merchant, good, lender;
  final String? lenderId, guarantor;
  final int qty, owed, dueDay, daysTotal, principal, interestPct;
  factory Loan.fromJson(Map<String, dynamic> j) => Loan(
    id: _i(j['id']),
    merchant: (j['merchant'] ?? '') as String,
    good: (j['good'] ?? '') as String,
    qty: _i(j['qty']),
    owed: _i(j['owed']),
    dueDay: _i(j['due_day']),
    principal: _i(j['principal']),
    interestPct: _i(j['interest_pct'], 6),
    lender: (j['lender'] ?? 'merchant') as String,
    lenderId: j['lender_id'] as String?,
    guarantor: j['guarantor'] as String?,
  );
}

class PlayerState {
  PlayerState({
    required this.day,
    required this.phase,
    required this.pts,
    required this.stock,
    required this.tier,
    required this.creditLimit,
    required this.loans,
    this.chamaId,
    this.nonce = 0,
    this.nextPhaseMs,
    this.playerId = '',
    this.creditAvailable,
    this.reputationScore = 0,
  });
  final int day, pts, nonce, reputationScore;

  /// Whole tier limit (what the player may owe at most).
  final int creditLimit;

  /// Tier limit minus outstanding; null when the source does not say.
  final int? creditAvailable;
  final String playerId;

  /// Epoch ms when the relayer clock moves next, or null if no timer.
  final int? nextPhaseMs;
  final Phase phase;
  final Map<String, int> stock;
  final String tier;
  final List<Loan> loans;
  final String? chamaId;
  int get openDebt => loans.fold(0, (a, l) => a + l.owed);
  factory PlayerState.fromJson(Map<String, dynamic> j) {
    final credit = (j['credit'] as Map?) ?? const {};
    final rep = (j['reputation'] as Map?) ?? const {};
    return PlayerState(
      playerId: (j['player_id'] ?? '') as String,
      day: _i(j['day']),
      phase: phaseFrom(j['phase'] as String),
      pts: _i(j['pts']),
      stock: ((j['stock'] ?? {}) as Map).map(
        (k, v) => MapEntry(k as String, _i(v)),
      ),
      tier: (rep['tier'] ?? 'mgeni') as String,
      reputationScore: _i(rep['score']),
      creditLimit: _i(credit['tier_limit'] ?? credit['limit']),
      creditAvailable: credit['limit'] == null ? null : _i(credit['limit']),
      loans: ((j['loans'] ?? []) as List)
          .map((e) => Loan.fromJson(e as Map<String, dynamic>))
          .toList(),
      chamaId: j['chama_id'] as String?,
      nonce: _i(j['nonce']),
      nextPhaseMs: j['next_phase_ms'] as int?,
    );
  }
}

class PriceRow {
  PriceRow({
    required this.merchant,
    required this.good,
    required this.ask,
    required this.bid,
    required this.stock,
    required this.why,
    required this.history,
  });
  final String merchant, good;
  final int ask, bid, stock;
  final List<String> why;
  final List<int> history; // up to 30 daily asks, oldest first; last = live ask
  factory PriceRow.fromJson(Map<String, dynamic> j) => PriceRow(
    merchant: j['merchant'] as String,
    good: j['good'] as String,
    ask: _i(j['ask']),
    bid: _i(j['bid']),
    stock: _i(j['stock']),
    why: ((j['why'] ?? []) as List).cast<String>(),
    history: ((j['history'] ?? []) as List).map((e) => _i(e)).toList(),
  );
}

/// `GET /v1/prices`: the flat rows plus the basket index (basis points, 10000 = 100%).
class PriceBoard {
  PriceBoard({required this.rows, required this.indexBp, this.day = 0});
  final List<PriceRow> rows;
  final int indexBp;
  final int day;
  factory PriceBoard.fromJson(Map<String, dynamic> j) => PriceBoard(
    rows: ((j['items'] ?? []) as List)
        .map((e) => PriceRow.fromJson(e as Map<String, dynamic>))
        .toList(),
    indexBp: _i(j['price_index_bp'] ?? j['price_index']),
    day: _i(j['day']),
  );
}

class NewsItem {
  NewsItem({required this.text, required this.day, required this.kind});
  final String text, kind;
  final int day;
  factory NewsItem.fromJson(Map<String, dynamic> j) => NewsItem(
    text: j['text'] as String,
    day: j['day'] as int,
    kind: j['kind'] as String,
  );
}

class ChamaOffer {
  ChamaOffer({
    required this.id,
    required this.good,
    required this.qty,
    required this.totalPts,
    required this.yes,
    required this.no,
    required this.deadlineDay,
    required this.myVote,
    this.borrower = '',
    this.merchant = '',
    this.owed = 0,
  });
  final int id, qty, totalPts, yes, no, deadlineDay, owed;
  final String good, borrower, merchant;
  final String? myVote;
  bool borrowerIs(String playerId) =>
      playerId.isNotEmpty && borrower == playerId;
  factory ChamaOffer.fromJson(Map<String, dynamic> j, String me) {
    final votes = ((j['votes'] ?? {}) as Map).cast<String, dynamic>();
    return ChamaOffer(
      id: _i(j['id']),
      good: (j['good'] ?? '') as String,
      qty: _i(j['qty']),
      totalPts: _i(j['cost']),
      owed: _i(j['owed']),
      yes: votes.values.where((v) => v == 'yes').length,
      no: votes.values.where((v) => v == 'no').length,
      deadlineDay: _i(j['deadline_day']),
      myVote: votes[me] as String?,
      borrower: (j['borrower'] ?? '') as String,
      merchant: (j['merchant'] ?? '') as String,
    );
  }
}

class ChamaMember {
  ChamaMember({required this.name, required this.shares, required this.you});
  final String name;
  final int shares;
  final bool you;
}

class Chama {
  Chama({
    required this.id,
    required this.name,
    required this.members,
    required this.cash,
    this.offer,
  });
  final String id, name;
  final List<ChamaMember> members;
  final int cash;
  final ChamaOffer? offer;
  int get totalShares => members.fold(0, (a, m) => a + m.shares);

  /// `GET /v1/chama/{id}`: members is a list of player ids, shares a map id -> pts.
  factory Chama.fromJson(Map<String, dynamic> j, String me) {
    final shares = ((j['shares'] ?? {}) as Map).cast<String, dynamic>();
    final id = j['id'] as String;
    return Chama(
      id: id,
      name: 'Chama ${id.toUpperCase()}',
      members: [
        for (final m in (j['members'] as List).cast<String>())
          ChamaMember(name: m, shares: _i(shares[m]), you: m == me),
      ],
      cash: _i(j['cash']),
      offer: j['offer'] == null
          ? null
          : ChamaOffer.fromJson(j['offer'] as Map<String, dynamic>, me),
    );
  }
}

/// A row of `GET /v1/chamas` (chamas with room, for discovery).
class ChamaSummary {
  ChamaSummary({
    required this.id,
    required this.members,
    required this.maxMembers,
    required this.joinShare,
    required this.openOffer,
  });
  final String id;
  final int members, maxMembers, joinShare;
  final bool openOffer;
  factory ChamaSummary.fromJson(Map<String, dynamic> j, int defaultShare) =>
      ChamaSummary(
        id: j['id'] as String,
        members: _i(j['members']),
        maxMembers: _i(j['max_members'], 8),
        joinShare: _i(j['join_share'], defaultShare),
        openOffer: j['open_offer'] == true,
      );
}

class LedgerEntry {
  LedgerEntry({required this.label, required this.delta, required this.cause});
  final String label, cause;
  final int delta;
  factory LedgerEntry.fromJson(Map<String, dynamic> j) => LedgerEntry(
    label: j['label'] as String,
    delta: j['delta'] as int,
    cause: j['cause'] as String,
  );
}

class DayLedger {
  DayLedger({required this.day, required this.entries});
  final int day;
  final List<LedgerEntry> entries;
  int get net => entries.fold(0, (a, e) => a + e.delta);
  factory DayLedger.fromJson(Map<String, dynamic> j) => DayLedger(
    day: j['day'] as int,
    entries: (j['entries'] as List)
        .map((e) => LedgerEntry.fromJson(e as Map<String, dynamic>))
        .toList(),
  );
}

class SokoReport {
  SokoReport({
    required this.faucets,
    required this.sinks,
    required this.priceIndex,
    required this.solvency,
    required this.score,
    this.best = 0,
    this.driftBp = 0,
  });
  final int faucets, sinks, score, best, driftBp;

  /// Basket index in basis points (10000 = 100%), oldest first, last = today.
  final List<int> priceIndex;
  final Map<String, int> solvency; // merchant -> percent
}

class LeaderRow {
  LeaderRow({required this.name, required this.score, required this.you});
  final String name;
  final int score;
  final bool you;
}

class Leaderboard {
  Leaderboard({required this.personalBest, required this.chamas});
  final int personalBest;
  final List<LeaderRow> chamas;
}

class Health {
  Health({
    required this.version,
    required this.chainId,
    required this.contractId,
    required this.mode,
    this.paused = false,
    this.degraded,
  });
  final String version, chainId, contractId, mode;
  final bool paused;
  final String? degraded;
  factory Health.fromJson(Map<String, dynamic> j) => Health(
    version: j['version'] as String,
    chainId: j['chain_id'] as String,
    contractId: j['contract_id'] as String,
    mode: j['mode'] as String,
    paused: j['paused'] == true,
    degraded: j['degraded'] as String?,
  );
}

class ActResult {
  ActResult({required this.txHash, required this.state, required this.events});
  final String txHash;
  final PlayerState state;
  final List<String> events;
}

/// An API error envelope: `{ ok:false, error:{code,message} }`.
class ApiException implements Exception {
  ApiException(this.code, this.message, {this.retryAfterS});
  final String code, message;
  final int? retryAfterS;
  @override
  String toString() => message;
}
