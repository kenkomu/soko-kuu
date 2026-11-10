import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

const _b58 = '123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz';

/// Base58 (Bitcoin alphabet), as used by NEAR for `ed25519:` public keys.
String base58Encode(List<int> bytes) {
  var zeros = 0;
  while (zeros < bytes.length && bytes[zeros] == 0) {
    zeros++;
  }
  var x = BigInt.zero;
  for (final b in bytes) {
    x = (x << 8) | BigInt.from(b);
  }
  final out = StringBuffer();
  final f = BigInt.from(58);
  final chars = <String>[];
  while (x > BigInt.zero) {
    chars.add(_b58[(x % f).toInt()]);
    x ~/= f;
  }
  for (var i = 0; i < zeros; i++) {
    out.write('1');
  }
  out.writeAll(chars.reversed);
  return out.toString();
}

/// Canonical JSON: object keys sorted (recursively), no whitespace.
String canonicalJson(Object? v) {
  if (v is Map) {
    final keys = v.keys.map((k) => k as String).toList()..sort();
    return '{${keys.map((k) => '${jsonEncode(k)}:${canonicalJson(v[k])}').join(',')}}';
  }
  if (v is List) return '[${v.map(canonicalJson).join(',')}]';
  return jsonEncode(v);
}

/// The exact bytes signed, per docs/API.md: the last field is the exact
/// `action_json` string that is also sent in the request body.
String signingMessageRaw({
  required String chainId,
  required String contractId,
  required String pubkey,
  required int nonce,
  required int expiresMs,
  required String actionJson,
}) => 'sokokuu/v1|$chainId|$contractId|$pubkey|$nonce|$expiresMs|$actionJson';

/// Convenience: canonicalises a map into action_json (sorted keys, no spaces).
String signingMessage({
  required String chainId,
  required String contractId,
  required String pubkey,
  required int nonce,
  required int expiresMs,
  required Map<String, dynamic> action,
}) => signingMessageRaw(
  chainId: chainId,
  contractId: contractId,
  pubkey: pubkey,
  nonce: nonce,
  expiresMs: expiresMs,
  actionJson: canonicalJson(action),
);

class Signer {
  Signer._(this._pair, this.pubkey, this.seed);
  final SimpleKeyPair _pair;
  final Uint8List seed;

  /// `ed25519:<base58 pubkey>`
  final String pubkey;

  static Future<Signer> fromSeed(List<int> seed) async {
    final pair = await Ed25519().newKeyPairFromSeed(seed);
    final pk = await pair.extractPublicKey();
    return Signer._(
      pair,
      'ed25519:${base58Encode(pk.bytes)}',
      Uint8List.fromList(seed),
    );
  }

  static Future<Signer> generate() async {
    final seed = await Ed25519().newKeyPair().then(
      (k) => k.extractPrivateKeyBytes(),
    );
    return fromSeed(seed);
  }

  Future<String> signBase64(String message) async {
    final sig = await Ed25519().sign(utf8.encode(message), keyPair: _pair);
    return base64.encode(sig.bytes);
  }
}
