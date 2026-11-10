import 'package:flutter_test/flutter_test.dart';
import 'package:soko_kuu/core/signing.dart';
import 'package:soko_kuu/domain/models.dart';
import 'package:soko_kuu/state/providers.dart';

void main() {
  test('signed string uses chain and contract ids from /v1/health', () async {
    final h = Health.fromJson({
      'version': '0.2.0',
      'chain_id': 'testnet',
      'contract_id': 'sokokuu.sokokuu-ken.testnet',
      'mode': 'testnet',
    });
    final signer = await Signer.fromSeed(List.generate(32, (i) => i + 1));
    final s = Session(signer, h.chainId, h.contractId)..nonce = 6;
    final a = await s.sign({'type': 'buy', 'qty': 1, 'good': 'tomato'});
    final expected =
        'sokokuu/v1|testnet|sokokuu.sokokuu-ken.testnet|${signer.pubkey}'
        '|7|${a.expiresMs}|${a.actionJson}';
    expect(a.sig, await signer.signBase64(expected));
    // a different contract id must give a different signature
    final other =
        'sokokuu/v1|testnet|sokokuu.testnet|${signer.pubkey}'
        '|7|${a.expiresMs}|${a.actionJson}';
    expect(a.sig, isNot(await signer.signBase64(other)));
  });
}
