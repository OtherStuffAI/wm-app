import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pointycastle/ecc/api.dart';
import 'package:wingman_app/src/core/nostr_crypto.dart';
import 'package:wingman_app/src/features/nstack/nstack_models.dart';

void main() {
  test('NBrowser namespace is the first valid deterministic secp256k1 x', () {
    const expectedX =
        '7d418aaf4a10c9460c1386596e8a0e42db73f92453118f46136e7ff4cc1e0f55';

    expect(nbrowserAppNamespaceDerivation,
        'sha256-counter-to-secp256k1-x:$nbrowserAppNamespaceLabel:0');
    expect(
      NostrCrypto.sha256Hex(utf8.encode('$nbrowserAppNamespaceLabel:0')),
      expectedX,
    );
    expect(NostrCrypto.publicKeyHexFromNpub(nbrowserAppNpub), expectedX);

    final compressedEvenPoint = <int>[0x02, ..._hexBytes(expectedX)];
    final point =
        ECDomainParameters('secp256k1').curve.decodePoint(compressedEvenPoint);
    expect(point, isNotNull);
    expect(point!.isInfinity, isFalse);
  });
}

List<int> _hexBytes(String value) => [
      for (var offset = 0; offset < value.length; offset += 2)
        int.parse(value.substring(offset, offset + 2), radix: 16),
    ];
