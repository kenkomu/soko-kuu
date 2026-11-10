import 'dart:convert';

import 'package:http/http.dart' as http;

import '../domain/models.dart';
import 'api_client.dart';

/// HTTP implementation of docs/API.md. `base` comes from --dart-define=API_BASE.
/// Payload shapes: runner/SHAPES.md.
class RelayerClient implements SokoApi {
  RelayerClient(this.base, {http.Client? client})
    : _c = client ?? http.Client();
  final String base;
  final http.Client _c;

  /// GET cache for ETag / If-None-Match: path -> (etag, decoded data).
  final Map<String, (String, dynamic)> _etags = {};

  /// Basket index per game day, collected from /v1/prices (the report has only today's value).
  final Map<int, int> _indexByDay = {};

  /// How many requests were answered 304 (so tests can see the ETag path work).
  int notModified = 0;

  Future<dynamic> _send(
    String method,
    String path, {
    Map<String, dynamic>? body,
    Duration? timeout,
    bool etag = false,
  }) async {
    final uri = Uri.parse('$base$path');
    final headers = {'content-type': 'application/json'};
    final cached = etag && method == 'GET' ? _etags[path] : null;
    if (cached != null) headers['if-none-match'] = cached.$1;
    http.Response r;
    try {
      r = switch (method) {
        'GET' =>
          await _c
              .get(
                uri,
                headers: {if (cached != null) 'if-none-match': cached.$1},
              )
              .timeout(timeout ?? const Duration(seconds: 15)),
        'DELETE' =>
          await _c
              .delete(uri, headers: headers, body: jsonEncode(body))
              .timeout(const Duration(seconds: 15)),
        _ =>
          await _c
              .post(uri, headers: headers, body: jsonEncode(body))
              .timeout(const Duration(seconds: 20)),
      };
    } catch (_) {
      throw ApiException(
        'OFFLINE',
        'Cannot reach the market. Check your connection.',
      );
    }
    if (r.statusCode == 304 && cached != null) {
      notModified++;
      return cached.$2;
    }
    Map<String, dynamic> j;
    try {
      j = jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
    } catch (_) {
      throw ApiException('INTERNAL', 'The market sent something unreadable.');
    }
    if (j['ok'] != true) {
      final e = (j['error'] ?? {}) as Map<String, dynamic>;
      throw ApiException(
        (e['code'] ?? 'INTERNAL') as String,
        (e['message'] ?? 'Something went wrong.') as String,
        retryAfterS: (e['retry_after_s'] as num?)?.toInt(),
      );
    }
    final tag = r.headers['etag'];
    if (etag && method == 'GET' && tag != null) _etags[path] = (tag, j['data']);
    return j['data'];
  }

  Map<String, dynamic> _m(dynamic d) => d as Map<String, dynamic>;
  List<Map<String, dynamic>> _l(dynamic d) =>
      (d as List).cast<Map<String, dynamic>>();
  String _q(String s) => Uri.encodeQueryComponent(s);

  @override
  Future<Health> health() async =>
      Health.fromJson(_m(await _send('GET', '/v1/health')));

  @override
  Future<PlayerState> state(String pubkey) async => PlayerState.fromJson(
    _m(await _send('GET', '/v1/state?pubkey=${_q(pubkey)}', etag: true)),
  );

  @override
  Future<PriceBoard> prices() async {
    final b = PriceBoard.fromJson(
      _m(await _send('GET', '/v1/prices', etag: true)),
    );
    _indexByDay[b.day] = b.indexBp;
    return b;
  }

  @override
  Future<List<NewsItem>> news() async {
    final d = await _send('GET', '/v1/news', etag: true);
    return _l(d is Map ? d['items'] : d).map(NewsItem.fromJson).toList();
  }

  @override
  Future<List<ChamaSummary>> chamas() async {
    final d = _m(await _send('GET', '/v1/chamas', etag: true));
    final share = (d['join_share'] as num? ?? 0).toInt();
    return _l(d['items'] ?? const [])
        .map((e) => ChamaSummary.fromJson(e, share))
        .toList();
  }

  @override
  Future<Chama?> chama(String id, String myPlayerId) async {
    try {
      final d = await _send(
        'GET',
        '/v1/chama/${Uri.encodeComponent(id)}',
        etag: true,
      );
      return d == null ? null : Chama.fromJson(_m(d), myPlayerId);
    } on ApiException catch (e) {
      if (e.code == 'NOT_MEMBER') return null; // unknown chama id
      rethrow;
    }
  }

  @override
  Future<DayLedger> ledger(String pubkey, int day) async {
    final d = _m(
      await _send(
        'GET',
        '/v1/ledger?pubkey=${_q(pubkey)}&day=$day',
        etag: true,
      ),
    );
    return DayLedger(
      day: (d['day'] as num).toInt(),
      entries: _l(d['entries'])
          .map(
            (e) => LedgerEntry(
              label: titleCaseKind(e['kind']),
              delta: (e['delta'] as num).toInt(),
              cause: (e['cause'] ?? '') as String,
            ),
          )
          .toList(),
    );
  }

  @override
  Future<SokoReport> report(String pubkey) async {
    final d = _m(
      await _send('GET', '/v1/report?pubkey=${_q(pubkey)}', etag: true),
    );
    int sum(dynamic m) => m is Map
        ? m.values.fold<int>(0, (a, v) => a + (v as num).toInt())
        : (m as num? ?? 0).toInt();
    final today = (d['day'] as num? ?? 0).toInt();
    final bp = (d['price_index_bp'] ?? d['price_index'] ?? 10000) as num;
    _indexByDay[today] = bp.toInt();
    final days = _indexByDay.keys.toList()..sort();
    final score = d['score'] as Map?;
    return SokoReport(
      faucets: sum(d['faucets']),
      sinks: sum(d['sinks']),
      priceIndex: [for (final k in days) _indexByDay[k]!],
      solvency: {
        for (final m in (d['merchants'] as List? ?? const []))
          (m as Map)['id'] as String: m['solvent'] == true ? 100 : 0,
      },
      score: (score?['net_worth'] as num? ?? 0).toInt(),
      best: (score?['best'] as num? ?? 0).toInt(),
      driftBp: (d['drift_bp'] as num? ?? 0).toInt(),
    );
  }

  @override
  Future<Leaderboard> leaderboard({String? playerId, String? chamaId}) async {
    final d = _m(await _send('GET', '/v1/leaderboard', etag: true));
    final mine = (d['personal'] as List? ?? const []).cast<Map>().where(
      (e) => e['player_id'] == playerId,
    );
    return Leaderboard(
      personalBest: mine.isEmpty
          ? 0
          : (mine.first['best_net_worth'] as num).toInt(),
      chamas: [
        for (final e in (d['chamas'] as List? ?? const []).cast<Map>())
          LeaderRow(
            name: 'Chama ${'${e['chama_id']}'.toUpperCase()}',
            score: (e['score'] as num? ?? 0).toInt(),
            you: e['chama_id'] == chamaId,
          ),
      ],
    );
  }

  @override
  Future<ActResult> act(SignedAct a) async {
    final d = _m(await _send('POST', '/v1/act', body: a.toJson()));
    // `state` is authoritative and complete (SHAPES.md); no second read is needed.
    return ActResult(
      txHash: (d['tx_hash'] ?? '') as String,
      state: PlayerState.fromJson(_m(d['state'])),
      events: ((d['events'] ?? []) as List)
          .map(
            (e) => e is String
                ? e
                : (e as Map)['text']?.toString() ?? e.toString(),
          )
          .toList(),
    );
  }

  @override
  Future<EventBatch> events(int since) async {
    final d = _m(
      await _send(
        'GET',
        '/v1/events?since=$since',
        timeout: const Duration(seconds: 35),
      ),
    );
    return EventBatch(
      events: [
        for (final e in _l(d['events'] ?? const []))
          GameEvent(
            id: (e['id'] as num).toInt(),
            kind: '${e['kind']}',
            day: (e['day'] as num? ?? 0).toInt(),
            data: (e['data'] as Map?)?.cast<String, dynamic>() ?? const {},
          ),
      ],
      lastId: (d['last_id'] as num? ?? since).toInt(),
      day: (d['day'] as num?)?.toInt(),
      phase: d['phase'] as String?,
    );
  }

  @override
  Future<List<SimFrame>> sim(
    int seed,
    int days,
    List<Map<String, dynamic>> events,
  ) async {
    final d = _m(
      await _send(
        'POST',
        '/v1/sim',
        body: {'seed': seed, 'days': days, 'events': events},
      ),
    );
    return _l(d['frames']).map(SimFrame.fromJson).toList();
  }

  @override
  Future<void> guest(String pubkey) async => _send(
    'POST',
    '/v1/auth/guest',
    body: {'pubkey': pubkey, 'age_confirmed': true},
  );
  @override
  Future<void> register(String email, String pubkey) async => _send(
    'POST',
    '/v1/auth/register',
    body: {'email': email, 'pubkey': pubkey, 'consent': true},
  );
  @override
  Future<String> confirm(String token, String pubkey) async =>
      (_m(
            await _send(
              'POST',
              '/v1/auth/confirm',
              body: {'token': token, 'pubkey': pubkey},
            ),
          )['player_id'])
          as String;
  @override
  Future<void> deleteAccount(SignedAct a) async =>
      _send('DELETE', '/v1/auth/account', body: a.toJson());
}

String titleCaseKind(Object? k) {
  final s = '${k ?? 'entry'}'.replaceAll('_', ' ');
  return s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
}
