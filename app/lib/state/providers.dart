import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../l10n.dart';
import '../core/signing.dart';
import '../data/api_client.dart';
import '../data/demo_ledger.dart';
import '../data/relayer_client.dart';
import '../domain/models.dart';
import '../ui/kit/feel.dart';
import 'trade_book.dart';

const _apiBase = String.fromEnvironment('API_BASE', defaultValue: '');
const _demoFlag = bool.fromEnvironment('DEMO', defaultValue: false);

/// Demo is on if --dart-define=DEMO=true, or if no API_BASE was given.
bool get demoDefault => _demoFlag || _apiBase.isEmpty;

final prefsProvider = Provider<SharedPreferences>(
  (ref) => throw UnimplementedError('override in main'),
);

/// Player can flip to the offline demo from Settings when the runner is down.
class DemoMode extends Notifier<bool> {
  @override
  bool build() =>
      demoDefault || (ref.read(prefsProvider).getBool('force_demo') ?? false);
  void set(bool v) {
    state = v;
    ref.read(prefsProvider).setBool('force_demo', v);
  }
}

class _PrefFlag extends Notifier<bool> {
  _PrefFlag(this.key, this.def);
  final String key;
  final bool def;
  @override
  bool build() => ref.read(prefsProvider).getBool(key) ?? def;
  void set(bool v) {
    state = v;
    ref.read(prefsProvider).setBool(key, v);
    Feel.load(ref.read(prefsProvider));
  }
}

/// Settings toggles. Sound is off by default.
final hapticsProvider = NotifierProvider<_PrefFlag, bool>(
  () => _PrefFlag('haptics', true),
);
final soundProvider = NotifierProvider<_PrefFlag, bool>(
  () => _PrefFlag('sound', false),
);

final demoModeProvider = NotifierProvider<DemoMode, bool>(DemoMode.new);

final apiProvider = Provider<SokoApi>((ref) {
  final demo = ref.watch(demoModeProvider);
  return demo ? DemoLedger() : RelayerClient(_apiBase);
});

/// Real mode needs an email-bound player; demo mode never does.
class LoggedIn extends Notifier<bool> {
  @override
  bool build() =>
      ref.watch(demoModeProvider) ||
      (ref.read(prefsProvider).getBool('logged_in') ?? false);
  void done() {
    ref.read(prefsProvider).setBool('logged_in', true);
    state = true;
  }
}

final loggedInProvider = NotifierProvider<LoggedIn, bool>(LoggedIn.new);

/// Tests set this false (no platform channel in the VM).
bool useSecureStorage = !kIsWeb;

/// Android: Keystore-backed secure storage. Web (and any failure): a throwaway
/// demo key in shared_preferences, labelled as such in Settings.
Future<Signer> loadSigner(SharedPreferences prefs) async {
  const store = FlutterSecureStorage();
  String? saved;
  var secure = useSecureStorage;
  if (secure) {
    try {
      saved = await store.read(key: 'key_seed');
    } catch (_) {
      secure = false;
    }
  }
  saved ??= prefs.getString('key_seed');
  if (saved != null) {
    if (secure && prefs.containsKey('key_seed')) {
      // migrate an earlier insecure copy into secure storage
      try {
        await store.write(key: 'key_seed', value: saved);
        await prefs.remove('key_seed');
      } catch (_) {}
    }
    return Signer.fromSeed(base64.decode(saved));
  }
  final signer = await Signer.generate();
  final enc = base64.encode(signer.seed);
  if (secure) {
    try {
      await store.write(key: 'key_seed', value: enc);
      return signer;
    } catch (_) {}
  }
  await prefs.setString('key_seed', enc);
  return signer;
}

final healthProvider = FutureProvider<Health>(
  (ref) => ref.watch(apiProvider).health(),
);

class AgeGate extends Notifier<bool> {
  @override
  bool build() => ref.read(prefsProvider).getBool('age_ok') ?? false;
  void accept() {
    ref.read(prefsProvider).setBool('age_ok', true);
    state = true;
  }
}

final ageGateProvider = NotifierProvider<AgeGate, bool>(AgeGate.new);

/// Holds the key and signs actions. On web this key is throwaway/demo-grade.
class Session {
  Session(this.signer, this.chainId, this.contractId);
  final Signer signer;
  final String chainId, contractId;
  int nonce = 0;

  Future<SignedAct> sign(Map<String, dynamic> action) async {
    final n = nonce + 1;
    final exp =
        DateTime.now().millisecondsSinceEpoch +
        90 * 1000; // API allows 2 minutes
    final json = canonicalJson(action);
    final msg = signingMessageRaw(
      chainId: chainId,
      contractId: contractId,
      pubkey: signer.pubkey,
      nonce: n,
      expiresMs: exp,
      actionJson: json,
    );
    return SignedAct(
      pubkey: signer.pubkey,
      nonce: n,
      expiresMs: exp,
      action: action,
      actionJson: json,
      sig: await signer.signBase64(msg),
    );
  }
}

final sessionProvider = FutureProvider<Session>((ref) async {
  final prefs = ref.read(prefsProvider);
  final api = ref.watch(apiProvider);
  final signer = await loadSigner(prefs);
  final h = await api.health();
  final s = Session(signer, h.chainId, h.contractId);
  s.nonce = (await api.state(signer.pubkey)).nonce;
  return s;
});

/// A player-signed `advance` is refused on testnet: the relayer owns the clock.
String clockMessage(String lang) => lang == 'sw'
    ? 'Saa ya soko husonga yenyewe.'
    : 'The market clock moves by itself.';

String friendlyError(ApiException e, String lang) {
  final base = errorText.containsKey(e.code)
      ? errorSentence(e.code, lang)
      : (e.message.isEmpty ? errorSentence('INTERNAL', lang) : e.message);
  final r = e.retryAfterS;
  if (e.code == 'RATE_LIMITED' && r != null && r > 0) {
    return lang == 'sw' ? '$base (sekunde $r)' : '$base (${r}s)';
  }
  return base;
}

class GameState {
  GameState({
    required this.player,
    required this.prices,
    required this.news,
    this.message,
    this.indexBp = 10000,
  });
  final PlayerState player;
  final List<PriceRow> prices;

  /// Basket index, basis points (10000 = 100%).
  final int indexBp;
  final List<NewsItem> news;
  final String? message;
}

class GameNotifier extends AsyncNotifier<GameState> {
  /// [fresh] is the full state an act just returned: it is authoritative, so no state read is needed.
  Future<GameState> _load([String? msg, PlayerState? fresh]) async {
    final api = ref.read(apiProvider);
    final s = await ref.read(sessionProvider.future);
    final r = await Future.wait([
      fresh != null ? Future.value(fresh) : api.state(s.signer.pubkey),
      api.prices(),
      api.news(),
    ]);
    s.nonce = (r[0] as PlayerState).nonce;
    final board = r[1] as PriceBoard;
    return GameState(
      player: r[0] as PlayerState,
      prices: board.rows,
      indexBp: board.indexBp,
      news: r[2] as List<NewsItem>,
      message: msg,
    );
  }

  @override
  Future<GameState> build() {
    _pollEvents();
    return _load();
  }

  bool _disposed = false;
  bool _polling = false;

  /// Real runner only: long-poll /v1/events and reload when the clock moves or news lands.
  /// Backs off on errors; stops with the notifier. The demo ledger has no clock to follow.
  Future<void> _pollEvents() async {
    final api = ref.read(apiProvider);
    if (api is! RelayerClient || _polling) return;
    _polling = true;
    ref.onDispose(() => _disposed = true);
    var since = 0, wait = 1;
    try {
      since = (await api.events(0))
          .lastId; // start from now; the first load reads current state
    } catch (_) {}
    while (!_disposed) {
      try {
        final b = await api.events(since);
        since = b.lastId;
        wait = 1;
        if (_disposed) break;
        if (b.events.any(
          (e) =>
              e.kind == 'phase' ||
              e.kind == 'news' ||
              e.kind == 'chama_vote' ||
              e.kind == 'loan_reminder',
        )) {
          final next = await AsyncValue.guard(_load);
          if (!_disposed && next.hasValue) state = next;
          ref.invalidate(chamaProvider);
          ref.invalidate(reportProvider);
        }
      } catch (_) {
        await Future<void>.delayed(Duration(seconds: wait));
        wait = wait < 30 ? wait * 2 : 30;
      }
    }
  }

  Future<void> refresh() async => state = await AsyncValue.guard(_load);

  /// Signs and sends an action; returns an error message or null on success.
  /// The sale the player just made, for the result view (cleared on read).
  TradeResult? takeResult() {
    final r = _last;
    _last = null;
    return r;
  }

  TradeResult? _last;

  Future<String?> act(Map<String, dynamic> action) async {
    final before = state.value?.player;
    final api = ref.read(apiProvider);
    final s = await ref.read(sessionProvider.future);
    try {
      SignedAct signed = await s.sign(action);
      if (action['type'] == 'delete_account') {
        await api.deleteAccount(signed);
        s.nonce = signed.nonce;
        await ref.read(prefsProvider).remove('logged_in');
        return null;
      }
      ActResult res;
      try {
        res = await api.act(signed);
      } on ApiException catch (e) {
        if (e.code != 'BAD_NONCE') rethrow;
        // Out of step: re-read the last nonce once and retry.
        s.nonce = (await api.state(s.signer.pubkey)).nonce;
        signed = await s.sign(action);
        res = await api.act(signed);
      }
      s.nonce = signed.nonce;
      if (action['type'] == 'sell') {
        ref.read(prefsProvider).setBool('tut_done', true);
      }
      state = AsyncData(
        await _load(
          res.events.isEmpty ? null : res.events.join(' / '),
          res.state,
        ),
      );
      if (before != null) {
        final book = TradeBook(ref.read(prefsProvider));
        final good = '${action['good']}';
        final qty = (action['qty'] as num?)?.toInt() ?? 0;
        if (action['type'] == 'buy') {
          book.bought(good, qty, before.pts - res.state.pts, before.day);
        } else if (action['type'] == 'sell') {
          _last = book.sold(good, qty, res.state.pts - before.pts, before.day);
        }
      }
      return null;
    } on ApiException catch (e) {
      if (e.code == 'BAD_NONCE') await refresh();
      if (e.message.startsWith('PRICE_')) {
        return errorSentence('PRICE_MOVED', ref.read(langProvider));
      }
      if (action['type'] == 'advance' &&
          (e.code == 'FORBIDDEN' || e.code == 'WRONG_PHASE')) {
        return clockMessage(ref.read(langProvider));
      }
      return friendlyError(e, ref.read(langProvider));
    }
  }
}

final gameProvider = AsyncNotifierProvider<GameNotifier, GameState>(
  GameNotifier.new,
);

/// The player's own chama, or null when they have not joined one.
final chamaProvider = FutureProvider<Chama?>((ref) async {
  final g = await ref.watch(gameProvider.future);
  final id = g.player.chamaId;
  if (id == null) return null;
  return ref.read(apiProvider).chama(id, g.player.playerId);
});

/// Chamas with room, for players who have not joined one.
final chamaListProvider = FutureProvider<List<ChamaSummary>>((ref) async {
  final g = await ref.watch(gameProvider.future);
  if (g.player.chamaId != null) return const [];
  return ref.read(apiProvider).chamas();
});

final ledgerDayProvider = NotifierProvider<LedgerDay, int?>(LedgerDay.new);

class LedgerDay extends Notifier<int?> {
  @override
  int? build() => null;
  void set(int d) => state = d;
}

final ledgerProvider = FutureProvider<DayLedger>((ref) async {
  final g = await ref.watch(gameProvider.future);
  final s = await ref.read(sessionProvider.future);
  final d = ref.watch(ledgerDayProvider) ?? g.player.day;
  return ref.read(apiProvider).ledger(s.signer.pubkey, d);
});

final reportProvider = FutureProvider<SokoReport>((ref) async {
  await ref.watch(gameProvider.future);
  final s = await ref.read(sessionProvider.future);
  return ref.read(apiProvider).report(s.signer.pubkey);
});

final boardProvider = FutureProvider<Leaderboard>((ref) async {
  final g = await ref.watch(gameProvider.future);
  return ref
      .read(apiProvider)
      .leaderboard(playerId: g.player.playerId, chamaId: g.player.chamaId);
});

/// Fast-forward preview: POST /v1/sim, never touches the player's game.
final simProvider = FutureProvider.family<List<SimFrame>, (int, String?)>((
  ref,
  a,
) async {
  final days = a.$1, kind = a.$2;
  return ref.read(apiProvider).sim(1, days, [
    if (kind != null) {'day': 2, 'kind': kind, 'magnitude': 30},
  ]);
});
