import 'package:flutter_test/flutter_test.dart';
import 'package:soko_kuu/core/signing.dart';

// Reference vector generated with near-api-js (KeyPair.fromString + sign),
// seed = bytes 1..32. Re-generate with the script described in README.
const refPub = 'ed25519:9C6hybhQ6Aycep9jaUnP6uL9ZYvDjUp1aSkFWPUFJtpj';
const refMsg =
    'sokokuu/v1|testnet|sokokuu.testnet|ed25519:9C6hybhQ6Aycep9jaUnP6uL9ZYvDjUp1aSkFWPUFJtpj|42|1770000000000|{"good":"tomato","max_unit_price":3900,"merchant":"njeri","qty":3,"type":"buy"}';
const refSig =
    '4HR/iwG8OT4jMDhhK9vSPqWGcucCZVcYfa8F9OCyCDjh2prJEdZPVbAOd356V5T9hV+9AGi4d1hkat/CF3pSDw==';

void main() {
  test('Dart pubkey matches near-api-js', () async {
    final s = await Signer.fromSeed(List.generate(32, (i) => i + 1));
    expect(s.pubkey, refPub);
  });

  test('canonical message bytes match', () {
    final msg = signingMessage(
      chainId: 'testnet',
      contractId: 'sokokuu.testnet',
      pubkey: refPub,
      nonce: 42,
      expiresMs: 1770000000000,
      // deliberately unsorted input
      action: {
        'type': 'buy',
        'qty': 3,
        'merchant': 'njeri',
        'good': 'tomato',
        'max_unit_price': 3900,
      },
    );
    expect(msg, refMsg);
  });

  test('Dart signature equals near-api-js signature', () async {
    final s = await Signer.fromSeed(List.generate(32, (i) => i + 1));
    expect(await s.signBase64(refMsg), refSig);
  });

  test('nested canonical json sorts recursively', () {
    expect(
      canonicalJson({
        'b': 1,
        'a': {
          'z': [1, 2],
          'y': 'x',
        },
      }),
      '{"a":{"y":"x","z":[1,2]},"b":1}',
    );
  });
}
