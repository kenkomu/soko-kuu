import '../domain/models.dart';

/// A signed write, ready for `POST /v1/act`.
class SignedAct {
  SignedAct({
    required this.pubkey,
    required this.nonce,
    required this.expiresMs,
    required this.action,
    required this.actionJson,
    required this.sig,
  });
  final String pubkey, sig;
  final int nonce, expiresMs;
  final Map<String, dynamic> action; // parsed copy, for the demo ledger only
  final String actionJson; // exact string that was signed and is sent
  Map<String, dynamic> toJson() => {
    'pubkey': pubkey,
    'nonce': nonce,
    'expires_ms': expiresMs,
    'action_json': actionJson,
    'sig': sig,
  };
}

/// The whole surface the UI may use. Implemented by RelayerClient (HTTP)
/// and DemoLedger (offline fake). The UI never touches anything else.
abstract class SokoApi {
  Future<Health> health();
  Future<PlayerState> state(String pubkey);
  Future<PriceBoard> prices();
  Future<List<NewsItem>> news();
  Future<List<ChamaSummary>> chamas();
  Future<Chama?> chama(String id, String myPlayerId);
  Future<DayLedger> ledger(String pubkey, int day);
  Future<SokoReport> report(String pubkey);
  Future<Leaderboard> leaderboard({String? playerId, String? chamaId});

  /// Long-poll (real runner only). Returns at once when `id > since` events exist.
  Future<EventBatch> events(int since);

  /// Deterministic fast-forward. Frames are basis points.
  Future<List<SimFrame>> sim(
    int seed,
    int days,
    List<Map<String, dynamic>> events,
  );
  Future<ActResult> act(SignedAct act);
  Future<void> guest(String pubkey);
  Future<void> register(String email, String pubkey);
  Future<String> confirm(String token, String pubkey);
  Future<void> deleteAccount(SignedAct act);
}

class GameEvent {
  GameEvent({
    required this.id,
    required this.kind,
    required this.data,
    this.day = 0,
  });
  final int id, day;
  final String kind; // phase | news | chama_vote | loan_reminder
  final Map<String, dynamic> data;
}

class EventBatch {
  EventBatch({
    required this.events,
    required this.lastId,
    this.day,
    this.phase,
  });
  final List<GameEvent> events;
  final int lastId;
  final int? day;
  final String? phase;
}

class SimFrame {
  SimFrame({
    required this.day,
    required this.supply,
    required this.driftBp,
    required this.priceIndexBp,
    required this.solventMerchants,
    required this.openLoans,
    required this.defaults,
    required this.events,
  });
  final int day,
      supply,
      driftBp,
      priceIndexBp,
      solventMerchants,
      openLoans,
      defaults;
  final List<String> events;
  factory SimFrame.fromJson(Map<String, dynamic> j) => SimFrame(
    day: (j['day'] as num).toInt(),
    supply: (j['supply'] as num? ?? 0).toInt(),
    driftBp: (j['drift_bp'] as num? ?? 0).toInt(),
    priceIndexBp: (j['price_index_bp'] as num? ?? 10000).toInt(),
    solventMerchants: (j['solvent_merchants'] as num? ?? 0).toInt(),
    openLoans: (j['open_loans'] as num? ?? 0).toInt(),
    defaults: (j['defaults'] as num? ?? 0).toInt(),
    events: ((j['events'] ?? []) as List)
        .map((e) => e is Map ? '${e['kind'] ?? e}' : '$e')
        .toList(),
  );
}
